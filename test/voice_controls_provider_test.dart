import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk_input.dart';
import 'package:fourfun_cod_client/features/voice/voice_controls_provider.dart';

class _FakeRtcService implements RtcService {
  final List<String> calls = [];
  int failRemoteAudioTimes = 0;

  @override
  Future<void> enableMicrophone() async => calls.add('mic:on');

  @override
  Future<void> disableMicrophone() async => calls.add('mic:off');

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) async {
    calls.add('remote:$enabled');
    if (failRemoteAudioTimes > 0) {
      failRemoteAudioTimes--;
      throw StateError('saída indisponível');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePushToTalkInputService extends PushToTalkInputService {
  final List<Object?> configured = [];
  bool result = true;

  @override
  Future<bool> configure(binding) async {
    configured.add(binding);
    return result;
  }
}

void main() {
  group('VoiceControlsController', () {
    late _FakeRtcService rtc;
    late _FakePushToTalkInputService input;
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      rtc = _FakeRtcService();
      input = _FakePushToTalkInputService();
      container = ProviderContainer(
        overrides: [
          rtcServiceProvider.overrideWithValue(rtc),
          pushToTalkInputServiceProvider.overrideWithValue(input),
        ],
      );
    });

    tearDown(() => container.dispose());

    Future<void> start({bool clearCalls = true}) async {
      final subscription = container.listen(voiceControlsProvider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(voiceControlsProvider.notifier).ensureInitialized();
      if (clearCalls) rtc.calls.clear();
    }

    test('alterna mute fora da sala e persiste a preferência', () async {
      await start();

      expect(
        await container.read(voiceControlsProvider.notifier).toggleMicrophone(),
        isTrue,
      );

      final state = container.read(voiceControlsProvider);
      final preferences = await SharedPreferences.getInstance();
      expect(state.isMuted, isTrue);
      expect(state.isMicrophoneEnabled, isFalse);
      expect(rtc.calls, ['remote:true', 'mic:off']);
      expect(preferences.getBool('voice.microphone_muted'), isTrue);
    });

    test('ensurdecer preserva o mute explícito ao ser desfeito', () async {
      await start();

      await container.read(voiceControlsProvider.notifier).toggleDeafen();
      expect(container.read(voiceControlsProvider).isDeafened, isTrue);
      expect(container.read(voiceControlsProvider).isMuted, isFalse);
      expect(
        container.read(voiceControlsProvider).isMicrophoneEnabled,
        isFalse,
      );
      expect(rtc.calls, ['mic:off', 'remote:false']);

      rtc.calls.clear();
      await container.read(voiceControlsProvider.notifier).toggleDeafen();
      expect(container.read(voiceControlsProvider).isDeafened, isFalse);
      expect(container.read(voiceControlsProvider).isMicrophoneEnabled, isTrue);
      expect(rtc.calls, ['remote:true', 'mic:on']);
    });

    test(
      'restaura mute e ensurdecer persistidos na criação seguinte',
      () async {
        SharedPreferences.setMockInitialValues({
          'voice.microphone_muted': true,
          'voice.deafened': true,
        });
        container.dispose();
        rtc = _FakeRtcService();
        container = ProviderContainer(
          overrides: [
            rtcServiceProvider.overrideWithValue(rtc),
            pushToTalkInputServiceProvider.overrideWithValue(input),
          ],
        );

        await start(clearCalls: false);

        final state = container.read(voiceControlsProvider);
        expect(state.isMuted, isTrue);
        expect(state.isDeafened, isTrue);
        expect(state.isMicrophoneEnabled, isFalse);
        expect(rtc.calls, ['mic:off', 'remote:false']);
      },
    );

    test('falha ao ensurdecer restaura a preferência anterior', () async {
      await start();
      rtc.failRemoteAudioTimes = 1;

      expect(
        await container.read(voiceControlsProvider.notifier).toggleDeafen(),
        isFalse,
      );

      final state = container.read(voiceControlsProvider);
      expect(state.isMuted, isFalse);
      expect(state.isDeafened, isFalse);
      expect(state.errorMessage, contains('ensurdecer'));
      expect(rtc.calls, ['mic:off', 'remote:false', 'remote:true', 'mic:on']);
    });

    test('PTT só transmite enquanto o binding está pressionado', () async {
      await start();
      final controls = container.read(voiceControlsProvider.notifier);

      expect(await controls.setPushToTalkEnabled(true), isFalse);
      expect(container.read(voiceControlsProvider).isRecordingPushToTalk, isTrue);

      await controls.recordPushToTalkMouse(4);
      expect(container.read(voiceControlsProvider).isPushToTalkEnabled, isTrue);
      expect(container.read(voiceControlsProvider).isMicrophoneEnabled, isFalse);
      expect(input.configured.last, isNotNull);

      rtc.calls.clear();
      await controls.setPushToTalkReleaseDelay(0);
      await controls.setPushToTalkPressed(true);
      expect(container.read(voiceControlsProvider).isMicrophoneEnabled, isTrue);
      expect(rtc.calls, ['remote:true', 'mic:on']);

      await controls.setPushToTalkPressed(false);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(voiceControlsProvider).isMicrophoneEnabled, isFalse);
      expect(rtc.calls, ['remote:true', 'mic:on', 'remote:true', 'mic:off']);
    });

    test('mute manual vence PTT pressionado', () async {
      await start();
      final controls = container.read(voiceControlsProvider.notifier);
      await controls.recordPushToTalkMouse(4);
      await controls.setPushToTalkEnabled(true);
      await controls.setPushToTalkPressed(true);

      await controls.toggleMicrophone();

      final state = container.read(voiceControlsProvider);
      expect(state.isPushToTalkPressed, isTrue);
      expect(state.isMuted, isTrue);
      expect(state.isMicrophoneEnabled, isFalse);
    });
  });
}
