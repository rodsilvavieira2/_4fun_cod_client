import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/features/voice/voice_audio_processing_provider.dart';

class _FakeRtcService implements RtcService {
  final List<bool> appliedNoiseSuppression = [];
  bool failNextApply = false;

  @override
  Future<void> setNoiseSuppressionEnabled(bool enabled) async {
    appliedNoiseSuppression.add(enabled);
    if (failNextApply) {
      failNextApply = false;
      throw StateError('processamento indisponível');
    }
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
      expect(rtc.appliedNoiseSuppression, [true]);
    });

    test('restaura preferência salva e aplica no RTC', () async {
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
      expect(rtc.appliedNoiseSuppression, [false]);
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
          .setNoiseSuppressionEnabled(false);

      final preferences = await SharedPreferences.getInstance();
      expect(changed, isTrue);
      expect(
        container.read(voiceAudioProcessingProvider).isNoiseSuppressionEnabled,
        isFalse,
      );
      expect(
        preferences.getBool(VoiceAudioProcessingController.noiseSuppressionKey),
        isFalse,
      );
      expect(rtc.appliedNoiseSuppression, [true, false]);
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
      expect(rtc.appliedNoiseSuppression, [true, false, true]);
    });
  });
}
