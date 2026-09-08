import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/livekit_rtc_service.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/features/voice/voice_volume_controller.dart';

class _FakeRtcService implements RtcService {
  double lastOutputGain = 1.0;
  final Map<String, double> participantGains = {};
  int outputCalls = 0;

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
      expect(container.read(voiceVolumeProvider).outputPercent, 100);
      expect(container.read(voiceVolumeProvider).percentOf('user_x'), 100);

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
      controller.setParticipantPercent('user_c', 50);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(rtc.lastOutputGain, 2.0);
      expect(rtc.participantGains['user_c'], 0.5);
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
