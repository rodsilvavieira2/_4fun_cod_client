import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/features/voice/voice_audio_processing_provider.dart';

class _FakeRtcService implements RtcService {
  final List<RtcNoiseSuppressionMode> appliedNoiseSuppression = [];
  bool failNextApply = false;
  bool fallbackStudio = false;

  @override
  Future<RtcNoiseSuppressionStatus> setNoiseSuppressionMode(
    RtcNoiseSuppressionMode mode,
  ) async {
    appliedNoiseSuppression.add(mode);
    if (failNextApply) {
      failNextApply = false;
      throw StateError('processamento indisponível');
    }
    if (mode == RtcNoiseSuppressionMode.studio && fallbackStudio) {
      return const RtcNoiseSuppressionStatus(
        requestedMode: RtcNoiseSuppressionMode.studio,
        effectiveMode: RtcNoiseSuppressionMode.webrtc,
        deepFilterNetAvailable: false,
        message: 'Studio indisponível neste dispositivo. Usando Normal.',
      );
    }
    return RtcNoiseSuppressionStatus(
      requestedMode: mode,
      effectiveMode: mode,
      deepFilterNetAvailable: mode == RtcNoiseSuppressionMode.studio,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceAudioProcessingController', () {
    late _FakeRtcService rtc;

    ProviderContainer makeContainer(Map<String, Object> initialValues) {
      SharedPreferences.setMockInitialValues(initialValues);
      rtc = _FakeRtcService();
      return ProviderContainer(
        overrides: [rtcServiceProvider.overrideWithValue(rtc)],
      );
    }

    Future<void> settle() => pumpEventQueue();

    test('usa supressão de ruído ligada por padrão', () async {
      final container = makeContainer({});
      addTearDown(container.dispose);
      final subscription = container.listen(
        voiceAudioProcessingProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await settle();

      expect(
        container.read(voiceAudioProcessingProvider).isNoiseSuppressionEnabled,
        isTrue,
      );
      expect(rtc.appliedNoiseSuppression, [RtcNoiseSuppressionMode.webrtc]);
    });

    test('migra preferência booleana antiga e aplica no RTC', () async {
      final container = makeContainer({
        VoiceAudioProcessingController.noiseSuppressionKey: false,
      });
      addTearDown(container.dispose);
      final subscription = container.listen(
        voiceAudioProcessingProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await settle();

      expect(
        container.read(voiceAudioProcessingProvider).isNoiseSuppressionEnabled,
        isFalse,
      );
      expect(
        container.read(voiceAudioProcessingProvider).requestedMode,
        RtcNoiseSuppressionMode.off,
      );
      expect(rtc.appliedNoiseSuppression, [RtcNoiseSuppressionMode.off]);
    });

    test('altera, aplica e persiste a preferência', () async {
      final container = makeContainer({});
      addTearDown(container.dispose);
      final subscription = container.listen(
        voiceAudioProcessingProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await settle();

      final changed = await container
          .read(voiceAudioProcessingProvider.notifier)
          .setNoiseSuppressionMode(RtcNoiseSuppressionMode.off);

      final preferences = await SharedPreferences.getInstance();
      expect(changed, isTrue);
      expect(
        container.read(voiceAudioProcessingProvider).isNoiseSuppressionEnabled,
        isFalse,
      );
      expect(
        preferences.getString(
          VoiceAudioProcessingController.noiseSuppressionModeKey,
        ),
        RtcNoiseSuppressionMode.off.name,
      );
      expect(rtc.appliedNoiseSuppression, [
        RtcNoiseSuppressionMode.webrtc,
        RtcNoiseSuppressionMode.off,
      ]);
    });

    test('mantém modo Studio pedido quando o RTC cai para Normal', () async {
      final container = makeContainer({});
      addTearDown(container.dispose);
      final subscription = container.listen(
        voiceAudioProcessingProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await settle();

      rtc.fallbackStudio = true;
      final changed = await container
          .read(voiceAudioProcessingProvider.notifier)
          .setNoiseSuppressionMode(RtcNoiseSuppressionMode.studio);

      final state = container.read(voiceAudioProcessingProvider);
      expect(changed, isTrue);
      expect(state.requestedMode, RtcNoiseSuppressionMode.studio);
      expect(state.effectiveMode, RtcNoiseSuppressionMode.webrtc);
      expect(state.deepFilterNetAvailable, isFalse);
      expect(state.errorMessage, contains('Studio indisponível'));
    });

    test('migra preferência legada deepFilterNet para Studio', () async {
      final container = makeContainer({
        VoiceAudioProcessingController.noiseSuppressionModeKey: 'deepFilterNet',
      });
      addTearDown(container.dispose);
      final subscription = container.listen(
        voiceAudioProcessingProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      await settle();

      expect(
        container.read(voiceAudioProcessingProvider).requestedMode,
        RtcNoiseSuppressionMode.studio,
      );
      expect(rtc.appliedNoiseSuppression, [RtcNoiseSuppressionMode.studio]);
    });

    test('faz rollback quando o RTC recusa a troca', () async {
      final container = makeContainer({});
      addTearDown(container.dispose);
      final subscription = container.listen(
        voiceAudioProcessingProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await settle();

      rtc.failNextApply = true;
      final changed = await container
          .read(voiceAudioProcessingProvider.notifier)
          .setNoiseSuppressionEnabled(false);

      final state = container.read(voiceAudioProcessingProvider);
      expect(changed, isFalse);
      expect(state.isNoiseSuppressionEnabled, isTrue);
      expect(state.errorMessage, contains('supressão de ruído'));
      expect(rtc.appliedNoiseSuppression, [
        RtcNoiseSuppressionMode.webrtc,
        RtcNoiseSuppressionMode.off,
        RtcNoiseSuppressionMode.webrtc,
      ]);
    });
  });
}
