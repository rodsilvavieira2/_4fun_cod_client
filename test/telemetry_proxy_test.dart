import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/config/app_config.dart';
import 'package:fourfun_cod_client/core/telemetry/telemetry_service.dart';

void main() {
  group('telemetria via API (opção A da release)', () {
    test('desligada por default (lab inalterado)', () {
      const config = AppConfig(
        apiBaseUrl: 'http://localhost:3000',
        livekitUrl: 'ws://localhost:7880',
      );
      expect(config.otelEnabled, isFalse);
      expect(config.otelViaApi, isFalse);
    });

    test('base do proxy casa com POST /telemetry/v1/*', () {
      expect(
        telemetryProxyBase('http://localhost:3000/api/v1'),
        'http://localhost:3000/api/v1/telemetry',
      );
      // Sem barra dupla quando a base termina com `/`.
      expect(
        telemetryProxyBase('https://api.4fun.gg/api/v1/'),
        'https://api.4fun.gg/api/v1/telemetry',
      );
    });

    test('exporter anexa o sinal à base (contrato do SDK)', () {
      // OtlpHttpExporterConfig anexa `/v1/<sinal>` quando ausente — o path
      // final precisa ser <api>/api/v1/telemetry/v1/logs.
      const signal = 'v1/logs';
      final full =
          '${telemetryProxyBase('https://api.4fun.gg/api/v1')}/$signal';
      expect(full, 'https://api.4fun.gg/api/v1/telemetry/v1/logs');
    });
  });
}
