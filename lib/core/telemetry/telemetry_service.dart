import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';

/// Observabilidade do client (OpenObserve no lab, desktop Linux/Windows).
///
/// Motor: `dartastic_opentelemetry` puro via OTLP/HTTP (sem `flutterrific`,
/// que exigiria `go_router ^14` contra o `^17` do app — ver spec).
/// Quando `OTEL_ENABLED=false` (default) tudo é no-op além do log local;
/// nenhuma falha do SDK pode quebrar o app (todos os toques OTel têm
/// try/catch e o log local continua intacto).
class TelemetryService {
  TelemetryService(this._log, this._config);

  static const _scope = 'fourfun-cod-client';

  final AppLogger _log;
  final AppConfig _config;

  bool _ready = false;

  /// `id` do usuário autenticado (só o id — nunca nome/email/username,
  /// pela redação estrita do grill). Injetado como atributo `user_id` em
  /// todos os eventos/spans seguintes; null = deslogado.
  String? _userId;

  /// Vincula/desvincula o usuário atual (chamado pelo `App` ao observar o
  /// `authControllerProvider`). Seguro chamar com OTel desligado.
  void setUser(String? userId) {
    if (_userId == userId) return;
    _userId = (userId == null || userId.isEmpty) ? null : userId;
  }

  /// Endpoint OTLP/HTTP efetivo (ex. `http://localhost:5080`).
  String get endpoint => _config.otelEndpoint;

  /// Habilitado via `--dart-define=OTEL_ENABLED=true` (lab/dev).
  bool get enabled => _config.otelEnabled;

  bool get ready => _ready;

  /// Base OTLP do OpenObserve: `<endpoint>/api/<org>` — o exporter anexa
  /// `v1/traces` / `v1/logs`. Se o endpoint já vier com `/api/`, usa cru.
  String get _otlpBase {
    final base = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    if (base.contains('/api/')) return base;
    return '$base/api/${_config.otelOrg}';
  }

  /// Header `Authorization: Basic ...` quando `OTEL_BASIC_AUTH` vier
  /// preenchido (lab); vazio = sem auth.
  Map<String, String> get _headers {
    final basic = _config.otelBasicAuth;
    if (basic.isEmpty) return const {};
    return {'Authorization': 'Basic $basic'};
  }

  /// Chamado uma vez no `App.build` (fire-and-forget). Idempotente.
  Future<void> init() async {
    if (!enabled || _ready) return;
    try {
      // Batch = envio em lote em background; exporter com retry limitado
      // (3x + backoff) — se o OpenObserve cair, o lote é descartado sem
      // travar a UI (drop offline do grill). Métricas ficam para a Fase 1c.
      await OTel.initialize(
        serviceName: _scope,
        serviceVersion: '1.0.0',
        endpoint: _otlpBase,
        spanProcessor: BatchSpanProcessor(
          OtlpHttpSpanExporter(
            OtlpHttpExporterConfig(endpoint: _otlpBase, headers: _headers),
          ),
        ),
        logRecordExporter: OtlpHttpLogRecordExporter(
          OtlpHttpLogRecordExporterConfig(
            endpoint: _otlpBase,
            headers: _headers,
          ),
        ),
        metricExporter: OtlpHttpMetricExporter(
          OtlpHttpMetricExporterConfig(endpoint: _otlpBase, headers: _headers),
        ),
        enableMetrics: true,
      );
      _ready = true;
      _log.i('telemetria ligada → $endpoint', tag: 'otel');
    } catch (e) {
      _log.w('otel init falhou (só log local): $e', tag: 'otel');
    }
  }

  /// Evento estruturado: sempre no log local + OTel quando pronto.
  void logEvent(String name, {Map<String, String>? attributes}) {
    final attrs = _withUser(_redactAttributes(attributes ?? const {}));
    _log.i('otel event $name $attrs', tag: 'otel');
    if (!_ready) return;
    try {
      OTel.logger(_scope).emit(
        body: '$name $attrs',
        severityText: 'INFO',
        eventName: name,
        attributes: Attributes.of(attrs),
      );
    } catch (_) {
      // Telemetria nunca quebra o app.
    }
  }

  /// Erro com contexto: log local + evento OTel de severidade ERROR.
  void reportError(String context, Object error, [StackTrace? stack]) {
    _log.e('otel error $context', error: error, stackTrace: stack, tag: 'otel');
    if (!_ready) return;
    try {
      OTel.logger(_scope).emit(
        body: '$context: ${_redact(error.toString())}',
        severityText: 'ERROR',
        eventName: 'error',
        attributes: Attributes.of(_withUser({'context': context})),
      );
    } catch (_) {}
  }

  /// Abre um span (ex. HTTP). Retorna null quando desligado/falha.
  Span? startSpan(String name, {Map<String, String>? attributes}) {
    if (!_ready) return null;
    try {
      return OTel.tracerProvider()
          .getTracer(_scope)
          .startSpan(
            name,
            kind: SpanKind.client,
            attributes: Attributes.of(
              _withUser(_redactAttributes(attributes ?? const {})),
            ),
          );
    } catch (_) {
      return null;
    }
  }

  /// Fecha um span, marcando erro quando houver.
  void endSpan(Span? span, {Object? error, StackTrace? stackTrace}) {
    if (span == null) return;
    try {
      if (error != null) {
        span.recordException(error, stackTrace: stackTrace);
        span.setStatus(SpanStatusCode.Error, _redact(error.toString()));
      }
      span.end();
    } catch (_) {}
  }

  /// Observer de navegação plugável no `go_router` (ao lado do
  /// `RouterLogObserver` existente). Só envia o NOME da rota, nunca
  /// argumentos/query — redação estrita do grill.
  NavigatorObserver navigatorObserver() => _TelemetryRouteObserver(this);

  // -- Métricas (Fase 1c) -------------------------------------------------
  // Instrumentos lazy sobre um único Meter; sem `user_id` de propósito
  // (métricas = agregados de baixa cardinalidade; o drill por usuário
  // continua nos logs/traces). Atributos: só nomes de rota, métodos e
  // status — nunca paths com UUID.

  Meter? _meter;
  APICounter<int>? _navCounter;
  APICounter<int>? _httpCounter;
  APIHistogram<double>? _httpDuration;

  Meter? get _m {
    if (!_ready) return null;
    try {
      return _meter ??= OTel.meter(_scope);
    } catch (_) {
      return null;
    }
  }

  /// Conta um `navigation.push` por nome de rota.
  void countNavigation(String route) {
    try {
      final meter = _m;
      if (meter == null) return;
      _navCounter ??= meter.createCounter<int>(
        name: 'navigation.push',
        description: 'Telas visitadas por rota',
      );
      _navCounter!.add(1, Attributes.of({'route': route}));
    } catch (_) {}
  }

  /// Conta a request e registra a duração (ms) — método + status apenas.
  void recordHttpRequest({
    required String method,
    required double durationMs,
    int? statusCode,
  }) {
    try {
      final meter = _m;
      if (meter == null) return;
      final attrs = Attributes.of({
        'http.method': method,
        'http.status_code': '${statusCode ?? 0}',
      });
      _httpCounter ??= meter.createCounter<int>(
        name: 'http.client.requests',
        description: 'Requisições HTTP do client',
      );
      _httpCounter!.add(1, attrs);
      _httpDuration ??= meter.createHistogram<double>(
        name: 'http.client.request.duration',
        unit: 'ms',
        description: 'Duração das requisições HTTP do client',
      );
      _httpDuration!.record(durationMs, attrs);
    } catch (_) {}
  }

  /// Soma `user_id` aos atributos quando há usuário vinculado. Chamador
  /// nunca sobrescreve: um `user_id` explícito no mapa vence (defesa).
  Map<String, String> _withUser(Map<String, String> attrs) {
    final id = _userId;
    if (id == null || attrs.containsKey('user_id')) return attrs;
    return {...attrs, 'user_id': id};
  }

  static Map<String, String> _redactAttributes(Map<String, String> input) {
    final out = <String, String>{};
    for (final e in input.entries) {
      final k = e.key.toLowerCase();
      if (k.contains('token') ||
          k.contains('password') ||
          k.contains('secret') ||
          k.contains('auth')) {
        out[e.key] = '***';
      } else {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  /// Mesma redação do [AppLogger] para corpos de erro.
  static String _redact(String input) {
    var out = input.replaceAllMapped(
      RegExp(r'Bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false),
      (_) => 'Bearer ***',
    );
    out = out.replaceAllMapped(
      RegExp(
        r'("(?:password|token|secret|refreshToken)"\s*:\s*")[^"]*(")',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}***${m.group(2)}',
    );
    return out;
  }
}

/// Observer magro: registra navegação como evento de telemetria.
class _TelemetryRouteObserver extends NavigatorObserver {
  _TelemetryRouteObserver(this._telemetry);

  final TelemetryService _telemetry;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name ?? 'unknown';
    _telemetry.logEvent('navigation.push', attributes: {'route': name});
    _telemetry.countNavigation(name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _telemetry.logEvent(
      'navigation.pop',
      attributes: {'route': route.settings.name ?? 'unknown'},
    );
  }
}

final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  return TelemetryService(
    ref.watch(appLoggerProvider),
    ref.watch(appConfigProvider),
  );
});
