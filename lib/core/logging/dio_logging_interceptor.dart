import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dio/dio.dart';

import '../telemetry/telemetry_service.dart';
import 'app_logger.dart';

/// Interceptor de log de todas as requisições HTTP do client.
///
/// Loga: método, path, status, duração e (em erro) o tipo do DioException —
/// **nunca** headers (Authorization), bodies de auth ou dados sensíveis.
/// Útil para diagnóstico: acompanhar exatamente o que o client chama e o
/// que responde, sem expor segredos.
///
/// Com telemetria ligada (`OTEL_ENABLED=true`), abre um span OTel por
/// request (fechado na resposta/erro) — sem telemetria, comportamento
/// idêntico ao anterior (só log local).
class DioLoggingInterceptor extends Interceptor {
  DioLoggingInterceptor(this._log, [this._telemetry]);

  final AppLogger _log;
  final TelemetryService? _telemetry;
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
    final telemetry = _telemetry;
    if (telemetry != null) {
      options.extra['_otelSpan'] = telemetry.startSpan(
        '${options.method} ${options.path}',
        attributes: {
          'http.method': options.method,
          'http.path': options.path,
        },
      );
    }
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
    _endSpan(response.requestOptions);
    _recordMetrics(response.requestOptions, response.statusCode);
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
    _endSpan(options, error: err);
    _recordMetrics(options, status);
    // Erros 5xx/sem-resposta viram evento OTel ERROR; 4xx de rotina (ex.
    // 401 do refresh) ficam só no log local para não gerar ruído.
    if (status == null || status >= 500) {
      _telemetry?.reportError('http ${options.method} ${options.path}', err);
    }
    handler.next(err);
  }

  void _endSpan(RequestOptions options, {Object? error}) {
    final span = options.extra.remove('_otelSpan') as Span?;
    _telemetry?.endSpan(span, error: error);
  }

  void _recordMetrics(RequestOptions options, int? statusCode) {
    final start = options.extra['_logStart'] as DateTime?;
    if (start == null) return;
    _telemetry?.recordHttpRequest(
      method: options.method,
      durationMs: DateTime.now().difference(start).inMilliseconds.toDouble(),
      statusCode: statusCode,
    );
  }
}
