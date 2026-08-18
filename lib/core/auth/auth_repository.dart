import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' hide User;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/auth_tokens.dart';
import '../../shared/models/user.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/auth_interceptor.dart';
import 'token_storage.dart';

/// Repositório de autenticação: identidade no **Firebase Auth** (client-side)
/// + sessão própria do **backend** (JWT access/refresh rotativo, §3.1).
///
/// Único lugar (junto de `core/auth`) que importa `firebase_auth` — a UI
/// nunca importa Firebase diretamente.
class AuthRepository {
  AuthRepository(this._ref) {
    // Anexa o interceptor de refresh single-flight ao dio compartilhado.
    _dio.interceptors.add(AuthInterceptor(this, _dio, _ref));
  }

  final Ref _ref;

  late final Dio _dio = _ref.read(apiClientProvider);
  late final TokenStorage _tokenStorage = _ref.read(tokenStorageProvider);
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  /// Access token atual (nulo se não houver sessão).
  Future<String?> get accessToken => _tokenStorage.readAccessToken();

  /// Login híbrido: Firebase Auth (email/senha) → ID token →
  /// `POST /auth/firebase/login` → tokens de sessão do backend.
  ///
  /// Se o backend não encontrar o User (404), orienta o cadastro.
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw const ApiException(message: 'Não foi possível autenticar. Tente novamente.');
      }
      final idToken = await firebaseUser.getIdToken();
      final response = await _dio.post(
        '/auth/firebase/login',
        data: {'idToken': idToken},
      );
      return _establishSession(response);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const ApiException(
          message: 'Conta não encontrada. Cadastre-se antes de entrar.',
          statusCode: 404,
        );
      }
      throw ApiException.fromDio(e);
    } on FirebaseAuthException catch (e) {
      throw ApiException(message: _firebaseAuthErrorMessage(e));
    }
  }

  /// Cadastro híbrido: Firebase Auth → ID token →
  /// `POST /auth/firebase/register` (idempotente por `firebaseUid`).
  Future<AuthSession> register({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw const ApiException(message: 'Não foi possível criar a conta. Tente novamente.');
      }
      final idToken = await firebaseUser.getIdToken();
      final response = await _dio.post(
        '/auth/firebase/register',
        data: {'idToken': idToken, 'name': name, 'username': username},
      );
      return _establishSession(response);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on FirebaseAuthException catch (e) {
      throw ApiException(message: _firebaseAuthErrorMessage(e));
    }
  }

  Future<String>? _refreshInFlight;

  /// Renova o access token via `POST /auth/refresh` (rotação do refresh).
  ///
  /// **Single-flight:** chamadas concorrentes compartilham o mesmo Future —
  /// apenas uma requisição de refresh é feita por vez.
  Future<String> refresh() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final future = _doRefresh();
    _refreshInFlight = future;
    future.whenComplete(() => _refreshInFlight = null);
    return future;
  }

  Future<String> _doRefresh() async {
    final refreshToken = await _tokenStorage.readRefreshToken();
    if (refreshToken == null) {
      throw const ApiException(
        message: 'Sessão expirada. Faça login novamente.',
        statusCode: 401,
      );
    }
    final response = await _dio.post(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    final tokens = SessionTokens.fromJson(response.data as Map<String, dynamic>);
    await _tokenStorage.saveTokens(tokens);
    return tokens.accessToken;
  }

  /// Logout completo: revoga o refresh no backend (best-effort), encerra a
  /// sessão no Firebase e limpa o armazenamento de tokens.
  Future<void> signOut() async {
    try {
      final refreshToken = await _tokenStorage.readRefreshToken();
      if (refreshToken != null) {
        await _dio.post('/auth/logout', data: {'refreshToken': refreshToken});
      }
    } catch (_) {
      // Best-effort: backend indisponível não impede o logout local.
    }
    await _firebaseAuth.signOut();
    await _tokenStorage.clear();
  }

  /// Revoga TODAS as sessões do usuário no backend (após troca de senha).
  Future<void> revokeSessions() async {
    try {
      await _dio.post('/auth/revoke-sessions');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Perfil do usuário autenticado (`GET /users/me`).
  Future<User> getMe() async {
    try {
      final response = await _dio.get('/users/me');
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Atualiza nome/username/avatarUrl via `PATCH /users/me`.
  ///
  /// `clearAvatar: true` envia `avatarUrl: null` (remove o avatar).
  Future<User> updateProfile({
    String? name,
    String? username,
    String? avatarUrl,
    bool clearAvatar = false,
  }) async {
    final data = <String, dynamic>{
      'name': ?name,
      'username': ?username,
      if (clearAvatar) 'avatarUrl': null else 'avatarUrl': ?avatarUrl,
    };
    try {
      final response = await _dio.patch('/users/me', data: data);
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Redefinição de senha 100% no Firebase (`sendPasswordResetEmail`).
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw ApiException(message: _firebaseAuthErrorMessage(e));
    }
  }

  /// Troca de senha: reauth + `updatePassword` no Firebase e depois
  /// `POST /auth/revoke-sessions` (derruba todas as sessões do backend).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final firebaseUser = _firebaseAuth.currentUser;
    final email = firebaseUser?.email;
    if (firebaseUser == null || email == null) {
      throw const ApiException(message: 'Sessão expirada. Faça login novamente.');
    }
    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await firebaseUser.reauthenticateWithCredential(credential);
      await firebaseUser.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw ApiException(message: _firebaseAuthErrorMessage(e));
    }
    await revokeSessions();
  }

  Future<AuthSession> _establishSession(Response<dynamic> response) async {
    final data = response.data as Map<String, dynamic>;
    final session = AuthSession(
      tokens: SessionTokens.fromJson(data),
      user: User.fromJson(data['user'] as Map<String, dynamic>),
    );
    await _tokenStorage.saveTokens(session.tokens);
    return session;
  }

  String _firebaseAuthErrorMessage(FirebaseAuthException e) {
    return switch (e.code) {
      'invalid-email' => 'E-mail inválido.',
      'user-not-found' ||
      'invalid-credential' ||
      'wrong-password' =>
        'E-mail ou senha incorretos.',
      'email-already-in-use' => 'Este e-mail já está cadastrado.',
      'weak-password' => 'Senha muito fraca.',
      'user-disabled' => 'Conta desativada.',
      'too-many-requests' => 'Muitas tentativas. Aguarde um pouco e tente novamente.',
      'network-request-failed' => 'Sem conexão com a rede.',
      'requires-recent-login' => 'Sessão expirada. Faça login novamente.',
      _ => e.message ?? 'Erro de autenticação.',
    };
  }
}

/// Provider do repositório de autenticação (Firebase + backend).
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref),
);
