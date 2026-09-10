import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/livekit_rtc_service.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/features/voice/voice_volume_controller.dart';

class _FakeRtcService implements RtcService {
  double lastInputGain = 1.0;
  double lastOutputGain = 1.0;
  final Map<String, double> participantGains = {};
  final Map<String, double> sourceGains = {};
  int inputCalls = 0;
  int outputCalls = 0;

  @override
  Future<void> setInputVolume(double gain) async {
    inputCalls++;
    lastInputGain = gain;
  }

  @override
  Future<void> setOutputVolume(double gain) async {
    outputCalls++;
    lastOutputGain = gain;
  }

  @override
  Future<void> setParticipantVolume(String identity, double gain) async {
    participantGains[identity] = gain;
  }

  @override
  Future<void> setParticipantSourceVolume(
    String identity,
    RtcAudioSource source,
    double gain,
  ) async {
    sourceGains['$identity#${source.name}'] = gain;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoiceVolumeMath', () {
    test('clamp 0..200', () {
      expect(VoiceVolumeMath.clampPercent(-5), 0);
      expect(VoiceVolumeMath.clampPercent(0), 0);
      expect(VoiceVolumeMath.clampPercent(100), 100);
      expect(VoiceVolumeMath.clampPercent(200), 200);
      expect(VoiceVolumeMath.clampPercent(999), 200);
    });

    test('clamp de entrada 0..100', () {
      expect(VoiceVolumeMath.clampInputPercent(-5), 0);
      expect(VoiceVolumeMath.clampInputPercent(0), 0);
      expect(VoiceVolumeMath.clampInputPercent(100), 100);
      expect(VoiceVolumeMath.clampInputPercent(200), 100);
      expect(VoiceVolumeMath.inputGainOf(50), 0.5);
      expect(VoiceVolumeMath.inputGainOf(200), 1.0);
    });

    test('ganho mestre, individual e combinado 200% x 200%', () {
      expect(VoiceVolumeMath.gainOf(100), 1.0);
      expect(VoiceVolumeMath.gainOf(0), 0.0);
      expect(VoiceVolumeMath.gainOf(200), 2.0);
      expect(VoiceVolumeMath.effectiveGain(100, 100), 1.0);
      expect(VoiceVolumeMath.effectiveGain(200, 200), 4.0);
      expect(VoiceVolumeMath.effectiveGain(0, 200), 0.0);
      expect(VoiceVolumeMath.effectiveGain(50, 50), 0.25);
    });

    test('percentOfGain normaliza 0.0..2.0', () {
      expect(VoiceVolumeMath.percentOfGain(1.0), 100);
      expect(VoiceVolumeMath.percentOfGain(0.0), 0);
      expect(VoiceVolumeMath.percentOfGain(2.0), 200);
      expect(VoiceVolumeMath.percentOfGain(9.9), 200);
      expect(VoiceVolumeMath.percentOfGain(-1.0), 0);
    });
  });

  group('LiveKitRtcService volume math', () {
    test('normalize + efetivo com teto 4.0', () {
      expect(LiveKitRtcService.normalizeVolumeGain(5.0), 2.0);
      expect(LiveKitRtcService.normalizeVolumeGain(-2.0), 0.0);
      expect(LiveKitRtcService.normalizeVolumeGain(double.nan), 1.0);
      expect(LiveKitRtcService.effectiveVolumeGain(2.0, 2.0), 4.0);
      expect(LiveKitRtcService.effectiveVolumeGain(0.0, 2.0), 0.0);
      expect(LiveKitRtcService.effectiveVolumeGain(1.0, 1.0), 1.0);
    });

    test('opções do microfone fixam EC/AGC/high-pass e alternam ruído', () {
      final enabled = LiveKitRtcService.microphoneCaptureOptionsForTesting(
        noiseSuppressionEnabled: true,
        deviceId: 'mic-usb',
      );
      final disabled = LiveKitRtcService.microphoneCaptureOptionsForTesting(
        noiseSuppressionEnabled: false,
        deviceId: 'mic-usb',
      );

      expect(enabled.deviceId, 'mic-usb');
      expect(enabled.echoCancellation, isTrue);
      expect(enabled.noiseSuppression, isTrue);
      expect(enabled.autoGainControl, isTrue);
      expect(enabled.highPassFilter, isTrue);
      expect(enabled.voiceIsolation, isTrue);
      expect(enabled.typingNoiseDetection, isTrue);

      expect(disabled.deviceId, 'mic-usb');
      expect(disabled.echoCancellation, isTrue);
      expect(disabled.noiseSuppression, isFalse);
      expect(disabled.autoGainControl, isTrue);
      expect(disabled.highPassFilter, isTrue);
      expect(disabled.voiceIsolation, isFalse);
      expect(disabled.typingNoiseDetection, isFalse);
    });

    test('áudio de sistema não usa processamento de voz', () {
      final options = systemAudioCaptureOptionsFor('monitor-id');

      expect(options.deviceId, 'monitor-id');
      expect(options.echoCancellation, isFalse);
      expect(options.noiseSuppression, isFalse);
      expect(options.autoGainControl, isFalse);
      expect(options.highPassFilter, isFalse);
      expect(options.voiceIsolation, isFalse);
      expect(options.typingNoiseDetection, isFalse);
    });
  });

  group('VoiceVolumeController', () {
    late _FakeRtcService rtc;

    ProviderContainer makeContainer() {
      rtc = _FakeRtcService();
      SharedPreferences.setMockInitialValues({});
      return ProviderContainer(
        overrides: [rtcServiceProvider.overrideWithValue(rtc)],
      );
    }

    test('defaults 100 e reset', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(voiceVolumeProvider).inputPercent, 100);
      expect(container.read(voiceVolumeProvider).outputPercent, 100);
      expect(container.read(voiceVolumeProvider).percentOf('user_x'), 100);

      container.read(voiceVolumeProvider.notifier).setInputPercent(1000);
      expect(container.read(voiceVolumeProvider).inputPercent, 100);
      container.read(voiceVolumeProvider.notifier).setInputPercent(-10);
      expect(container.read(voiceVolumeProvider).inputPercent, 0);
      container.read(voiceVolumeProvider.notifier).resetInput();
      expect(container.read(voiceVolumeProvider).inputPercent, 100);

      container.read(voiceVolumeProvider.notifier).setOutputPercent(1000);
      expect(container.read(voiceVolumeProvider).outputPercent, 200);
      container.read(voiceVolumeProvider.notifier).resetOutput();
      expect(container.read(voiceVolumeProvider).outputPercent, 100);
    });

    test('volume individual remove entrada ao voltar a 100', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final controller = container.read(voiceVolumeProvider.notifier);

      controller.setParticipantPercent('user_a', 50);
      expect(container.read(voiceVolumeProvider).participantPercent, {
        'user_a': 50,
      });
      controller.setParticipantPercent('user_a', 100);
      expect(container.read(voiceVolumeProvider).participantPercent, isEmpty);
      expect(rtc.sourceGains['user_a#microphone'], 1.0);
      controller.setParticipantPercent('', 50);
      expect(container.read(voiceVolumeProvider).participantPercent, isEmpty);
    });

    test('clamp individual 0..200', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final controller = container.read(voiceVolumeProvider.notifier);

      controller.setParticipantPercent('user_b', -10);
      expect(container.read(voiceVolumeProvider).percentOf('user_b'), 0);
      controller.setParticipantPercent('user_b', 500);
      expect(container.read(voiceVolumeProvider).percentOf('user_b'), 200);
    });

    test('encaminha ganhos ao RtcService', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final controller = container.read(voiceVolumeProvider.notifier);

      controller.setOutputPercent(200);
      controller.setInputPercent(40);
      controller.setParticipantPercent('user_c', 50);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rtc.lastOutputGain, 2.0);
      expect(rtc.lastInputGain, 0.4);
      expect(rtc.sourceGains['user_c#microphone'], 0.5);
    });

    test(
      'mute individual é separado do slider e restaura o percentual',
      () async {
        final container = makeContainer();
        addTearDown(container.dispose);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final controller = container.read(voiceVolumeProvider.notifier);

        controller.setParticipantPercent('user_d', 150);
        controller.setParticipantMuted('user_d', true);
        expect(container.read(voiceVolumeProvider).percentOf('user_d'), 150);
        expect(
          container.read(voiceVolumeProvider).isParticipantMuted('user_d'),
          isTrue,
        );
        expect(rtc.sourceGains['user_d#microphone'], 0.0);

        controller.setParticipantMuted('user_d', false);
        expect(
          container.read(voiceVolumeProvider).isParticipantMuted('user_d'),
          isFalse,
        );
        expect(rtc.sourceGains['user_d#microphone'], 1.5);
      },
    );

    test('restaura input, participante e mute persistidos', () async {
      SharedPreferences.setMockInitialValues({
        VoiceVolumeController.inputKey: 45,
        VoiceVolumeController.outputKey: 150,
        VoiceVolumeController.participantsKey: '{"user_e":125}',
        VoiceVolumeController.mutedParticipantsKey: '["user_f"]',
      });
      rtc = _FakeRtcService();
      final container = ProviderContainer(
        overrides: [rtcServiceProvider.overrideWithValue(rtc)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(voiceVolumeProvider, (_, _) {});
      addTearDown(subscription.close);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(voiceVolumeProvider);
      expect(state.inputPercent, 45);
      expect(state.outputPercent, 150);
      expect(state.percentOf('user_e'), 125);
      expect(state.isParticipantMuted('user_f'), isTrue);
      expect(rtc.lastInputGain, 0.45);
      expect(rtc.lastOutputGain, 1.5);
      expect(rtc.sourceGains['user_e#microphone'], 1.25);
      expect(rtc.sourceGains['user_f#microphone'], 0.0);
    });

    test('volume da transmissão não afeta a voz (e vice-versa)', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final controller = container.read(voiceVolumeProvider.notifier);

      controller.setParticipantPercent('user_g', 50);
      controller.setParticipantPercent(
        'user_g',
        150,
        source: RtcAudioSource.screenShareAudio,
      );
      final state = container.read(voiceVolumeProvider);
      expect(state.percentOf('user_g'), 50);
      expect(
        state.percentOf('user_g', source: RtcAudioSource.screenShareAudio),
        150,
      );
      expect(state.participantPercent['user_g'], 50);
      expect(state.participantPercent['user_g#screen'], 150);
      expect(rtc.sourceGains['user_g#microphone'], 0.5);
      expect(rtc.sourceGains['user_g#screenShareAudio'], 1.5);

      controller.setParticipantMuted(
        'user_g',
        true,
        source: RtcAudioSource.screenShareAudio,
      );
      expect(
        container
            .read(voiceVolumeProvider)
            .isParticipantMuted(
              'user_g',
              source: RtcAudioSource.screenShareAudio,
            ),
        isTrue,
      );
      expect(
        container.read(voiceVolumeProvider).isParticipantMuted('user_g'),
        isFalse,
      );
      expect(rtc.sourceGains['user_g#screenShareAudio'], 0.0);
      expect(rtc.sourceGains['user_g#microphone'], 0.5);
    });

    test('coalescing: rajada de slider aplica o último valor', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final controller = container.read(voiceVolumeProvider.notifier);

      for (var i = 0; i <= 20; i++) {
        controller.setOutputPercent(i * 10);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(voiceVolumeProvider).outputPercent, 200);
      expect(rtc.lastOutputGain, 2.0);
    });
  });
}
