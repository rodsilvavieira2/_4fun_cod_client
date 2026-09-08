import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart'
    show ScreenShareCaptureOptions, VideoParametersPresets;

import 'package:fourfun_cod_client/core/rtc/livekit_rtc_service.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';

void main() {
  group('screenShareQualityProfile', () {
    test('mapeia exatamente os seis perfis', () {
      expect(
        screenShareQualityProfile(RtcScreenShareQuality.auto),
        const ScreenShareQualityProfile(
          scaleResolutionDownBy: 1,
          maxFramerate: 15,
          maxBitrate: 2500000,
        ),
      );
      expect(
        screenShareQualityProfile(RtcScreenShareQuality.q1080p60),
        const ScreenShareQualityProfile(
          scaleResolutionDownBy: 1,
          maxFramerate: 60,
          maxBitrate: 8000000,
        ),
      );
      expect(
        screenShareQualityProfile(RtcScreenShareQuality.q1080p30),
        const ScreenShareQualityProfile(
          scaleResolutionDownBy: 1,
          maxFramerate: 30,
          maxBitrate: 5000000,
        ),
      );
      expect(
        screenShareQualityProfile(RtcScreenShareQuality.q1080p15),
        const ScreenShareQualityProfile(
          scaleResolutionDownBy: 1,
          maxFramerate: 15,
          maxBitrate: 2500000,
        ),
      );
      expect(
        screenShareQualityProfile(RtcScreenShareQuality.q720p15),
        const ScreenShareQualityProfile(
          scaleResolutionDownBy: 1.5,
          maxFramerate: 15,
          maxBitrate: 1500000,
        ),
      );
      expect(
        screenShareQualityProfile(RtcScreenShareQuality.q360p3),
        const ScreenShareQualityProfile(
          scaleResolutionDownBy: 3,
          maxFramerate: 3,
          maxBitrate: 200000,
        ),
      );
    });
  });

  group('screenShareQualityEncodings', () {
    final baseline = [
      rtc.RTCRtpEncoding(
        rid: 'low',
        active: true,
        scaleResolutionDownBy: 2,
        maxBitrate: 625000,
        maxFramerate: 15,
        ssrc: 11,
      ),
      rtc.RTCRtpEncoding(
        rid: 'high',
        active: false,
        scaleResolutionDownBy: 1,
        maxBitrate: 2500000,
        maxFramerate: 15,
        ssrc: 22,
      ),
    ];

    test('transforma resolução, fps e bitrate proporcionalmente', () {
      final expected = <RtcScreenShareQuality, List<num>>{
        RtcScreenShareQuality.auto: [2, 15, 625000, 1, 15, 2500000],
        RtcScreenShareQuality.q1080p60: [2, 60, 2000000, 1, 60, 8000000],
        RtcScreenShareQuality.q1080p30: [2, 30, 1250000, 1, 30, 5000000],
        RtcScreenShareQuality.q1080p15: [2, 15, 625000, 1, 15, 2500000],
        RtcScreenShareQuality.q720p15: [3, 15, 375000, 1.5, 15, 1500000],
        RtcScreenShareQuality.q360p3: [6, 3, 50000, 3, 3, 200000],
      };

      for (final entry in expected.entries) {
        final encodings = screenShareQualityEncodings(
          baseline: baseline,
          quality: entry.key,
        );
        expect(encodings, hasLength(2));
        expect(encodings[0].scaleResolutionDownBy, entry.value[0]);
        expect(encodings[0].maxFramerate, entry.value[1]);
        expect(encodings[0].maxBitrate, entry.value[2]);
        expect(encodings[1].scaleResolutionDownBy, entry.value[3]);
        expect(encodings[1].maxFramerate, entry.value[4]);
        expect(encodings[1].maxBitrate, entry.value[5]);
      }
    });

    test('preserva RID e active, e omite o SSRC (libwebrtc recusa echo)', () {
      final encodings = screenShareQualityEncodings(
        baseline: baseline,
        quality: RtcScreenShareQuality.q720p15,
      );
      expect(encodings[0].rid, 'low');
      expect(encodings[0].ssrc, isNull);
      expect(encodings[0].active, isTrue);
      expect(encodings[1].rid, 'high');
      expect(encodings[1].ssrc, isNull);
      expect(encodings[1].active, isFalse);
    });
  });

  test('o teto de captura do share é 1080p60 com FPS explícito', () {
    final options = screenShareCaptureOptionsFor('source-1');
    expect(options, isA<ScreenShareCaptureOptions>());
    expect(options.deviceId, 'source-1');
    expect(options.maxFrameRate, 60);
    expect(options.params, LiveKitRtcService.screenShareH1080FPS60);
    expect(options.params.dimensions.width, 1920);
    expect(options.params.dimensions.height, 1080);
    expect(options.params.encoding!.maxFramerate, 60);
  });

  test('o preset SDK 1080p30 continua disponível como referência', () {
    expect(VideoParametersPresets.screenShareH1080FPS30.dimensions.width, 1920);
    expect(
      VideoParametersPresets.screenShareH1080FPS30.dimensions.height,
      1080,
    );
    expect(
      VideoParametersPresets.screenShareH1080FPS30.encoding!.maxFramerate,
      30,
    );
  });
}
