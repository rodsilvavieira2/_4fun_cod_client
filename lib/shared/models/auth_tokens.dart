import 'user.dart';

/// Par de tokens de sessão emitidos pelo backend (JWT próprio).
///
/// Espelha a resposta de `/auth/login`, `/auth/register` e `/auth/refresh`
/// (§3.1 do plano de arquitetura).
class SessionTokens {
  const SessionTokens({required this.accessToken, required this.refreshToken});

  factory SessionTokens.fromJson(Map<String, dynamic> json) => SessionTokens(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
  );

  final String accessToken;
  final String refreshToken;
}

/// Sessão completa: tokens + usuário autenticado.
class AuthSession {
  const AuthSession({required this.tokens, required this.user});

  final SessionTokens tokens;
  final User user;
}
