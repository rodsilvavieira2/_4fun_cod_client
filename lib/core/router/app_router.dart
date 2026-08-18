import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';

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
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final authState = ref.read(authControllerProvider).valueOrNull;
      final location = state.matchedLocation;
      final isPublicAuthRoute = location == '/login' ||
          location == '/register' ||
          location == '/forgot-password';

      // Bootstrap ainda em andamento → splash.
      if (authState == null || authState is AuthUnknown) {
        return location == '/splash' ? null : '/splash';
      }
      if (authState is Unauthenticated) {
        return isPublicAuthRoute ? null : '/login';
      }
      // Authenticated.
      if (location == '/splash' || isPublicAuthRoute) {
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
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) => const ProfileScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    refreshStream.dispose();
    router.dispose();
  });
  return router;
});
