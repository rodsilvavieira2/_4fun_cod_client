import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configuração da aplicação, lida de `--dart-define` com defaults locais.
///
/// - `API_URL`: base URL da API NestJS (default `http://localhost:3000` — lab
///   sem Caddy; a API é publicada direto na 3000).
/// - `LIVEKIT_URL`: URL do servidor LiveKit (default `ws://localhost:7880`).
/// - `OTEL_ENDPOINT`: base do OpenObserve (default `http://localhost:5080` —
///   Fase 1, desktop Linux/Windows). Pode incluir o path da org
///   (`http://localhost:5080/api/default`); sem `/api/`, o sufixo
///   `/api/<OTEL_ORG>` é anexado pelo [TelemetryService].
/// - `OTEL_ORG`: organização do OpenObserve (default `default`).
/// - `OTEL_BASIC_AUTH`: `base64(email:senha)` para o header
///   `Authorization: Basic *** do OTLP (default vazio = sem auth).
///   NUNCA vai baked na release: lido de `--dart-define` (lab/dev) com
///   fallback para a env de runtime `OTEL_BASIC_AUTH` (desktop lê
///   `Platform.environment`). Nunca commitar valor real.
/// - `OTEL_ENABLED`: `true` liga a telemetria (default `false`).
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.livekitUrl,
    this.otelEndpoint = 'http://localhost:5080',
    this.otelOrg = 'default',
    this.otelBasicAuth = '',
    this.otelEnabled = false,
    // Opção A da release: OTLP via `POST <api>/api/v1/telemetria...` —
    // sem Basic do O2 no binário (P2); auth = token de telemetria do usuário.
    this.otelViaApi = false,
  });

  factory AppConfig.fromEnvironment() {
    const apiBaseUrl = String.fromEnvironment(
      'API_URL',
      defaultValue: 'http://localhost:3000',
    );
    const livekitUrl = String.fromEnvironment(
      'LIVEKIT_URL',
      defaultValue: 'ws://localhost:7880',
    );
    const otelEndpoint = String.fromEnvironment(
      'OTEL_ENDPOINT',
      defaultValue: 'http://localhost:5080',
    );
    const otelOrg = String.fromEnvironment('OTEL_ORG', defaultValue: 'default');
    const otelBasicAuthDefine = String.fromEnvironment(
      'OTEL_BASIC_AUTH',
      defaultValue: '',
    );
    // P2 (review t_34728661): credencial nunca baked no binário da release.
    // Lab/dev injeta via --dart-define; release distribuída lê da env de
    // runtime (ex.: `OTEL_BASIC_AUTH=... ./4fun-cod-*.AppImage`).
    final otelBasicAuth = otelBasicAuthDefine.isNotEmpty
        ? otelBasicAuthDefine
        : Platform.environment['OTEL_BASIC_AUTH'] ?? '';
    const otelEnabled = bool.fromEnvironment(
      'OTEL_ENABLED',
      defaultValue: false,
    );
    const otelViaApi = bool.fromEnvironment(
      'OTEL_VIA_API',
      defaultValue: false,
    );
    return AppConfig(
      apiBaseUrl: apiBaseUrl,
      livekitUrl: livekitUrl,
      otelEndpoint: otelEndpoint,
      otelOrg: otelOrg,
      otelBasicAuth: otelBasicAuth,
      otelEnabled: otelEnabled,
      otelViaApi: otelViaApi,
    );
  }

  /// Base URL da API NestJS — origem pura (ex. `http://localhost:3000`).
  final String apiBaseUrl;

  /// Base URL da API REST: origem + prefixo global `/api/v1` do NestJS
  /// (`app.setGlobalPrefix('api/v1')` no main.ts).
  ///
  /// O gateway Socket.IO NÃO herda o prefixo (mounta na raiz) — o
  /// [SocketService] deve usar [apiBaseUrl]; somente o dio usa esta.
  String get apiRestBaseUrl {
    final origin = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return origin.endsWith('/api/v1') ? origin : '$origin/api/v1';
  }

  /// URL do servidor LiveKit (WebSocket).
  final String livekitUrl;

  /// Base do OpenObserve (UI+API+OTLP) — Fase 1 desktop.
  final String otelEndpoint;

  /// Organização do OpenObserve usada no path OTLP (`/api/<org>/...`).
  final String otelOrg;

  /// `base64(email:senha)` do OpenObserve para o OTLP (lab local).
  final String otelBasicAuth;

  /// Telemetria ligada via `--dart-define=OTEL_ENABLED=true`.
  final bool otelEnabled;

  /// OTLP via proxy autenticado da API (`OTEL_VIA_API=true`, releases).
  final bool otelViaApi;
}

/// Provider de infraestrutura: expõe o [AppConfig] para toda a árvore.
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);
