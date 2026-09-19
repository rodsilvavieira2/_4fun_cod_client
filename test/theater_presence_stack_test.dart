import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/theme/app_theme.dart';
import 'package:fourfun_cod_client/core/ui/app_file_image.dart';
import 'package:fourfun_cod_client/core/ui/participant_avatar.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk_input.dart';
import 'package:fourfun_cod_client/features/voice/theater/theater_presence_stack.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';
import 'package:fourfun_cod_client/shared/models/user.dart';

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

/// Detalhe fake: hermético (sem rede/dio) para o lookup de foto de perfil.
/// Sem este override, o `watch(serverDetailProvider)` dispararia um fetch real
/// e deixaria `Timer` pendente no teardown do teste.
ServerDetail _detail = const ServerDetail(
  server: Server(id: 's1', name: 'Servidor de teste'),
  channels: [],
  members: [],
  myRole: ServerRole.owner,
);

class _FakeServerDetailController extends ServerDetailController {
  @override
  Future<ServerDetail> build(String serverId) async => _detail;
}

const _arg = (serverId: 's1', channelId: 'c1');

const _anaAvatarUrl = 'https://example.com/ana.png';

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
      _detail = const ServerDetail(
        server: Server(id: 's1', name: 'Servidor de teste'),
        channels: [],
        members: [],
        myRole: ServerRole.owner,
      );
    });

    tearDown(() async {
      await rtc.participantsController.close();
      await rtc.eventsController.close();
    });

    Future<void> pumpStack(
      WidgetTester tester, {
      List<Override> extraOverrides = const [],
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rtcServiceProvider.overrideWithValue(rtc),
            pushToTalkInputServiceProvider.overrideWithValue(_FakeInput()),
            serverDetailProvider.overrideWith(
              _FakeServerDetailController.new,
            ),
            ...extraOverrides,
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
      expect(find.byType(ParticipantAvatar), findsNWidgets(2));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('participante falando renderiza sem erro', (tester) async {
      await pumpStack(tester);
      rtc.participantsController.add([
        _participant('u1', 'Ana').copyWith(isSpeaking: true),
        _participant('u2', 'Beto'),
      ]);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ParticipantAvatar), findsNWidgets(2));
    });

    testWidgets('usa a foto de perfil quando o membro tem avatarUrl', (
      tester,
    ) async {
      _detail = ServerDetail(
        server: const Server(id: 's1', name: 'Servidor de teste'),
        channels: const [],
        members: [
          ServerMember(
            id: 'm1',
            userId: 'u1',
            role: ServerRole.member,
            joinedAt: DateTime.fromMillisecondsSinceEpoch(0),
            user: const User(
              id: 'u1',
              name: 'Ana',
              username: 'ana',
              avatarUrl: _anaAvatarUrl,
            ),
          ),
        ],
        myRole: ServerRole.owner,
      );
      // Sem rede em teste: a imagem cai no fallback (inicial), mas o widget
      // deve ter recebido a URL do membro.
      await pumpStack(tester, extraOverrides: [
        fileImageBytesProvider(
          _anaAvatarUrl,
        ).overrideWith((ref) => throw StateError('rede desabilitada')),
      ]);
      rtc.participantsController.add([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Beto'),
      ]);
      await tester.pump();
      // O detalhe (membros/avatar) é async: espera resolver antes de cobrar.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final avatars = tester
          .widgetList<ParticipantAvatar>(find.byType(ParticipantAvatar))
          .toList();
      expect(avatars, hasLength(2));
      expect(avatars.first.avatarUrl, _anaAvatarUrl);
      expect(avatars.last.avatarUrl, isNull);
    });

    testWidgets('acima de 4 mostra todos com scroll, sem "+N"', (
      tester,
    ) async {
      await pumpStack(tester);
      rtc.participantsController.add([
        _participant('u1', 'Ana'),
        _participant('u2', 'Beto'),
        _participant('u3', 'Cleo'),
        _participant('u4', 'Duda'),
        _participant('u5', 'Elias'),
      ]);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ParticipantAvatar), findsNWidgets(5));
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('sem participantes renderiza vazio', (tester) async {
      await pumpStack(tester);
      rtc.participantsController.add(const []);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(ParticipantAvatar), findsNothing);
    });
  });
}
