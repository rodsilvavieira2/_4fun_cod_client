import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart'
    show VideoParametersPresets;

import 'package:fourfun_cod_client/core/rtc/livekit_rtc_service.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';

/// Testes da função PURA [cameraQualityOptions] (Fase 7): mapping perfil →
/// (CameraCaptureOptions, VideoPublishOptions). Confere dimensões/fps das
/// capturas e as camadas simulcast de cada perfil contra a tabela da SPEC.
void main() {
  group('cameraNeedsRepublish (fix CRÍTICO do review)', () {
    test('sem publicação → sempre republica (1ª ligada)', () {
      expect(
        cameraNeedsRepublish(
          hasPublication: false,
          pending: RtcCameraQuality.auto,
          applied: RtcCameraQuality.auto,
        ),
        isTrue,
      );
    });

    test('publicação existe e perfil pendente == aplicado → só unmute', () {
      expect(
        cameraNeedsRepublish(
          hasPublication: true,
          pending: RtcCameraQuality.q1080,
          applied: RtcCameraQuality.q1080,
        ),
        isFalse,
      );
    });

    test('publicação existe e perfil pendente != aplicado → republica '
        '(desligou→trocou perfil→religou)', () {
      expect(
        cameraNeedsRepublish(
          hasPublication: true,
          pending: RtcCameraQuality.q720,
          applied: RtcCameraQuality.auto,
        ),
        isTrue,
        reason: 'perfil trocado com a câmera OFF não pode ser descartado '
            'ao religar (fix do review)');
    });
  });

  group('cameraQualityOptions', () {
    test('auto e q1080 compartilham o teto 1080p@60 com simulcast h180/h540/h1080_60',
        () {
      for (final quality in [RtcCameraQuality.auto, RtcCameraQuality.q1080]) {
        final (capture, publish) = cameraQualityOptions(quality);
        expect(capture.params, LiveKitRtcService.h1080_60,
            reason: '$quality captura em 1080p60');
        expect(capture.params.encoding!.maxFramerate, 60,
            reason: '$quality — teto 60fps (preset custom)');
        expect(capture.params.dimensions.width, 1920);
        expect(capture.params.dimensions.height, 1080);
        expect(publish.simulcast, isTrue,
            reason: '$quality mantém simulcast (dynacast precisa dele)');
        expect(publish.videoSimulcastLayers, hasLength(3));
        expect(publish.videoSimulcastLayers.last, LiveKitRtcService.h1080_60,
            reason: '$quality — topo é a camada 1080p60');
      }
    });

    test('q720 captura 720p@30 com simulcast h180/h360/h720', () {
      final (capture, publish) = cameraQualityOptions(RtcCameraQuality.q720);
      expect(capture.params, VideoParametersPresets.h720_169);
      expect(capture.params.encoding!.maxFramerate, 30);
      expect(capture.params.dimensions.height, 720);
      expect(publish.simulcast, isTrue);
      expect(publish.videoSimulcastLayers, hasLength(3));
      expect(publish.videoSimulcastLayers.last, VideoParametersPresets.h720_169,
          reason: 'topo do perfil 720p é a camada 720p');
    });

    test('q480 captura 480p 16:9 com simulcast h180/h360/h480', () {
      final (capture, publish) = cameraQualityOptions(RtcCameraQuality.q480);
      expect(capture.params, LiveKitRtcService.h480_169,
          reason: '480p 16:9 é custom (SDK só tem 4:3)');
      expect(capture.params.dimensions.height, 480);
      expect(capture.params.encoding!.maxFramerate, 30);
      expect(publish.simulcast, isTrue);
      expect(publish.videoSimulcastLayers, hasLength(3));
      expect(publish.videoSimulcastLayers.last, LiveKitRtcService.h480_169);
    });

    test('q360/q240/q144 caem para 1 camada (simulcast desligado)', () {
      for (final quality in [
        RtcCameraQuality.q360,
        RtcCameraQuality.q240,
        RtcCameraQuality.q144,
      ]) {
        final (capture, publish) = cameraQualityOptions(quality);
        expect(publish.simulcast, isFalse,
            reason: '$quality — simulcast perde o valor abaixo de 480p');
        expect(publish.videoEncoding, isNotNull,
            reason: '$quality — 1 camada usa videoEncoding explícito');
        expect(capture.params.dimensions.height, switch (quality) {
          RtcCameraQuality.q360 => 360,
          RtcCameraQuality.q240 => 240,
          _ => 144,
        });
      }
    });

    test('todos os perfis cobrem todos os enums (sem default implícito)', () {
      // Se um enum novo for adicionado sem caso, o switch não-exaustivo
      // quebra a compilação — este teste garante que a função retorna para
      // TODOS os valores atuais.
      for (final quality in RtcCameraQuality.values) {
        expect(cameraQualityOptions(quality), isNotNull);
      }
    });
  });
}
