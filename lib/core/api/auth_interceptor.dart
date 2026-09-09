import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_repository.dart';
import 'api_client.dart';

/// Interceptor de autenticação (dio) com refresh single-flight (§7.3).
///
/// - `onRequest`: anexa `Authorization: Bearer <accessToken>` quando houver;
/// - `onError` com 401 (exceto rotas `/auth/` e requisições já retentadas
///   com `x-retry`): dispara refresh **single-flight** (Future compartilhado
///   no [AuthRepository]), repete a requisição original com o header
///   `x-retry: true`; se o refresh falhar, faz signOut local e volta o
///   estado de autenticação para deslogado — o redirect do router leva o
///   usuário para `/login`.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor(this._authRepo, this._ref);

  final AuthRepository _authRepo;
  final Ref _ref;

  /// Dio "nu" (sem interceptors) para o retry: o retry disparado DENTRO do
  /// `onError` do QueuedInterceptor que falhe de novo entraria na
  /// `_errorQueue` ATRÁS do erro original em processamento → espera
  /// circular (deadlock permanente — o erro original espera o retry, o
  /// retry espera seu task de erro; fila de interceptor não tem timeout).
  late final Dio _bareDio = _ref.read(apiBareClientProvider);

  /// Rotas que NÃO aceitam/necessitam de access token e, portanto, não devem
  /// disparar refresh-retry em 401. Atenção: `/auth/logout` e
  /// `/auth/change-password` NÃO estão aqui — exigem access válido e devem
  /// passar pelo refresh.
  static const _publicAuthPaths = <String>{
    '/auth/register',
    '/auth/login',
    '/auth/refresh',
  };

  /// True se o path da requisição é rota pública de auth. O dio mantém
  /// [RequestOptions.path] como passado na chamada (`/auth/login`) e expõe o
  /// path resolvido contra a baseUrl em [RequestOptions.uri] — cobre ambos.
  static bool _isPublicAuthPath(RequestOptions request) {
    return _publicAuthPaths.contains(request.path) ||
        _publicAuthPaths.contains(request.uri.path);
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _authRepo.accessToken;
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final request = err.requestOptions;
    final isPublicAuthPath = _isPublicAuthPath(request);
    if (err.response?.statusCode != 401 ||
        isPublicAuthPath ||
        request.headers['x-retry'] == 'true') {
      return handler.next(err);
    }
    // A fila do QueuedInterceptor só avança quando o handler completa; um
    // refresh/retry pendurado não pode segurar a fila de erros para sempre
    // (spinner infinito). Timeouts explícitos + conclusão garantida.
    var completed = false;
    try {
      final token = await _authRepo.refresh().timeout(
        const Duration(seconds: 15),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['x-retry'] = 'true';
      // Retry pelo dio BARE (fora da cadeia que originou o erro).
      final response = await _bareDio.fetch(request);
      completed = true;
      return handler.resolve(response);
    } catch (_) {
      try {
        await _authRepo.signOut().timeout(const Duration(seconds: 10));
      } catch (_) {
        // Logout best-effort; a sessão local é limpa mesmo sem backend.
      }
      try {
        _ref.read(authControllerProvider.notifier).setUnauthenticated();
      } catch (_) {}
      completed = true;
      return handler.next(err);
    } finally {
      if (!completed) {
        handler.next(err);
      }
    }
  }
}
