import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/theme/app_theme.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk_input.dart';
import 'package:fourfun_cod_client/features/voice/theater/theater_presence_stack.dart';

class _FakeRtcService implements RtcService {
  // Sync: o evento chega ao listener ainda no `add`, sem depender de pump.
  final participantsController =
      StreamController<List<RtcParticipant>>.broadcast(sync: true);
  final eventsController = StreamController<RtcEvent>.broadcast(sync: true);

  @override
  String? get localParticipantId => 'u1';

  @override
  Stream<List<RtcParticipant>> get participants =>
      participantsController.stream;

  @override
  Stream<RtcEvent> get events => eventsController.stream;

  @override
  Future<void> enableMicrophone() async {}

  @override
  Future<void> disableMicrophone() async {}

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) async {}

  @override
  Future<void> disconnect() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInput extends PushToTalkInputService {
  @override
  Future<PushToTalkConfigResult> configure(PushToTalkBinding? binding) async =>
      const PushToTalkConfigResult.ok();
}

const _arg = (serverId: 's1', channelId: 'c1');

RtcParticipant _participant(String id, String name) => RtcParticipant(
  id: id,
  name: name,
  isMicrophoneEnabled: true,
  isCameraEnabled: false,
  isScreenSharing: false,
  isSystemAudioEnabled: false,
  isSpeaking: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TheaterPresenceStack', () {
    late _FakeRtcService rtc;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      rtc = _FakeRtcService();
    });

    tearDown(() async {
      await rtc.participantsController.close();
      await rtc.eventsController.close();
    });

    Future<void> pumpStack(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rtcServiceProvider.overrideWithValue(rtc),
            pushToTalkInputServiceProvider.overrideWithValue(_FakeInput()),
          ],
          child: MaterialApp(
            theme: theme4funCod,
            home: const Scaffold(body: TheaterPresenceStack(arg: _arg)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renderiza um avatar por participante sem erro de layout', (
      tester,
    ) async {
      await pumpStack(tester);
      // Regressão 2026-09-19: margem negativa quebrava a assertion
      // `margin.isNonNegative` do Container e estourava o header.
      rtc.participantsController.add([
        _participant('u1', 'Ana'),
        _participant('u2', 'Beto'),
      ]);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(CircleAvatar), findsNWidgets(2));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('sem participantes renderiza vazio', (tester) async {
      await pumpStack(tester);
      rtc.participantsController.add(const []);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(CircleAvatar), findsNothing);
    });
  });
}
