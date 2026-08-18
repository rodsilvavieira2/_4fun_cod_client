import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_repository.dart';

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
  AuthInterceptor(this._authRepo, this._dio, this._ref);

  final AuthRepository _authRepo;
  final Dio _dio;
  final Ref _ref;

  /// Rotas que NÃO aceitam/necessitam de access token e, portanto, não devem
  /// disparar refresh-retry em 401. Atenção: `/auth/logout` e
  /// `/auth/revoke-sessions` NÃO estão aqui — exigem access válido e devem
  /// passar pelo refresh.
  static const _publicAuthPaths = <String>{
    '/auth/firebase/register',
    '/auth/firebase/login',
    '/auth/refresh',
  };

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
    final isPublicAuthPath = _publicAuthPaths.contains(request.path);
    if (err.response?.statusCode != 401 ||
        isPublicAuthPath ||
        request.headers['x-retry'] == 'true') {
      return handler.next(err);
    }
    try {
      final token = await _authRepo.refresh(); // single-flight
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['x-retry'] = 'true';
      final response = await _dio.fetch(request);
      return handler.resolve(response);
    } catch (_) {
      await _authRepo.signOut();
      try {
        _ref.read(authControllerProvider.notifier).setUnauthenticated();
      } catch (_) {
        // Bootstrap ainda em andamento: o catch do build() do
        // AuthController finaliza o estado como Unauthenticated.
      }
      handler.next(err);
    }
  }
}
