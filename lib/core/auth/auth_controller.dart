import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'auth_state.dart';
import 'token_storage.dart';

/// Controller de autenticação — bootstrap de sessão + ações de login,
/// registro e logout (§7.2 do plano de arquitetura).
class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    // Bootstrap de sessão: se existe refresh token no storage, tenta
    // renovar a sessão em silêncio (rotação single-flight). Access expirado
    // em chamadas seguintes é coberto pelo interceptor.
    final storage = ref.read(tokenStorageProvider);
    final repo = ref.read(authRepositoryProvider);
    try {
      final hasRefreshToken = await storage.readRefreshToken() != null;
      if (!hasRefreshToken) return const Unauthenticated();

      await repo.refresh(); // silencioso; rotação do refresh token
      final user = await repo.getMe();
      return Authenticated(user: user);
    } catch (_) {
      // Falha de storage (ex.: Keystore Android invalidada após restore) ou
      // de refresh: trata como "sem sessão" — NUNCA deixa o app preso na
      // splash (o router manda para /login).
      try {
        await storage.clear();
      } catch (_) {
        // Storage inacessível: sem sessão de qualquer forma.
      }
      return const Unauthenticated();
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    final session = await repo.login(email: email, password: password);
    state = AsyncData(Authenticated(user: session.user));
  }

  Future<void> register({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    final session = await repo.register(
      name: name,
      username: username,
      email: email,
      password: password,
    );
    state = AsyncData(Authenticated(user: session.user));
  }

  Future<void> logout() async {
    final repo = ref.read(authRepositoryProvider);
    try {
      await repo.signOut();
    } catch (_) {
      // signOut já é best-effort no remoto; nunca falha o logout local.
    }
    state = const AsyncData(Unauthenticated());
  }

  /// Troca de senha (Firebase + revoke-sessions) e encerra a sessão local —
  /// todas as sessões foram revogadas no backend, então o usuário precisa
  /// entrar novamente com a nova senha.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    try {
      await repo.signOut();
    } catch (_) {
      // best-effort
    }
    state = const AsyncData(Unauthenticated());
  }

  /// Redefinição de senha via e-mail (100% Firebase).
  Future<void> sendPasswordResetEmail(String email) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.sendPasswordResetEmail(email);
  }

  /// Reflete no estado o logout forçado pelo interceptor (refresh falhou).
  void setUnauthenticated() {
    if (state.valueOrNull is! Unauthenticated) {
      state = const AsyncData(Unauthenticated());
    }
  }

  /// Edita nome/username/avatar via `PATCH /users/me` e reflete no estado.
  Future<void> updateProfile({
    String? name,
    String? username,
    String? avatarUrl,
    bool clearAvatar = false,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    final updated = await repo.updateProfile(
      name: name,
      username: username,
      avatarUrl: avatarUrl,
      clearAvatar: clearAvatar,
    );
    state = AsyncData(Authenticated(user: updated));
  }
}

/// Provider do estado de autenticação.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
