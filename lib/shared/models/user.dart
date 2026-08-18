/// Usuário espelhado da API (respostas de `/users/me`, `/users/:id` e
/// respostas de auth) — `shared/models` = DTOs espelhados (§6.2 do plano).
class User {
  const User({
    required this.id,
    required this.name,
    required this.username,
    required this.email,
    this.avatarUrl,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        name: json['name'] as String,
        username: json['username'] as String,
        email: json['email'] as String,
        avatarUrl: json['avatarUrl'] as String?,
      );

  final String id;
  final String name;
  final String username;
  final String email;
  final String? avatarUrl;
}
