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

  // Contadores/listas do contrato de câmera (Fase 5) — mesmo padrão do mic.
  int enableCameraCalls = 0;
  int disableCameraCalls = 0;
  final List<String> switchCameraCalls = [];
  final List<({String participantId, RtcVideoQuality quality})>
      setQualityCalls = [];
  int listCameraDevicesCalls = 0;
  List<RtcVideoDevice> cameraDevices = const [];
  RtcVideoTrackRef? cameraTrackRef;

  // Contadores do contrato de screen share (Fase 6) — mesmo padrão do mic.
  int startScreenShareCalls = 0;
  int stopScreenShareCalls = 0;
  final List<String> startScreenShareSources = [];
  RtcVideoTrackRef? screenTrackRef;

  // Flag de falha de share (Prompt 2) — mesmo padrão do failEnableCameraTimes:
  // uma falha consumida não conta como chamada efetiva.
  int failStartScreenShareTimes = 0;
  Object startScreenShareError = Exception('share indisponível');

  /// Falha de [stopScreenShare] (Prompt 2) — mesmo padrão do failSwitchCamera:
  /// flag simples; com true a chamada lança e não conta como efetiva.
  bool failStopScreenShare = false;

  // Flags de falha de câmera (Prompt 2) — mesmo padrão do failConnectTimes:
  // uma falha consumida não conta como chamada efetiva.
  int failEnableCameraTimes = 0;
  Object enableCameraError = Exception('câmera indisponível');
  bool failListCameraDevices = false;
  bool failSwitchCamera = false;

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

  @override
  Future<void> enableCamera() async {
    if (failEnableCameraTimes > 0) {
      failEnableCameraTimes--;
      throw enableCameraError;
    }
    enableCameraCalls++;
  }

  @override
  Future<void> disableCamera() async => disableCameraCalls++;

  @override
  Future<void> setQuality(
    String participantId,
    RtcVideoQuality quality,
  ) async {
    setQualityCalls.add((participantId: participantId, quality: quality));
  }

  @override
  Future<List<RtcVideoDevice>> listCameraDevices() async {
    listCameraDevicesCalls++;
    if (failListCameraDevices) throw Exception('enumeração falhou');
    return cameraDevices;
  }

  @override
  Future<void> switchCamera(String deviceId) async {
    if (failSwitchCamera) throw Exception('troca de câmera falhou');
    switchCameraCalls.add(deviceId);
  }

  @override
  RtcVideoTrackRef? videoTrackOf(String participantId) => cameraTrackRef;

  @override
  Future<void> startScreenShare(String sourceId) async {
    if (failStartScreenShareTimes > 0) {
      failStartScreenShareTimes--;
      throw startScreenShareError;
    }
    startScreenShareCalls++;
    startScreenShareSources.add(sourceId);
  }

  @override
  Future<void> stopScreenShare() async {
    if (failStopScreenShare) throw Exception('encerrar share falhou');
    stopScreenShareCalls++;
  }

  @override
  RtcVideoTrackRef? screenTrackOf(String participantId) => screenTrackRef;

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
  bool camera = false,
  bool screenShare = false,
  bool speaking = false,
}) =>
    RtcParticipant(
      id: id,
      name: name,
      isMicrophoneEnabled: mic,
      isCameraEnabled: camera,
      isScreenSharing: screenShare,
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

    // ── Fase 5 (Prompt 2): câmera, spotlight, devices e qualidade ──────────

    test('toggleCamera conectado chama enable/disable e flipa o estado',
        () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      expect(state().isCameraEnabled, isFalse,
          reason: 'câmera começa OFF e nunca é publicada no connect');

      await notifier.toggleCamera();
      await settle();
      expect(rtc.enableCameraCalls, 1);
      expect(state().isCameraEnabled, isTrue);

      await notifier.toggleCamera();
      await settle();
      expect(rtc.disableCameraCalls, 1);
      expect(state().isCameraEnabled, isFalse);
    });

    test('toggleCamera fora da sessão é ignorado', () async {
      final notifier = buildVoice();

      await notifier.toggleCamera();
      await settle();

      expect(rtc.enableCameraCalls, 0);
      expect(rtc.disableCameraCalls, 0);
      expect(state().isCameraEnabled, isFalse);
    });

    test('falha de enableCamera (permissão) não derruba a sessão', () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      final notifier = buildVoice();
      await notifier.join();
      await settle();

      rtc.failEnableCameraTimes = 1;
      await notifier.toggleCamera();
      await settle();

      expect(state().status, VoiceSessionStatus.connected);
      expect(state().isCameraEnabled, isFalse,
          reason: 'sem otimismo: volta ao estado anterior');
      expect(state().errorMessage, 'Não foi possível alternar a câmera.');
      expect(rtc.disconnectCalls, 0,
          reason: 'erro de câmera nunca desconecta a sala');
    });

    test('CameraEnabledChangedEvent do local reconcilia; de remoto não toca',
        () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      expect(state().isCameraEnabled, isFalse);

      rtc.pushEvent(const CameraEnabledChangedEvent(
        participantId: 'user_u1',
        isCameraEnabled: true,
      ));
      await settle();
      expect(state().isCameraEnabled, isTrue);

      rtc.pushEvent(const CameraEnabledChangedEvent(
        participantId: 'user_u2',
        isCameraEnabled: false,
      ));
      await settle();
      expect(state().isCameraEnabled, isTrue,
          reason: 'evento de remoto não toca o botão local');
    });

    test('refreshCameraDevices preenche a lista; falha mantém a atual',
        () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      final notifier = buildVoice();
      await notifier.join();
      await settle();

      rtc.cameraDevices = const [
        RtcVideoDevice(id: 'dev-1', label: 'Webcam integrada'),
        RtcVideoDevice(id: 'dev-2', label: ''),
      ];
      await notifier.refreshCameraDevices();
      await settle();
      expect(rtc.listCameraDevicesCalls, 1);
      expect(state().cameraDevices.length, 2);

      rtc.failListCameraDevices = true;
      await notifier.refreshCameraDevices();
      await settle();
      expect(rtc.listCameraDevicesCalls, 2);
      expect(state().cameraDevices.length, 2,
          reason: 'falha de enumeração mantém a lista anterior');

      // Seleção que saiu da lista nova é limpa no próximo refresh.
      await notifier.selectCamera('dev-1');
      await settle();
      expect(state().selectedCameraId, 'dev-1');
      rtc.failListCameraDevices = false;
      rtc.cameraDevices = const [RtcVideoDevice(id: 'dev-3', label: 'Outra')];
      await notifier.refreshCameraDevices();
      await settle();
      expect(state().selectedCameraId, isNull,
          reason: 'deviceId que saiu da lista é limpo');
    });

    test('selectCamera troca ao vivo só com a câmera ligada', () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      final notifier = buildVoice();
      await notifier.join();
      await settle();

      // Câmera desligada: apenas registra a seleção (o serviço não persiste
      // deviceId pendente — o próximo enableCamera usa o device default).
      await notifier.selectCamera('dev-1');
      await settle();
      expect(state().selectedCameraId, 'dev-1');
      expect(rtc.switchCameraCalls, isEmpty);

      // Câmera ligada: aplica ao vivo via switchCamera.
      await notifier.toggleCamera();
      await settle();
      await notifier.selectCamera('dev-2');
      await settle();
      expect(state().selectedCameraId, 'dev-2');
      expect(rtc.switchCameraCalls, ['dev-2']);

      // Falha de troca: mensagem de erro, sessão intacta.
      rtc.failSwitchCamera = true;
      await notifier.selectCamera('dev-3');
      await settle();
      expect(state().status, VoiceSessionStatus.connected);
      expect(state().errorMessage, 'Não foi possível trocar a câmera.');
      expect(rtc.disconnectCalls, 0);

      // Sucesso APÓS falha: limpa a mensagem — senão o SnackBar de uma
      // falha antiga nunca reaparece (o listener só dispara em mudança).
      rtc.failSwitchCamera = false;
      await notifier.selectCamera('dev-4');
      await settle();
      expect(state().errorMessage, isNull);
      expect(state().selectedCameraId, 'dev-4');
      expect(rtc.switchCameraCalls, ['dev-2', 'dev-4']);
    });

    test('applyTileQuality: remoto com setQuality, local ignorado, dedupe',
        () async {
      rtc.localId = 'user_u1';
      final notifier = buildVoice();

      await notifier.applyTileQuality('user_u2', RtcVideoQuality.medium);
      await settle();
      await notifier.applyTileQuality('user_u2', RtcVideoQuality.medium);
      await settle();
      expect(rtc.setQualityCalls, [
        (participantId: 'user_u2', quality: RtcVideoQuality.medium),
      ], reason: 'mesma qualidade 2x → 1 chamada (dedupe)');

      await notifier.applyTileQuality('user_u2', RtcVideoQuality.high);
      await settle();
      expect(rtc.setQualityCalls.length, 2);

      await notifier.applyTileQuality('user_u1', RtcVideoQuality.high);
      await settle();
      expect(rtc.setQualityCalls.length, 2,
          reason: 'qualidade local é da publicação — nunca setQuality');
    });

    test('toggleSpotlight seta, repete limpa; snapshot órfão limpa sozinho',
        () async {
      final notifier = buildVoice();

      notifier.toggleSpotlight('user_u2');
      expect(state().spotlightParticipantId, 'user_u2');

      notifier.toggleSpotlight('user_u2');
      expect(state().spotlightParticipantId, isNull,
          reason: 'toque repetido no destaque volta ao grid');

      notifier.toggleSpotlight('user_u2');
      expect(state().spotlightParticipantId, 'user_u2');

      // Câmera desligou → destaque de tile sem vídeo não faz sentido.
      rtc.pushParticipants([_participant('user_u2', 'Bia', camera: false)]);
      await settle();
      expect(state().spotlightParticipantId, isNull);

      // Saiu da sala → limpo também.
      notifier.toggleSpotlight('user_u2');
      expect(state().spotlightParticipantId, 'user_u2');
      rtc.pushParticipants([_participant('user_u3', 'Caio', camera: true)]);
      await settle();
      expect(state().spotlightParticipantId, isNull);
    });

    test('leave e DisconnectedEvent resetam câmera e spotlight', () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      final notifier = buildVoice();
      await notifier.join();
      await settle();

      await notifier.toggleCamera();
      await settle();
      notifier.toggleSpotlight('user_u2');
      expect(state().isCameraEnabled, isTrue);
      expect(state().spotlightParticipantId, 'user_u2');

      await notifier.leave();
      await settle();
      expect(state().status, VoiceSessionStatus.idle);
      expect(state().isCameraEnabled, isFalse);
      expect(state().spotlightParticipantId, isNull);

      // Reconecta e a sala cai sozinha: DisconnectedEvent reseta igual.
      await notifier.join();
      await settle();
      await notifier.toggleCamera();
      await settle();
      notifier.toggleSpotlight('user_u2');
      rtc.pushEvent(const DisconnectedEvent());
      await settle();
      expect(state().status, VoiceSessionStatus.idle);
      expect(state().isCameraEnabled, isFalse);
      expect(state().spotlightParticipantId, isNull);
    });

    // ── Fase 6 (Prompt 2): screen share, spotlight automático e reconexão ──

    test('start/stopScreenShare conectado chamam o serviço e flipam o estado',
        () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      expect(state().isScreenSharing, isFalse,
          reason: 'share começa OFF (nunca publicado no connect)');

      await notifier.startScreenShare('src-1');
      await settle();
      expect(rtc.startScreenShareCalls, 1);
      expect(rtc.startScreenShareSources, ['src-1']);
      expect(state().isScreenSharing, isTrue,
          reason: 'flag liga pós-await (sem otimismo)');

      await notifier.stopScreenShare();
      await settle();
      expect(rtc.stopScreenShareCalls, 1);
      expect(state().isScreenSharing, isFalse);
    });

    test('startScreenShare fora da sessão é ignorado; com share ativo é no-op',
        () async {
      final notifier = buildVoice();

      // Fora da sessão (idle): ignorado, 0 chamadas.
      await notifier.startScreenShare('src-1');
      await settle();
      expect(rtc.startScreenShareCalls, 0);
      expect(state().isScreenSharing, isFalse);

      // Conectado com share ativo: no-op — contador não cresce.
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      await notifier.join();
      await settle();
      await notifier.startScreenShare('src-2');
      await settle();
      expect(rtc.startScreenShareCalls, 1);

      await notifier.startScreenShare('src-3');
      await settle();
      expect(rtc.startScreenShareCalls, 1, reason: 'já compartilhando → no-op');
      expect(rtc.startScreenShareSources, ['src-2']);
    });

    test('falha de startScreenShare não derruba a sessão', () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      final notifier = buildVoice();
      await notifier.join();
      await settle();

      rtc.failStartScreenShareTimes = 1;
      await notifier.startScreenShare('src-1');
      await settle();

      expect(state().status, VoiceSessionStatus.connected);
      expect(state().isScreenSharing, isFalse,
          reason: 'sem otimismo: flag não liga quando o serviço falha');
      expect(state().errorMessage, 'Não foi possível iniciar o compartilhamento.');
      expect(rtc.disconnectCalls, 0,
          reason: 'erro de share nunca desconecta a sala');
    });

    test('falha de stopScreenShare mantém a sessão e avisa', () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      final notifier = buildVoice();
      await notifier.join();
      await settle();

      await notifier.startScreenShare('src-1');
      await settle();
      expect(state().isScreenSharing, isTrue);

      rtc.failStopScreenShare = true;
      await notifier.stopScreenShare();
      await settle();

      expect(state().status, VoiceSessionStatus.connected);
      expect(state().isScreenSharing, isTrue,
          reason: 'sem otimismo: flag não desliga quando o serviço falha');
      expect(state().errorMessage, 'Não foi possível encerrar o compartilhamento.');
      expect(rtc.disconnectCalls, 0);
    });

    test('ScreenShareEnabledChangedEvent do local reconcilia; de remoto não toca',
        () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      final notifier = buildVoice();
      await notifier.join();
      await settle();
      expect(state().isScreenSharing, isFalse);

      // O RtcService real emite isso quando o share local é confirmado.
      rtc.pushEvent(const ScreenShareEnabledChangedEvent(
        participantId: 'user_u1',
        isScreenSharing: true,
      ));
      await settle();
      expect(state().isScreenSharing, isTrue);

      rtc.pushEvent(const ScreenShareEnabledChangedEvent(
        participantId: 'user_u2',
        isScreenSharing: false,
      ));
      await settle();
      expect(state().isScreenSharing, isTrue,
          reason: 'evento de remoto não toca o botão local');
    });

    test('1º sharer no snapshot ganha destaque automático salvando o anterior',
        () async {
      rtc.localId = 'user_u1';
      final notifier = buildVoice();

      // Spotlight manual pré-existente (Fase 5).
      notifier.toggleSpotlight('user_u2');
      expect(state().spotlightParticipantId, 'user_u2');

      // 1º snapshot com sharer: destaque vai para o sharer, anterior salvo.
      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia', camera: true),
        _participant('user_u3', 'Caio', camera: true, screenShare: true),
      ]);
      await settle();

      expect(state().spotlightParticipantId, 'user_u3');
      expect(state().autoSpotlightActive, isTrue);
      expect(state().savedSpotlightParticipantId, 'user_u2',
          reason: 'spotlight manual anterior salvo para restaurar');
    });

    test('share termina: spotlight restaurado para o id salvo', () async {
      rtc.localId = 'user_u1';
      final notifier = buildVoice();

      notifier.toggleSpotlight('user_u2');
      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia', camera: true),
        _participant('user_u3', 'Caio', camera: true, screenShare: true),
      ]);
      await settle();
      expect(state().spotlightParticipantId, 'user_u3');
      expect(state().savedSpotlightParticipantId, 'user_u2');

      // Share termina: sem sharers no snapshot → restaura o manual anterior.
      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia', camera: true),
        _participant('user_u3', 'Caio', camera: true),
      ]);
      await settle();

      expect(state().spotlightParticipantId, 'user_u2');
      expect(state().autoSpotlightActive, isFalse);
      expect(state().savedSpotlightParticipantId, isNull);
    });

    test('share termina com spotlight anterior em grid: restaura para grid',
        () async {
      rtc.localId = 'user_u1';
      buildVoice();

      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia', screenShare: true),
      ]);
      await settle();
      expect(state().spotlightParticipantId, 'user_u2');
      expect(state().savedSpotlightParticipantId, isNull,
          reason: 'era grid — nada para restaurar');

      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia'),
      ]);
      await settle();

      expect(state().spotlightParticipantId, isNull, reason: 'volta ao grid');
      expect(state().autoSpotlightActive, isFalse);
      expect(state().savedSpotlightParticipantId, isNull);
    });

    test('2º sharer assume o destaque com auto-spotlight ativo', () async {
      rtc.localId = 'user_u1';
      buildVoice();

      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia', screenShare: true),
      ]);
      await settle();
      expect(state().spotlightParticipantId, 'user_u2');

      // Bia para de compartilhar e Caio assume: destaque move para Caio.
      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia'),
        _participant('user_u3', 'Caio', screenShare: true),
      ]);
      await settle();

      expect(state().spotlightParticipantId, 'user_u3',
          reason: 'troca de sharer: destaque segue o share');
      expect(state().autoSpotlightActive, isTrue);
    });

    test('dispensa manual do auto-spotlight não é re-forçada pelo snapshot',
        () async {
      rtc.localId = 'user_u1';
      final notifier = buildVoice();

      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia', screenShare: true),
      ]);
      await settle();
      expect(state().spotlightParticipantId, 'user_u2');
      expect(state().autoSpotlightActive, isTrue);

      // Toque no sharer em destaque: dispensa explícita → grid.
      notifier.toggleSpotlight('user_u2');
      expect(state().spotlightParticipantId, isNull);
      expect(state().autoSpotlightActive, isFalse);

      // Snapshot seguinte com o sharer AINDA compartilhando: não re-força.
      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia', screenShare: true),
      ]);
      await settle();

      expect(state().spotlightParticipantId, isNull);
      expect(state().autoSpotlightActive, isFalse,
          reason: 'dispensa manual desativa o auto — sem loop visual');
    });

    test('selecionar OUTRO participante dispensa o auto-spotlight (não só o sharer)',
        () async {
      rtc.localId = 'user_u1';
      final notifier = buildVoice();

      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia', screenShare: true),
        _participant('user_u3', 'Caio', camera: true),
      ]);
      await settle();
      expect(state().spotlightParticipantId, 'user_u2');
      expect(state().autoSpotlightActive, isTrue);

      // Seleção manual de OUTRO tile (não o sharer): assume o controle —
      // dispensa o auto e limpa o saved (senão o snapshot re-forçaria o
      // sharer e o fim do share restauraria um estado obsoleto).
      notifier.toggleSpotlight('user_u3');
      expect(state().spotlightParticipantId, 'user_u3');
      expect(state().autoSpotlightActive, isFalse);
      expect(state().savedSpotlightParticipantId, isNull);

      // Snapshot seguinte com o sharer AINDA compartilhando: não re-força.
      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia', screenShare: true),
        _participant('user_u3', 'Caio', camera: true),
      ]);
      await settle();
      expect(state().spotlightParticipantId, 'user_u3',
          reason: 'seleção manual sobrevive ao snapshot');
      expect(state().autoSpotlightActive, isFalse);
    });

    test('reconexão: Reconnecting mantém connected; Reconnected reseta mídia',
        () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      final notifier = buildVoice();
      await notifier.join();
      await settle();

      // Estado "sujo" antes da queda: mic/câmera/share ligados + spotlight.
      await notifier.toggleMicrophone();
      await settle();
      await notifier.toggleCamera();
      await settle();
      await notifier.startScreenShare('src-1');
      await settle();
      notifier.toggleSpotlight('user_u2');

      rtc.pushEvent(const ReconnectingEvent());
      await settle();
      expect(state().isReconnecting, isTrue);
      expect(state().status, VoiceSessionStatus.connected,
          reason: 'reconexão em andamento NÃO derruba para idle/error');

      rtc.pushEvent(const ReconnectedEvent());
      await settle();
      expect(state().isReconnecting, isFalse);
      expect(state().isMicrophoneEnabled, isFalse,
          reason: 'sala nova: mic republicado mutado');
      expect(state().isCameraEnabled, isFalse,
          reason: 'sala nova: câmera local recomeça off');
      expect(state().isScreenSharing, isFalse,
          reason: 'sala nova: share local recomeça off');
      expect(state().autoSpotlightActive, isFalse);
      expect(state().savedSpotlightParticipantId, isNull);
      expect(state().spotlightParticipantId, isNull);
    });

    test('DisconnectedEvent e leave resetam share/reconexão/auto-spotlight',
        () async {
      repo.onJoinVoice = (serverId, channelId) async => _joinInfo;
      rtc.localId = 'user_u1';
      final notifier = buildVoice();
      await notifier.join();
      await settle();

      await notifier.startScreenShare('src-1');
      await settle();
      notifier.toggleSpotlight('user_u2');
      rtc.pushEvent(const ReconnectingEvent());
      await settle();
      expect(state().isReconnecting, isTrue);

      // Queda final (não reconectou): idle com banner limpo e share resetado.
      rtc.pushEvent(const DisconnectedEvent());
      await settle();
      expect(state().status, VoiceSessionStatus.idle);
      expect(state().isReconnecting, isFalse);
      expect(state().isScreenSharing, isFalse);
      expect(state().autoSpotlightActive, isFalse);
      expect(state().savedSpotlightParticipantId, isNull);

      // Reconecta e sai: leave reseta igual.
      await notifier.join();
      await settle();
      await notifier.startScreenShare('src-2');
      await settle();
      notifier.toggleSpotlight('user_u2');
      await notifier.leave();
      await settle();
      expect(state().status, VoiceSessionStatus.idle);
      expect(state().isScreenSharing, isFalse);
      expect(state().isReconnecting, isFalse);
      expect(state().autoSpotlightActive, isFalse);
      expect(state().savedSpotlightParticipantId, isNull);
    });

    test('revalidação: sharer sem câmera mantém destaque; sem vídeo limpa',
        () async {
      rtc.localId = 'user_u1';
      final notifier = buildVoice();

      // Sharer entra compartilhando COM câmera (auto-spotlight ativo).
      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia', camera: true, screenShare: true),
      ]);
      await settle();
      expect(state().spotlightParticipantId, 'user_u2');

      // Desliga a câmera, segue compartilhando: destaque SE MANTÉM (a tela
      // é o vídeo do sharer — critério ampliado da revalidação).
      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia', screenShare: true),
      ]);
      await settle();
      expect(state().spotlightParticipantId, 'user_u2',
          reason: 'sharer sem câmera ainda merece destaque (destaque de tela vale)');

      // Share termina → restaura; um manual em quem NÃO tem câmera nem
      // share continua sendo limpo (comportamento Fase 5 intacto).
      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia'),
      ]);
      await settle();
      notifier.toggleSpotlight('user_u3');
      expect(state().spotlightParticipantId, 'user_u3');
      rtc.pushParticipants([
        _participant('user_u1', 'Ana'),
        _participant('user_u2', 'Bia'),
        _participant('user_u3', 'Caio'),
      ]);
      await settle();
      expect(state().spotlightParticipantId, isNull,
          reason: 'sem câmera E sem share: destaque limpo (Fase 5 intacto)');
    });
  });
}
