import '../../shared/models/user.dart';

/// Estado de autenticação da aplicação (§7.2 do plano de arquitetura).
sealed class AuthState {
  const AuthState();
}

/// Bootstrap ainda em andamento (tokens sendo validados) — tela splash.
class AuthUnknown extends AuthState {
  const AuthUnknown();
}

/// Usuário autenticado com sessão válida no backend.
class Authenticated extends AuthState {
  const Authenticated({required this.user});

  final User user;
}

/// Sem sessão válida — rotas protegidas redirecionam para /login.
class Unauthenticated extends AuthState {
  const Unauthenticated();
}
