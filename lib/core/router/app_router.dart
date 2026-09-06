import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/dms/dm_shell_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/profile/profile_settings_redirect_screen.dart';
import '../../features/servers/invite_screen.dart';
import '../../features/servers/members_screen.dart';
import '../../features/servers/server_shell_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';
import '../logging/app_logger.dart';
import '../telemetry/telemetry_service.dart';

/// Observer de navegação: loga todas as transições de rota (diagnóstico).
class RouterLogObserver extends NavigatorObserver {
  RouterLogObserver(this._log);

  final AppLogger _log;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log.i(
      'navegação → ${route.settings.name ?? route.settings.toString()}',
      tag: 'router',
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _log.i(
      'navegação ← ${route.settings.name ?? route.settings.toString()}',
      tag: 'router',
    );
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _log.i(
      'navegação ⇄ ${newRoute?.settings.name ?? newRoute?.settings.toString()}',
      tag: 'router',
    );
  }
}

/// Repassa mudanças do [authControllerProvider] para o go_router via
/// [ChangeNotifier] — faz o redirect reavaliar quando o estado de auth muda
/// (login, logout, refresh-falhou, troca de senha).
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Ref ref) {
    // A assinatura é encerrada automaticamente pelo Riverpod quando o
    // routerProvider for destruído.
    ref.listen<AsyncValue<AuthState>>(
      authControllerProvider,
      (_, _) => notifyListeners(),
    );
  }
}

/// Router global com redirect por estado de autenticação (§7.2).
///
/// - AuthUnknown/loading → `/splash` (nada renderiza até o bootstrap);
/// - Unauthenticated → `/login` (exceto rotas públicas de auth);
/// - Authenticated → `/` (home); rotas de auth redirecionam para a home.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshStream = GoRouterRefreshStream(ref);
  final telemetry = ref.watch(telemetryServiceProvider);
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refreshStream,
    observers: [
      RouterLogObserver(ref.watch(appLoggerProvider)),
      telemetry.navigatorObserver(),
    ],
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider).valueOrNull;
      final location = state.matchedLocation;
      // Rotas públicas: fluxo de auth + deep link de convite (resolve sem
      // sessão; o aceite exige login e volta para cá).
      final isPublicRoute =
          location == '/login' ||
          location == '/register' ||
          location.startsWith('/invite/');

      // Bootstrap ainda em andamento → splash.
      if (authState == null || authState is AuthUnknown) {
        return location == '/splash' ? null : '/splash';
      }
      if (authState is Unauthenticated) {
        return isPublicRoute ? null : '/login';
      }
      // Authenticated: rotas de auth (e splash) redirecionam para a home;
      // /invite/:code continua acessível.
      if (location == '/splash' ||
          location == '/login' ||
          location == '/register') {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/dms',
        name: 'dms',
        builder: (context, state) => const DmShellScreen(),
      ),
      GoRoute(
        path: '/servers/:serverId',
        name: 'server-shell',
        builder: (context, state) =>
            ServerShellScreen(serverId: state.pathParameters['serverId']!),
      ),
      GoRoute(
        path: '/servers/:serverId/members',
        name: 'server-members',
        builder: (context, state) =>
            MembersScreen(serverId: state.pathParameters['serverId']!),
      ),
      GoRoute(
        path: '/invite/:code',
        name: 'invite',
        builder: (context, state) =>
            InviteScreen(code: state.pathParameters['code']!),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileSettingsRedirectScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    refreshStream.dispose();
    router.dispose();
  });
  return router;
});
