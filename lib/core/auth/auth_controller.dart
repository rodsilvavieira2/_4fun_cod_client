import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/websocket/socket_service.dart';
import 'auth_repository.dart';
import 'auth_state.dart';
import 'token_storage.dart';

/// Controller de autenticação — bootstrap de sessão + ações de login,
/// registro e logout (§7.2 do plano de arquitetura). Também sincroniza o
/// [SocketService] com a sessão: conecta com o accessToken ao autenticar e
/// desconecta no logout; handshake rejeitado (token inválido/expirado)
/// vira logout forçado.
class AuthController extends AsyncNotifier<AuthState> {
  bool _handlingSocketAuth = false;
  int _socketAuthRetries = 0;

  @override
  Future<AuthState> build() async {
    // Sinal de auth rejeitada pelo socket durante toda a vida do app:
    // token inválido/expirado no handshake ⇒ tenta renovar a sessão e
    // reconectar; só desloga se o refresh falhar (revogação real).
    final socket = ref.read(socketServiceProvider);
    final authFailures = socket.authFailures;
    final authFailureSub =
        authFailures.listen((_) => _handleSocketAuthFailure());
    ref.onDispose(authFailureSub.cancel);
    // Conexão bem-sucedida após recuperação: o teto de tentativas deixa de
    // ser um orçamento global da sessão (expiração normal de access token
    // não pode consumir tentativas de recuperação).
    final reconnectedSub =
        socket.reconnected.listen((_) => _socketAuthRetries = 0);
    ref.onDispose(reconnectedSub.cancel);

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
      await _connectSocket();
      return Authenticated(user: user);
    } catch (_) {
      // Falha de storage (ex.: Keystore Android invalidada após restore) ou
      // de refresh: trata como "sem sessão" — NUNCA deixa o app preso na
      // splash (o router manda para /login).
      ref.read(socketServiceProvider).disconnect();
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
    await _connectSocket();
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
    await _connectSocket();
  }

  Future<void> logout() async {
    ref.read(socketServiceProvider).disconnect();
    final repo = ref.read(authRepositoryProvider);
    try {
      await repo.signOut();
    } catch (_) {
      // signOut já é best-effort no remoto; nunca falha o logout local.
    }
    state = const AsyncData(Unauthenticated());
  }

  /// Conecta o socket com o accessToken atual (lido do storage seguro).
  Future<void> _connectSocket() async {
    final token = await ref.read(authRepositoryProvider).accessToken;
    if (token == null) return;
    _socketAuthRetries = 0;
    ref.read(socketServiceProvider).connect(token);
  }

  /// Handshake rejeitado: tenta refresh (token expirado após queda de rede)
  /// e reconecta com token novo; refresh falho ou excesso de tentativas
  /// (loop sem backoff) = revogação real → logout.
  Future<void> _handleSocketAuthFailure() async {
    if (_handlingSocketAuth) return;
    if (state.valueOrNull is! Authenticated) return;
    _handlingSocketAuth = true;
    try {
      if (_socketAuthRetries >= 3) {
        setUnauthenticated();
        return;
      }
      await ref.read(authRepositoryProvider).refresh();
      final token = await ref.read(authRepositoryProvider).accessToken;
      // Re-valida após os awaits: um logout/changePassword concorrente não
      // pode deixar o socket reconectar com sessão encerrada.
      if (token == null || state.valueOrNull is! Authenticated) {
        setUnauthenticated();
        return;
      }
      _socketAuthRetries++;
      ref.read(socketServiceProvider).connect(token);
    } catch (_) {
      setUnauthenticated();
    } finally {
      _handlingSocketAuth = false;
    }
  }

  /// Troca de senha (`POST /auth/change-password` — o backend revoga todas
  /// as sessões) e encerra a sessão local — o usuário precisa entrar
  /// novamente com a nova senha.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    await repo.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    ref.read(socketServiceProvider).disconnect();
    try {
      await repo.signOut();
    } catch (_) {
      // best-effort
    }
    state = const AsyncData(Unauthenticated());
  }

  /// Reflete no estado o logout forçado pelo interceptor (refresh falhou) ou
  /// pelo socket (handshake rejeitado) e encerra a conexão realtime.
  void setUnauthenticated() {
    if (state.valueOrNull is! Unauthenticated) {
      ref.read(socketServiceProvider).disconnect();
      state = const AsyncData(Unauthenticated());
    }
  }

  /// Edita nome/username via `PATCH /users/me` e reflete no estado.
  ///
  /// `clearAvatar: true` remove o avatar via storage service
  /// (`DELETE /users/me/avatar`).
  Future<void> updateProfile({
    String? name,
    String? username,
    bool clearAvatar = false,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    final updated = await repo.updateProfile(
      name: name,
      username: username,
      clearAvatar: clearAvatar,
    );
    state = AsyncData(Authenticated(user: updated));
  }
}

/// Provider do estado de autenticação.
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
