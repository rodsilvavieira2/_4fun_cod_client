import 'package:dio/dio.dart';

import 'app_logger.dart';

/// Interceptor de log de todas as requisições HTTP do client.
///
/// Loga: método, path, status, duração e (em erro) o tipo do DioException —
/// **nunca** headers (Authorization), bodies de auth ou dados sensíveis.
/// Útil para diagnóstico: acompanhar exatamente o que o client chama e o
/// que responde, sem expor segredos.
class DioLoggingInterceptor extends Interceptor {
  DioLoggingInterceptor(this._log);

  final AppLogger _log;
  static const _tag = 'http';

  static final _sensitivePaths = <String>[
    '/auth/login',
    '/auth/register',
    '/auth/refresh',
    '/auth/logout',
    '/auth/change-email',
    '/auth/change-password',
  ];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['_logStart'] = DateTime.now();
    // Path já inclui o prefixo /api/v1 quando resolvido; loga o path cru.
    _log.d('→ ${options.method} ${options.path}', tag: _tag);
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final start = response.requestOptions.extra['_logStart'] as DateTime?;
    final elapsed = start == null
        ? ''
        : ' (${DateTime.now().difference(start).inMilliseconds}ms)';
    _log.d(
      '← ${response.statusCode} ${response.requestOptions.path}$elapsed',
      tag: _tag,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    final start = options.extra['_logStart'] as DateTime?;
    final elapsed = start == null
        ? ''
        : ' (${DateTime.now().difference(start).inMilliseconds}ms)';
    final isSensitive = _sensitivePaths.any(options.path.startsWith);
    final status = err.response?.statusCode;
    // Corpo apenas para rotas NÃO sensíveis e erros não-401 (401 de auth tem
    // corpo inócuo, mas melhor não arriscar); truncado.
    String? body;
    if (!isSensitive && status != null && status != 401) {
      final data = err.response?.data;
      if (data is String && data.isNotEmpty) {
        body = data.length > 300 ? '${data.substring(0, 300)}…' : data;
      }
    }
    _log.w(
      '✗ ${options.method} ${options.path} → ${err.type.name}'
      '${status != null ? ' [$status]' : ''}$elapsed'
      '${body == null ? '' : ' body=$body'}',
      tag: _tag,
    );
    handler.next(err);
  }
}
