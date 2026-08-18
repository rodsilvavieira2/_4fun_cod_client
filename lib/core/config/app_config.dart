import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configuração da aplicação, lida de `--dart-define` com defaults locais.
///
/// - `API_URL`: base URL da API NestJS (default `http://localhost`).
/// - `LIVEKIT_URL`: URL do servidor LiveKit (default `ws://localhost:7880`).
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.livekitUrl,
  });

  factory AppConfig.fromEnvironment() {
    const apiBaseUrl = String.fromEnvironment(
      'API_URL',
      defaultValue: 'http://localhost',
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

  /// Base URL da API NestJS.
  final String apiBaseUrl;

  /// URL do servidor LiveKit (WebSocket).
  final String livekitUrl;
}

/// Provider de infraestrutura: expõe o [AppConfig] para toda a árvore.
final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);
