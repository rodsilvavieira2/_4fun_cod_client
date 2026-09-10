import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/auth/auth_controller.dart';
import 'package:fourfun_cod_client/core/auth/auth_state.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/websocket/realtime_event.dart';
import 'package:fourfun_cod_client/core/websocket/socket_service.dart';
import 'package:fourfun_cod_client/features/channels/channel_list.dart';
import 'package:fourfun_cod_client/features/servers/server_shell_screen.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/features/servers/servers_repository.dart';
import 'package:fourfun_cod_client/features/voice/voice_providers.dart';
import 'package:fourfun_cod_client/shared/models/message.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';
import 'package:fourfun_cod_client/shared/models/user.dart';
import 'package:fourfun_cod_client/shared/models/voice.dart';

class _FakeAuth extends AuthController {
  @override
  Future<AuthState> build() async => const Authenticated(
    user: User(id: 'u1', name: 'Ana', username: 'ana'),
  );
}

/// Socket fake que registra rooms (o join real com ack falha sem conexão —
/// o ChatController trata isso e segue com o snapshot REST).
class _Socket extends SocketService {
  _Socket() : super(apiUrl: 'http://localhost:3000');

  final joined = <String>[];
  final left = <String>[];
  final StreamController<RealtimeEvent> eventsController =
      StreamController<RealtimeEvent>.broadcast();
  final StreamController<void> reconnectedController =
      StreamController<void>.broadcast();

  @override
  Stream<RealtimeEvent> get events => eventsController.stream;

  @override
  Stream<void> get reconnected => reconnectedController.stream;

  @override
  void joinChannel(String channelId) {
    joined.add(channelId);
    super.joinChannel(channelId);
  }

  @override
  void leaveChannel(String channelId) {
    left.add(channelId);
    super.leaveChannel(channelId);
  }

  @override
  void dispose() {
    eventsController.close();
    reconnectedController.close();
    super.dispose();
  }
}

class _Repo implements ServersRepository {
  int fetchCalls = 0;
  int joinVoiceCalls = 0;

  @override
  Future<List<Server>> fetchServers() async => const [
    Server(id: 's1', name: 'Servidor'),
  ];

  @override
  Future<List<ServerChannel>> fetchChannels(String serverId) async => const [
    ServerChannel(id: 't1', name: 'geral', type: ChannelType.text),
    ServerChannel(id: 'v1', name: 'Voz', type: ChannelType.voice),
  ];

  @override
  Future<MessagePage> fetchMessages(
    String channelId, {
    int limit = 50,
    String? before,
  }) async {
    fetchCalls++;
    return MessagePage(
      messages: [
        ChatMessage(
          id: 'm1',
          channelId: channelId,
          content: 'olá do texto',
          kind: ChatMessageKind.text,
          author: const User(id: 'u1', name: 'Ana', username: 'ana'),
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      ],
    );
  }

  @override
  Future<VoiceJoinInfo> joinVoice(String serverId, String channelId) async {
    joinVoiceCalls++;
    return const VoiceJoinInfo(
      livekitUrl: 'ws://localhost:7880',
      token: 'token',
      roomName: 'room',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Detail extends ServerDetailController {
  @override
  Future<ServerDetail> build(String serverId) async => ServerDetail(
    server: const Server(id: 's1', name: 'Servidor'),
    channels: const [],
    members: const [],
    myRole: ServerRole.member,
  );
}

class _Rtc implements RtcService {
  @override
  Stream<void> get mediaDevicesChanged => const Stream.empty();

  @override
  Stream<List<RtcParticipant>> get participants => const Stream.empty();

  @override
  Stream<RtcEvent> get events => const Stream.empty();

  @override
  Future<List<RtcAudioDevice>> listAudioInputDevices() async => const [];

  @override
  Future<List<RtcAudioDevice>> listAudioOutputDevices() async => const [];

  @override
  Future<List<RtcVideoDevice>> listCameraDevices() async => const [];

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> connect(
    String url,
    String token, {
    RtcTokenGenerator? tokenGenerator,
  }) async {}

  @override
  Future<void> enableMicrophone() async {}

  @override
  Future<void> disableMicrophone() async {}

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets(
    'voz↔texto no mesmo servidor não derruba o chat (sem refetch, sem leave)',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final socket = _Socket();
      final repo = _Repo();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_FakeAuth.new),
          socketServiceProvider.overrideWithValue(socket),
          serversRepositoryProvider.overrideWithValue(repo),
          serverDetailProvider.overrideWith(_Detail.new),
          rtcServiceProvider.overrideWithValue(_Rtc()),
        ],
      );
      addTearDown(() async {
        // Desmonta o shell ANTES de descartar o container: o `dispose` do
        // shell usa `ref` (rooms + leave da voz) e o framework só desmonta
        // a árvore no postTest — descartar antes derruba o `ref`.
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ServerShellScreen(serverId: 's1')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Auto-seleção abre o texto: snapshot único.
      expect(find.text('olá do texto'), findsOneWidget);
      expect(repo.fetchCalls, 1);
      expect(socket.joined, contains('t1'));

      // Linhas da LISTA (o nome do canal também aparece no header/painel).
      Finder channelRow(String name) => find.descendant(
        of: find.byType(ChannelList),
        matching: find.text(name),
      );

      // Vai para a voz: join conecta (fake) — 1 token.
      await tester.tap(channelRow('Voz'));
      await tester.pumpAndSettle();

      final voiceArg = (serverId: 's1', channelId: 'v1');
      expect(
        container.read(voiceControllerProvider(voiceArg)).status,
        VoiceSessionStatus.connected,
      );
      expect(repo.joinVoiceCalls, 1);

      // A room de texto NÃO saiu enquanto a voz estava em vista.
      expect(socket.left, isNot(contains('t1')));

      // Volta para o texto: instantâneo, sem refetch (sem spinner) e sem
      // derrubar a voz.
      await tester.tap(channelRow('geral'));
      await tester.pumpAndSettle();

      expect(find.text('olá do texto'), findsOneWidget);
      expect(repo.fetchCalls, 1);
      expect(socket.left, isNot(contains('t1')));
      expect(
        container.read(voiceControllerProvider(voiceArg)).status,
        VoiceSessionStatus.connected,
      );

      // Volta para a MESMA voz: só seleciona, sem token novo nem rejoin.
      await tester.tap(channelRow('Voz'));
      await tester.pumpAndSettle();

      expect(repo.joinVoiceCalls, 1);
      expect(
        container.read(voiceControllerProvider(voiceArg)).status,
        VoiceSessionStatus.connected,
      );
    },
  );
}
