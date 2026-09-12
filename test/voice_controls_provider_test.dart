import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk.dart';
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
  PushToTalkConfigResult result = const PushToTalkConfigResult.ok();

  @override
  Future<PushToTalkConfigResult> configure(binding) async {
    configured.add(binding);
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('PTT restaurado limpa mute manual antigo', () async {
      final binding = PushToTalkBinding.keyboard(
        physicalKeyUsage: PhysicalKeyboardKey.keyK.usbHidUsage,
        label: 'K',
      );
      SharedPreferences.setMockInitialValues({
        'voice.microphone_muted': true,
        'voice.push_to_talk.enabled': true,
        'voice.push_to_talk.binding': jsonEncode(binding.toJson()),
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
      final preferences = await SharedPreferences.getInstance();
      expect(state.isMuted, isFalse);
      expect(state.isPushToTalkEnabled, isTrue);
      expect(state.isMicrophoneEnabled, isFalse);
      expect(preferences.getBool('voice.microphone_muted'), isFalse);
      expect(rtc.calls, ['remote:true', 'mic:off']);
    });

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
      expect(
        container.read(voiceControlsProvider).isRecordingPushToTalk,
        isTrue,
      );

      await controls.recordPushToTalkMouse(4);
      expect(container.read(voiceControlsProvider).isPushToTalkEnabled, isTrue);
      expect(
        container.read(voiceControlsProvider).isMicrophoneEnabled,
        isFalse,
      );
      expect(input.configured.last, isNotNull);

      rtc.calls.clear();
      await controls.setPushToTalkReleaseDelay(0);
      await controls.setPushToTalkPressed(true);
      expect(container.read(voiceControlsProvider).isMicrophoneEnabled, isTrue);
      expect(rtc.calls, ['remote:true', 'mic:on']);

      await controls.setPushToTalkPressed(false);
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(voiceControlsProvider).isMicrophoneEnabled,
        isFalse,
      );
      expect(rtc.calls, ['remote:true', 'mic:on', 'remote:true', 'mic:off']);
    });

    test('gravar atalho pela configuração já ativa o modo PTT', () async {
      await start();
      final controls = container.read(voiceControlsProvider.notifier);

      controls.startPushToTalkRecording(enableAfterCapture: true);
      await controls.recordPushToTalkMouse(4);

      final state = container.read(voiceControlsProvider);
      expect(state.isRecordingPushToTalk, isFalse);
      expect(state.pushToTalkBinding?.mouseButton, 4);
      expect(state.isPushToTalkEnabled, isTrue);
      expect(state.isPushToTalkRegistered, isTrue);
      expect(input.configured.last, state.pushToTalkBinding);
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

    test('fallback focado do PTT funciona mesmo sem registro global', () async {
      await start();
      final controls = container.read(voiceControlsProvider.notifier);
      await controls.recordPushToTalkMouse(4);
      input.result = const PushToTalkConfigResult.failed(
        PushToTalkConfigError.registrationFailed,
      );

      expect(await controls.setPushToTalkEnabled(true), isFalse);
      expect(container.read(voiceControlsProvider).isPushToTalkEnabled, isTrue);
      expect(
        container.read(voiceControlsProvider).isPushToTalkRegistered,
        isFalse,
      );

      rtc.calls.clear();
      await controls.setPushToTalkReleaseDelay(0);
      await controls.setPushToTalkPressed(true);

      expect(container.read(voiceControlsProvider).isPushToTalkPressed, true);
      expect(container.read(voiceControlsProvider).isMicrophoneEnabled, true);
      expect(rtc.calls, ['remote:true', 'mic:on']);

      await controls.setPushToTalkPressed(false);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(voiceControlsProvider).isPushToTalkPressed, false);
      expect(container.read(voiceControlsProvider).isMicrophoneEnabled, false);
      expect(rtc.calls, ['remote:true', 'mic:on', 'remote:true', 'mic:off']);
    });

    test('Ctrl+Alt+Del rejeita com mensagem e mantém gravando', () async {
      await start();
      final controls = container.read(voiceControlsProvider.notifier);
      controls.startPushToTalkRecording();

      KeyEvent down(PhysicalKeyboardKey physical, LogicalKeyboardKey logical) =>
          KeyDownEvent(
            physicalKey: physical,
            logicalKey: logical,
            timeStamp: Duration.zero,
          );
      KeyEvent up(PhysicalKeyboardKey physical, LogicalKeyboardKey logical) =>
          KeyUpEvent(
            physicalKey: physical,
            logicalKey: logical,
            timeStamp: Duration.zero,
          );

      await controls.recordPushToTalkKey(
        down(PhysicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlLeft),
        control: true,
      );
      await controls.recordPushToTalkKey(
        down(PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft),
        control: true,
        alt: true,
      );
      await controls.recordPushToTalkKey(
        down(PhysicalKeyboardKey.delete, LogicalKeyboardKey.delete),
        control: true,
        alt: true,
      );
      await controls.recordPushToTalkKey(
        up(PhysicalKeyboardKey.delete, LogicalKeyboardKey.delete),
        control: true,
        alt: true,
      );
      await controls.recordPushToTalkKey(
        up(PhysicalKeyboardKey.altLeft, LogicalKeyboardKey.altLeft),
        control: true,
      );
      await controls.recordPushToTalkKey(
        up(PhysicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlLeft),
      );

      final state = container.read(voiceControlsProvider);
      expect(state.isRecordingPushToTalk, isTrue);
      expect(state.pushToTalkBinding, isNull);
      expect(state.errorMessage, contains('Ctrl+Alt+Del'));
    });

    test('Ctrl isolado grava atalho só-modificadores e registra', () async {
      await start();
      final controls = container.read(voiceControlsProvider.notifier);
      controls.startPushToTalkRecording();

      await controls.recordPushToTalkKey(
        KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.controlLeft,
          logicalKey: LogicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        ),
        control: true,
      );
      await controls.recordPushToTalkKey(
        KeyUpEvent(
          physicalKey: PhysicalKeyboardKey.controlLeft,
          logicalKey: LogicalKeyboardKey.controlLeft,
          timeStamp: Duration.zero,
        ),
      );

      final state = container.read(voiceControlsProvider);
      expect(state.isRecordingPushToTalk, isFalse);
      expect(state.pushToTalkBinding?.isModifierOnly, isTrue);
      expect(state.pushToTalkBinding?.displayLabel, 'Ctrl');

      expect(await controls.setPushToTalkEnabled(true), isTrue);
      expect(
        container.read(voiceControlsProvider).isPushToTalkRegistered,
        isTrue,
      );
      expect(input.configured.last, state.pushToTalkBinding);
    });

    test('falha posterior do atalho global mantém PTT fechado', () async {
      await start();
      final controls = container.read(voiceControlsProvider.notifier);
      await controls.recordPushToTalkMouse(4);
      await controls.setPushToTalkEnabled(true);
      await controls.setPushToTalkPressed(true);
      rtc.calls.clear();

      await controls.handlePushToTalkRegistrationFailure();

      final state = container.read(voiceControlsProvider);
      final preferences = await SharedPreferences.getInstance();
      expect(state.isPushToTalkEnabled, isTrue);
      expect(state.isPushToTalkRegistered, isFalse);
      expect(state.isMicrophoneEnabled, isFalse);
      expect(state.errorMessage, contains('atalho global'));
      expect(preferences.getBool('voice.push_to_talk.enabled'), isTrue);
      expect(rtc.calls, ['remote:true', 'mic:off']);
    });
  });
}
