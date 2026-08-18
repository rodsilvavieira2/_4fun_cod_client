import 'package:go_router/go_router.dart';

import '../../features/auth/login_screen.dart';
import '../../features/home/home_screen.dart';

/// Router global da aplicação (go_router).
///
/// Rotas mínimas da Fase 0:
/// - `/`      -> home provisória
/// - `/login` -> tela de login placeholder
///
/// TODO(task 1 - auth): implementar redirect por estado de autenticação
/// (AuthState, seção 7.2 do plano de arquitetura):
///   AuthUnknown      -> splash (nada renderiza)
///   Unauthenticated  -> /login (exceto /invite/:code)
///   Authenticated    -> /home, /servers/:id/channels/:channelId
///
/// Exemplo de onde o redirect entrará:
/// ```dart
/// redirect: (context, state) {
///   final authState = ...; // lido via ref (authControllerProvider)
///   final isLoginRoute = state.matchedLocation == '/login';
///   ...
///   return null;
/// },
/// ```
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (context, state) => const LoginScreen(),
    ),
  ],
);
