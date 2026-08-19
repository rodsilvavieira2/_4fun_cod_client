import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:_4fun_cod_client/core/api/api_exception.dart';
import 'package:_4fun_cod_client/core/rtc/rtc_providers.dart';
import 'package:_4fun_cod_client/core/rtc/rtc_service.dart';
import 'package:_4fun_cod_client/features/servers/servers_providers.dart';
import 'package:_4fun_cod_client/features/servers/servers_repository.dart';
import 'package:_4fun_cod_client/features/voice/voice_providers.dart';
import 'package:_4fun_cod_client/shared/models/voice.dart';

/// RtcService fake: registra chamadas e expõe streams injetáveis para
/// simular eventos/participantes do LiveKit sem o SDK.
class FakeRtcService implements RtcService {
  final StreamController<List<RtcParticipant>> participantsController =
      StreamController<List<RtcParticipant>>.broadcast();
  final StreamController<RtcEvent> eventsController =
      StreamController<RtcEvent>.broadcast();

  /// Identity do participante local (configurável por teste).
  @override
  String? get localParticipantId => localId;

  /// Identidade local (campo para o getter acima ser configurável).
  String? localId;

  /// Quantas chamadas de [connect] devem falhar antes de passar.
  int failConnectTimes = 0;
  Object connectError = Exception('connect falhou');

  final List<({String url, String token})> connections = [];
  int disconnectCalls = 0;
  int enableMicCalls = 0;
  int disableMicCalls = 0;
  RtcTokenGenerator? lastTokenGenerator;

  @override
  Stream<List<RtcParticipant>> get participants => participantsController.stream;

  @override
  Stream<RtcEvent> get events => eventsController.stream;

  @override
  Future<void> connect(
    String url,
    String token, {
    RtcTokenGenerator? tokenGenerator,
  }) async {
    connections.add((url: url, token: token));
    lastTokenGenerator = tokenGenerator;
    if (failConnectTimes > 0) {
      failConnectTimes--;
      throw connectError;
    }
  }

  @override
  Future<void> disconnect() async => disconnectCalls++;

  @override
  Future<void> enableMicrophone() async => enableMicCalls++;

  @override
  Future<void> disableMicrophone() async => disableMicCalls++;

  void pushParticipants(List<RtcParticipant> list) =>
      participantsController.add(list);

  void pushEvent(RtcEvent event) => eventsController.add(event);
}

/// Repository fake: apenas os métodos usados pelo voice; o restante da
/// interface cai em `noSuchMethod` (nunca chamado nos testes).
class FakeServersRepository implements ServersRepository {
  Future<VoiceJoinInfo> Function(String serverId, String channelId)? onJoinVoice;
  int joinVoiceCalls = 0;

  @override
  Future<VoiceJoinInfo> joinVoice(String serverId, String channelId) async {
    joinVoiceCalls++;
    final handler = onJoinVoice;
    if (handler == null) {
      return const VoiceJoinInfo(
        livekitUrl: 'wss://livekit.test',
        token: 'token',
        roomName: 'ch_c1',
      );
    }
    return handler(serverId, channelId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const _arg = (serverId: 's1', channelId: 'c1');
const _joinInfo = VoiceJoinInfo(
  livekitUrl: 'wss://livekit.test',
  token: 'token-1',
  roomName: 'ch_c1',
);

RtcParticipant _participant(
  String id,
  String name, {
  bool mic = true,
  bool speaking = false,
}) =>
    RtcParticipant(
      id: id,
      name: name,
      isMicrophoneEnabled: mic,
      isSpeaking: speaking,
    );

void main() {
  group('VoiceController', () {
    late ProviderContainer container;
    late FakeServersRepository repo;
    late FakeRtcService rtc;

    setUp(() {
      repo = FakeServersRepository();
      rtc = FakeRtcService();
      container = ProviderContainer(
        overrides: [
          serversRepositoryProvider.overrideWithValue(repo),
          rtcServiceProvider.overrideWithValue(rtc),
        ],
      );
    });

    tearDown(() => container.dispose());

    /// Mantém o provider vivo com um listener (autoDispose descarta sem
    /// listeners ativos) e devolve o notifier.
    VoiceController buildVoice() {
      final sub = container.listen(voiceControllerProvider(_arg), (_, _) {});
      addTearDown(sub.close);
      return container.read(voiceControllerProvider(_arg).notifier);
    }

    VoiceState state() => container.read(voiceControllerProvider(_arg));

    Future<void> settle() => pumpEventQueue();

    test('join conecta com a url/token do joinVoice e vai para connected',
        () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      final notifier = buildVoice();
      expect(state().status, VoiceSessionStatus.idle);

      await notifier.join();
      await settle();

      expect(repo.joinVoiceCalls, 1);
      expect(rtc.connections, [
        (url: 'wss://livekit.test', token: 'token-1'),
      ]);
      expect(rtc.lastTokenGenerator, isNotNull,
          reason: 'tokenGenerator registrado para reconexão futura');
      expect(state().status, VoiceSessionStatus.connected);
      expect(state().isMicrophoneEnabled, isFalse,
          reason: 'mic entra mutado por padrão (decisão Fase 4)');
    });

    test('falha de connect refaz o join e reconecta com token fresco',
        () async {
      var joinCalls = 0;
      repo.onJoinVoice = (serverId, channelId) async {
        joinCalls++;
        return VoiceJoinInfo(
          livekitUrl: 'wss://livekit.test',
          token: joinCalls == 1 ? 'token-velho' : 'token-fresco',
          roomName: 'ch_c1',
        );
      };
      rtc.failConnectTimes = 1; // 1ª tentativa falha (token expirado)
      final notifier = buildVoice();

      await notifier.join();
      await settle();

      expect(joinCalls, 2, reason: 'refaz o /join para obter token fresco');
      expect(
        rtc.connections.map((c) => c.token),
        ['token-velho', 'token-fresco'],
      );
      expect(state().status, VoiceSessionStatus.connected);
    });

    test('falha persistente do connect vira estado error', () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.failConnectTimes = 5; // falha na 1ª e na retry
      final notifier = buildVoice();

      await notifier.join();
      await settle();

      expect(rtc.connections.length, 2, reason: '1 tentativa + 1 retry');
      expect(state().status, VoiceSessionStatus.error);
      expect(state().errorMessage, isNotNull);
    });

    test('erro do join (backend) vira estado error sem chamar connect',
        () async {
      repo.onJoinVoice = (serverId, channelId) async =>
          throw const ApiException(message: 'Canal de voz indisponível');
      final notifier = buildVoice();

      await notifier.join();
      await settle();

      expect(rtc.connections, isEmpty);
      expect(state().status, VoiceSessionStatus.error);
      expect(state().errorMessage, isNotNull);
    });

    test('leave desconecta e volta para idle', () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      expect(state().status, VoiceSessionStatus.connected);

      await notifier.leave();
      await settle();

      expect(rtc.disconnectCalls, 1);
      expect(state().status, VoiceSessionStatus.idle);
      expect(state().participants, isEmpty);
    });

    test('toggleMicrophone chama enable/disable e atualiza o estado',
        () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      final notifier = buildVoice();
      await notifier.join();
      await settle();

      await notifier.toggleMicrophone();
      await settle();
      expect(rtc.enableMicCalls, 1);
      expect(state().isMicrophoneEnabled, isTrue);

      await notifier.toggleMicrophone();
      await settle();
      expect(rtc.disableMicCalls, 1);
      expect(state().isMicrophoneEnabled, isFalse);
    });

    test('toggleMicrophone fora da sessão é ignorado', () async {
      final notifier = buildVoice();

      await notifier.toggleMicrophone();
      await settle();

      expect(rtc.enableMicCalls, 0);
      expect(rtc.disableMicCalls, 0);
    });

    test('troca de canal (dispose do provider) desconecta', () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      expect(rtc.disconnectCalls, 0);

      // Selecionar outro canal descarta o provider (autoDispose family) →
      // onDispose do controller desconecta da sala.
      container.invalidate(voiceControllerProvider(_arg));
      await settle();

      expect(rtc.disconnectCalls, 1);
    });

    test('participantes do stream aparecem no estado, local primeiro',
        () async {
      rtc.localId = 'user_u1';
      buildVoice();

      rtc.pushParticipants([
        _participant('user_u2', 'Bia'),
        _participant('user_u3', 'Caio'),
        _participant('user_u1', 'Ana'),
      ]);
      await settle();

      expect(state().participants.map((p) => p.id), [
        'user_u1',
        'user_u2',
        'user_u3',
      ], reason: 'local primeiro, depois por nome');
    });

    test('estado do participante reflete mic e speaking do snapshot',
        () async {
      buildVoice();

      rtc.pushParticipants([
        _participant('user_u2', 'Bia', mic: false, speaking: true),
      ]);
      await settle();

      final bia = state().participants.single;
      expect(bia.isMicrophoneEnabled, isFalse);
      expect(bia.isSpeaking, isTrue);
    });

    test('DisconnectedEvent (queda da sala) volta para idle', () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      expect(state().status, VoiceSessionStatus.connected);

      rtc.pushEvent(const DisconnectedEvent());
      await settle();

      expect(state().status, VoiceSessionStatus.idle);
      expect(state().participants, isEmpty);
    });

    test('MicEnabledChangedEvent do local sincroniza o botão de mute',
        () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      expect(state().isMicrophoneEnabled, isFalse);

      // O RtcService real emite isso quando o unmute local é confirmado.
      rtc.pushEvent(const MicEnabledChangedEvent(
        participantId: 'user_u1',
        isMicrophoneEnabled: true,
      ));
      await settle();

      expect(state().isMicrophoneEnabled, isTrue);
    });

    test('MicEnabledChangedEvent de outro participante não toca o botão',
        () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      final notifier = buildVoice();
      await notifier.join();
      await settle();

      rtc.pushEvent(const MicEnabledChangedEvent(
        participantId: 'user_u2',
        isMicrophoneEnabled: true,
      ));
      await settle();

      expect(state().isMicrophoneEnabled, isFalse);
    });
  });
}
