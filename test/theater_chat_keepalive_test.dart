import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/theme/app_theme.dart';
import 'package:fourfun_cod_client/core/websocket/realtime_event.dart';
import 'package:fourfun_cod_client/core/websocket/socket_service.dart';
import 'package:fourfun_cod_client/features/chat/chat_providers.dart';
import 'package:fourfun_cod_client/features/chat/chat_screen.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/features/servers/servers_repository.dart';
import 'package:fourfun_cod_client/features/voice/theater/theater_screen.dart';
import 'package:fourfun_cod_client/features/voice/theater/theater_ui_provider.dart';
import 'package:fourfun_cod_client/features/voice/voice_providers.dart';
import 'package:fourfun_cod_client/shared/models/message.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';

class _FakeRtcService implements RtcService {
  @override
  String? get localParticipantId => 'u1';

  @override
  RtcVideoTrackRef? videoTrackOf(String participantId) => null;

  @override
  RtcVideoTrackRef? screenTrackOf(String participantId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// VoiceController com estado fixo: prova o keepalive do chat sem precisar
/// dirigir o `join` (backend/LiveKit).
class _FixedVoiceController extends VoiceController {
  _FixedVoiceController(this._fixed);

  final VoiceState _fixed;

  @override
  VoiceState build(({String serverId, String channelId}) arg) => _fixed;
}

/// Socket fake: sem conexão real. O `joinChannelAndWait` herdado lança
/// `StateError` (sem socket) e o `ChatController` segue sem join — o
/// `fetchMessages` + eventos continuam exercitando o keepalive.
class _FakeSocketService extends SocketService {
  _FakeSocketService() : super(apiUrl: 'http://localhost:3000');

  final StreamController<RealtimeEvent> controller =
      StreamController<RealtimeEvent>.broadcast();
  final StreamController<void> reconnectedController =
      StreamController<void>.broadcast();

  @override
  Stream<RealtimeEvent> get events => controller.stream;

  @override
  Stream<void> get reconnected => reconnectedController.stream;
}

/// Repository fake: conta os `fetchMessages` (sinal de reconexão/refetch) e
/// devolve vazio para as demais leituras do shell do teatro.
class _FakeServersRepository implements ServersRepository {
  int fetchCalls = 0;

  @override
  Future<MessagePage> fetchMessages(
    String channelId, {
    int limit = 50,
    String? before,
  }) async {
    fetchCalls++;
    return const MessagePage(messages: []);
  }

  @override
  Future<List<ServerChannel>> fetchChannels(String serverId) async => const [];

  @override
  Future<ServerDetail> fetchServerDetail(String serverId) async => ServerDetail(
    server: const Server(id: 's1', name: 'Servidor'),
    channels: const [],
    members: const [],
  );

  @override
  Future<ServerPresence> fetchPresence(String serverId) async =>
      const ServerPresence(online: {});

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _arg = (serverId: 's1', channelId: 'c1');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TheaterScreen chat keepalive', () {
    late _FakeSocketService socket;
    late _FakeServersRepository repo;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      socket = _FakeSocketService();
      repo = _FakeServersRepository();
    });

    tearDown(() async {
      await socket.controller.close();
      await socket.reconnectedController.close();
    });

    Future<ProviderContainer> pumpTheater(
      WidgetTester tester, {
      required Size size,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      late ProviderContainer container;
      const fixed = VoiceState(
        status: VoiceSessionStatus.connected,
        participants: [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rtcServiceProvider.overrideWithValue(_FakeRtcService()),
            voiceControllerProvider.overrideWith(
              () => _FixedVoiceController(fixed),
            ),
            socketServiceProvider.overrideWithValue(socket),
            serversRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: theme4funCod,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  container = ProviderScope.containerOf(context);
                  return const TheaterScreen(
                    serverId: 's1',
                    channelId: 'c1',
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return container;
    }

    Future<void> openChat(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      container
          .read(theaterUiControllerProvider(_arg).notifier)
          .toggleChat();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> closeChat(
      WidgetTester tester,
      ProviderContainer container,
    ) async {
      container
          .read(theaterUiControllerProvider(_arg).notifier)
          .toggleChat();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('colapsar e reabrir não refaz o fetch (coluna larga)', (
      tester,
    ) async {
      final container = await pumpTheater(
        tester,
        size: const Size(1280, 800),
      );
      expect(tester.takeException(), isNull);
      // Lazy: sem abrir, nenhum fetch.
      expect(repo.fetchCalls, 0);

      await openChat(tester, container);
      expect(tester.takeException(), isNull);
      expect(repo.fetchCalls, 1);
      expect(
        container.read(chatControllerProvider(_arg)).hasValue,
        isTrue,
      );
      expect(find.byType(ChatScreen), findsOneWidget);

      await closeChat(tester, container);
      expect(tester.takeException(), isNull);
      // Conexão mantida: provider vivo, sem refetch.
      expect(
        container.read(chatControllerProvider(_arg)).hasValue,
        isTrue,
      );
      expect(repo.fetchCalls, 1);

      await openChat(tester, container);
      expect(tester.takeException(), isNull);
      expect(repo.fetchCalls, 1);
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(
        container.read(chatControllerProvider(_arg)).hasValue,
        isTrue,
      );
    });

    testWidgets('colapsar e reabrir não refaz o fetch (overlay estreito)', (
      tester,
    ) async {
      final container = await pumpTheater(
        tester,
        size: const Size(800, 600),
      );
      expect(tester.takeException(), isNull);

      await openChat(tester, container);
      expect(repo.fetchCalls, 1);
      expect(find.byType(ChatScreen), findsOneWidget);

      await closeChat(tester, container);
      expect(
        container.read(chatControllerProvider(_arg)).hasValue,
        isTrue,
      );
      expect(repo.fetchCalls, 1);

      await openChat(tester, container);
      expect(repo.fetchCalls, 1);
      expect(find.byType(ChatScreen), findsOneWidget);
    });
  });
}
