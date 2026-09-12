import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk_input.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk_listener.dart';
import 'package:fourfun_cod_client/features/voice/voice_controls_provider.dart';

class _FakeRtcService implements RtcService {
  final List<String> calls = [];

  @override
  Future<void> enableMicrophone() async => calls.add('mic:on');

  @override
  Future<void> disableMicrophone() async => calls.add('mic:off');

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) async {
    calls.add('remote:$enabled');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePushToTalkInputService extends PushToTalkInputService {
  final _events = StreamController<PushToTalkInputEvent>.broadcast();
  final List<PushToTalkBinding?> configured = [];

  @override
  Stream<PushToTalkInputEvent> get events => _events.stream;

  @override
  Future<PushToTalkConfigResult> configure(PushToTalkBinding? binding) async {
    configured.add(binding);
    return const PushToTalkConfigResult.ok();
  }

  Future<void> dispose() => _events.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushToTalkListener', () {
    late _FakeRtcService rtc;
    late _FakePushToTalkInputService input;
    ProviderContainer? container;

    Future<void> pumpListener(
      WidgetTester tester,
      PushToTalkBinding binding,
    ) async {
      SharedPreferences.setMockInitialValues({
        'voice.push_to_talk.enabled': true,
        'voice.push_to_talk.binding': jsonEncode(binding.toJson()),
        'voice.push_to_talk.release_delay_ms': 0,
      });
      container = ProviderContainer(
        overrides: [
          rtcServiceProvider.overrideWithValue(rtc),
          pushToTalkInputServiceProvider.overrideWithValue(input),
        ],
      );
      await container!.read(voiceControlsProvider.notifier).ensureInitialized();
      rtc.calls.clear();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container!,
          child: const MaterialApp(
            home: Scaffold(body: PushToTalkListener(child: SizedBox.expand())),
          ),
        ),
      );
      await tester.pump();
    }

    setUp(() {
      rtc = _FakeRtcService();
      input = _FakePushToTalkInputService();
    });

    tearDown(() async {
      container?.dispose();
      await input.dispose();
    });

    testWidgets(
      'fallback focado aciona o microfone mesmo com atalho global registrado',
      (tester) async {
        final binding = PushToTalkBinding.keyboard(
          physicalKeyUsage: PhysicalKeyboardKey.keyK.usbHidUsage,
          label: 'K',
        );
        await pumpListener(tester, binding);

        expect(
          container!.read(voiceControlsProvider).isPushToTalkRegistered,
          isTrue,
        );

        await tester.sendKeyDownEvent(
          LogicalKeyboardKey.keyK,
          physicalKey: PhysicalKeyboardKey.keyK,
        );
        await tester.pump();

        expect(
          container!.read(voiceControlsProvider).isPushToTalkPressed,
          true,
        );
        expect(
          container!.read(voiceControlsProvider).isMicrophoneEnabled,
          true,
        );
        expect(rtc.calls, ['remote:true', 'mic:on']);

        await tester.sendKeyUpEvent(
          LogicalKeyboardKey.keyK,
          physicalKey: PhysicalKeyboardKey.keyK,
        );
        await tester.pump();

        expect(
          container!.read(voiceControlsProvider).isPushToTalkPressed,
          false,
        );
        expect(
          container!.read(voiceControlsProvider).isMicrophoneEnabled,
          false,
        );
        expect(rtc.calls, ['remote:true', 'mic:on', 'remote:true', 'mic:off']);
      },
    );
  });
}
