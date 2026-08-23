import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configuração da aplicação, lida de `--dart-define` com defaults locais.
///
/// - `API_URL`: base URL da API NestJS (default `http://localhost:3000` — lab
///   sem Caddy; a API é publicada direto na 3000).
/// - `LIVEKIT_URL`: URL do servidor LiveKit (default `ws://localhost:7880`).
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.livekitUrl,
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
    return const AppConfig(
      apiBaseUrl: apiBaseUrl,
      livekitUrl: livekitUrl,
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
}

/// Provider de infraestrutura: expõe o [AppConfig] para toda a árvore.
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);
