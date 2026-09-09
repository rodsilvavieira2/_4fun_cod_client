import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/auth_tokens.dart';
import '../../shared/models/user.dart';
import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/auth_interceptor.dart';
import '../storage/api_storage_service.dart';
import 'token_storage.dart';

/// Repositório de autenticação: identidade 100% no **backend** (NestJS —
/// e-mail/senha local + JWT próprio rotativo, §3.1), sem SDK de terceiros
/// de identidade em nenhuma camada.
class AuthRepository {
  AuthRepository(this._ref) {
    // Anexa o interceptor de refresh single-flight ao dio compartilhado.
    _dio.interceptors.add(AuthInterceptor(this, _ref));
  }

  final Ref _ref;

  late final Dio _dio = _ref.read(apiClientProvider);

  /// Dio "nu" (sem o AuthInterceptor) para refresh/logout — uma request
  /// aninhada no onError do QueuedInterceptor que falhe causa deadlock na
  /// _errorQueue (spinner infinito). Ver [apiBareClientProvider].
  late final Dio _bareDio = _ref.read(apiBareClientProvider);
  late final TokenStorage _tokenStorage = _ref.read(tokenStorageProvider);

  /// Access token em cache (após login/register/refresh). Evita a leitura
  /// síncrona do secure storage (libsecret/D-Bus) a CADA requisição — uma
  /// leitura que pendure no `onRequest` seguraria a fila do
  /// QueuedInterceptor para sempre (todas as requests seguintes travam).
  String? _accessTokenCache;

  /// Access token atual (nulo se não houver sessão).
  Future<String?> get accessToken async =>
      _accessTokenCache ??= await _tokenStorage.readAccessToken();

  /// Login com e-mail/senha: `POST /auth/login` → tokens de sessão.
  ///
  /// Credenciais inválidas → 404 do backend; orienta o cadastro.
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
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
    }
  }

  /// Cadastro: `POST /auth/register` com e-mail/senha local no backend
  /// (email/username duplicados → 409).
  Future<AuthSession> register({
    required String name,
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/register',
        data: {
          'name': name,
          'username': username,
          'email': email,
          'password': password,
        },
      );
      return _establishSession(response);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
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
    final response = await _bareDio.post(
      '/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    final tokens = SessionTokens.fromJson(
      response.data as Map<String, dynamic>,
    );
    await _tokenStorage.saveTokens(tokens);
    _accessTokenCache = tokens.accessToken;
    return tokens.accessToken;
  }

  /// Token de telemetria (opção A da release): opaco, por usuário, emitido
  /// pelo backend em `POST /telemetry/token` via sessão autenticada.
  ///
  /// Cacheado no secure storage e estável por meses de propósito — o
  /// exporter OTLP congela headers no init (sem re-init). `null` = sem
  /// sessão ou backend sem `TELEMETRY_TOKEN_SECRET` (telemetria tenta de
  /// novo no próximo start/login; nunca quebra o app).
  Future<String?> ensureTelemetryToken() async {
    final cached = await _tokenStorage.readTelemetryToken();
    if (cached != null && cached.isNotEmpty) return cached;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final access = await accessToken;
        if (access == null) return null;
        final response = await _bareDio.post(
          '/telemetry/token',
          options: Options(headers: {'Authorization': 'Bearer $access'}),
        );
        final token = (response.data as Map<String, dynamic>)['token'];
        if (token is String && token.isNotEmpty) {
          await _tokenStorage.saveTelemetryToken(token);
          return token;
        }
        return null;
      } on DioException catch (e) {
        if (e.response?.statusCode == 401 && attempt == 0) {
          try {
            await refresh();
            continue;
          } catch (_) {
            return null;
          }
        }
        return null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Logout completo: revoga o refresh no backend (best-effort) e limpa o
  /// armazenamento de tokens (inclui o token de telemetria).
  Future<void> signOut() async {
    try {
      final refreshToken = await _tokenStorage.readRefreshToken();
      if (refreshToken != null) {
        await _bareDio.post(
          '/auth/logout',
          data: {'refreshToken': refreshToken},
        );
      }
    } catch (_) {
      // Best-effort: backend indisponível não impede o logout local.
    }
    _accessTokenCache = null;
    await _tokenStorage.clear();
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

  /// Atualiza nome/username via `PATCH /users/me`.
  ///
  /// Avatar é responsabilidade do [StorageService] (multipart para o
  /// backend) — `clearAvatar: true` remove via `DELETE /users/me/avatar`.
  Future<User> updateProfile({
    String? name,
    String? username,
    bool clearAvatar = false,
  }) async {
    if (clearAvatar) {
      await _ref.read(storageServiceProvider).deleteAvatar();
    }
    final data = <String, dynamic>{'name': ?name, 'username': ?username};
    try {
      final response = await _dio.patch('/users/me', data: data);
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Troca de senha: `POST /auth/change-password` — o backend verifica a
  /// senha atual, grava o novo hash e **revoga TODAS as sessões** (tokens +
  /// realtime); o controller encerra a sessão local na sequência.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post(
        '/auth/change-password',
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Altera o e-mail de login após confirmar a senha atual. O backend mantém
  /// as sessões existentes, pois os tokens identificam somente o usuário.
  Future<User> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/change-email',
        data: {'currentPassword': currentPassword, 'newEmail': newEmail},
      );
      return User.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<AuthSession> _establishSession(Response<dynamic> response) async {
    final data = response.data as Map<String, dynamic>;
    final session = AuthSession(
      tokens: SessionTokens.fromJson(data),
      user: User.fromJson(data['user'] as Map<String, dynamic>),
    );
    await _tokenStorage.saveTokens(session.tokens);
    _accessTokenCache = session.tokens.accessToken;
    return session;
  }
}

/// Provider do repositório de autenticação (backend via dio).
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref),
);
