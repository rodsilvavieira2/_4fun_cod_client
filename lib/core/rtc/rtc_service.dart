import 'dart:async';

/// Gerador de token LiveKit para reconexão: devolve um token novo (o token
/// inicial tem validade curta — 10m no 4fun_cod — e o controller pode usar
/// esta função para obter um fresco antes de reconectar).
///
/// Observação: o `livekit_client` 2.11.0 NÃO tem suporte nativo a
/// `tokenGenerator` (nem em [RoomOptions] nem em [ConnectOptions]); o
/// [RtcService] aceita a função por contrato e a implementação a armazena
/// para o controller usar quando quiser reconectar.
typedef RtcTokenGenerator = Future<String> Function();

/// Participante de um canal de voz — espelho do estado do LiveKit sem
/// dependência do pacote (a UI nunca importa `livekit_client`).
///
/// Igualdade por [id] (identity do LiveKit, `user_<userId>`): duas
/// instâncias com a mesma identity representam a mesma pessoa, mesmo que
/// `name`/`isMicrophoneEnabled`/`isCameraEnabled`/`isScreenSharing`/
/// `isSpeaking` tenham mudado.
class RtcParticipant {
  const RtcParticipant({
    required this.id,
    required this.name,
    required this.isMicrophoneEnabled,
    required this.isCameraEnabled,
    required this.isScreenSharing,
    required this.isSpeaking,
  });

  /// Identity do participante no LiveKit (`user_<userId>`).
  final String id;

  /// Nome de exibição (fallback: a própria identity quando vazio).
  final String name;

  /// Se o microfone está publicado e não-mutado (fala o quê o outro lado
  /// ouve; escopo voz da Fase 4 — screen share é Fase 6).
  final bool isMicrophoneEnabled;

  /// Se a câmera está publicada e não-mutada (Fase 5). O vídeo em si não
  /// trafega por aqui: a UI busca a referência renderizável via
  /// [RtcService.videoTrackOf] e a passa ao `RtcVideoView`.
  final bool isCameraEnabled;

  /// Se está publicando a tela — track de screenShareVideo publicada e
  /// não-mutada (Fase 6). Espelho de [isCameraEnabled]; a imagem em si é
  /// obtida via [RtcService.screenTrackOf].
  final bool isScreenSharing;

  /// Se o participante está falando agora (ActiveSpeakersChangedEvent).
  final bool isSpeaking;

  RtcParticipant copyWith({
    String? name,
    bool? isMicrophoneEnabled,
    bool? isCameraEnabled,
    bool? isScreenSharing,
    bool? isSpeaking,
  }) {
    return RtcParticipant(
      id: id,
      name: name ?? this.name,
      isMicrophoneEnabled: isMicrophoneEnabled ?? this.isMicrophoneEnabled,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      isSpeaking: isSpeaking ?? this.isSpeaking,
    );
  }

  @override
  bool operator ==(Object other) => other is RtcParticipant && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Evento de tempo real do canal de voz, emitido pelo [RtcService].
sealed class RtcEvent {
  const RtcEvent();
}

/// Um participante entrou na sala de voz.
class ParticipantJoinedEvent extends RtcEvent {
  const ParticipantJoinedEvent({required this.participant});

  final RtcParticipant participant;
}

/// Um participante saiu da sala de voz.
class ParticipantLeftEvent extends RtcEvent {
  const ParticipantLeftEvent({required this.participantId});

  final String participantId;
}

/// O microfone de um participante foi habilitado/desabilitado (mute/unmute
/// ou publicação/despublicação da track de mic).
class MicEnabledChangedEvent extends RtcEvent {
  const MicEnabledChangedEvent({
    required this.participantId,
    required this.isMicrophoneEnabled,
  });

  final String participantId;
  final bool isMicrophoneEnabled;
}

/// A câmera de um participante foi habilitada/desabilitada (mute/unmute ou
/// publicação/despublicação da track de câmera — Fase 5). Espelho exato do
/// [MicEnabledChangedEvent]; o vídeo em si é obtido via [RtcService.videoTrackOf].
class CameraEnabledChangedEvent extends RtcEvent {
  const CameraEnabledChangedEvent({
    required this.participantId,
    required this.isCameraEnabled,
  });

  final String participantId;
  final bool isCameraEnabled;
}

/// A tela de um participante começou/parou de ser compartilhada
/// (publicação/despublicação da track de screenShareVideo — Fase 6).
/// Espelho do [CameraEnabledChangedEvent]; a imagem em si é obtida via
/// [RtcService.screenTrackOf].
class ScreenShareEnabledChangedEvent extends RtcEvent {
  const ScreenShareEnabledChangedEvent({
    required this.participantId,
    required this.isScreenSharing,
  });

  final String participantId;
  final bool isScreenSharing;
}

/// Um participante começou/parou de falar.
class SpeakingChangedEvent extends RtcEvent {
  const SpeakingChangedEvent({
    required this.participantId,
    required this.isSpeaking,
  });

  final String participantId;
  final bool isSpeaking;
}

/// A sala de voz caiu por conta própria (servidor encerrou, rede caiu).
///
/// O [RtcService] já limpou o estado interno (participantes vazios, streams
/// vivos); o controller usa este evento para sair do estado `connected`
/// (voltar para `idle`) e permitir uma nova entrada.
class DisconnectedEvent extends RtcEvent {
  const DisconnectedEvent();
}

/// A RECONEXÃO AUTOMÁTICA do serviço começou (a sala caiu por motivo não
/// iniciado pelo app; o serviço vai tentar restabelecer com token fresco).
/// A UI mostra "Reconectando…" e o controller NÃO deve cair para idle.
class ReconnectingEvent extends RtcEvent {
  const ReconnectingEvent();
}

/// A RECONEXÃO AUTOMÁTICA concluiu (nova sala criada e conectada). O
/// serviço republicou o mic ATIVO (padrão do connect desde a Fase 7);
/// câmera e share locais recomeçam DESLIGADOS (risco V1 documentado).
class ReconnectedEvent extends RtcEvent {
  const ReconnectedEvent();
}

/// Qualidade de recepção de vídeo remoto (Fase 5).
///
/// SEM `off`: "desligar" um tile é decisão da UI (não montar o RtcVideoView).
/// O enum do LiveKit tem apenas LOW/MEDIUM/HIGH — o serviço traduz
/// low/medium/high; OFF não existe no protocolo.
enum RtcVideoQuality { low, medium, high }

/// Qualidade de PUBLICAÇÃO da câmera local (Fase 7) — o "teto" de
/// resolução/fps/bitrate que EU transmito.
///
/// DISTINTO de [RtcVideoQuality] (recepção remota): este enum governa a
/// captura/publicação local. `auto` = comportamento adaptativo (simulcast
/// h180/h540/h1080_60 + dynacast), default da feature.
enum RtcCameraQuality { auto, q1080, q720, q480, q360, q240, q144 }

/// Dispositivo de captura de vídeo (câmera).
class RtcVideoDevice {
  const RtcVideoDevice({required this.id, required this.label});

  /// deviceId do MediaDevice (usado em [RtcService.switchCamera]).
  final String id;

  /// Label amigável (pode vir vazio antes da permissão de câmera).
  final String label;
}

/// Referência OPACA a uma track de vídeo.
///
/// A UI recebe isto de [RtcService.videoTrackOf] e passa ao `RtcVideoView`
/// (core/rtc/rtc_video_view.dart) sem conhecer o tipo concreto (que vive no
/// LiveKit). Só o `LiveKitRtcService` sabe resolvê-lo para o renderer.
abstract class RtcVideoTrackRef {
  const RtcVideoTrackRef();
}

/// Abstração de voz em tempo real (Fase 4 — LiveKit por baixo).
///
/// Escopo voz: mic (Fase 4), câmera (Fase 5) e screen share (Fase 6). A UI
/// conversa só com esta interface; a implementação concreta fica em
/// `livekit_rtc_service.dart`.
abstract class RtcService {
  /// Conecta a uma sala de voz.
  ///
  /// [tokenGenerator], quando fornecido, é a fonte de tokens frescos para
  /// reconexão (ver [RtcTokenGenerator]). Erros de conexão propagam para
  /// quem chama (o controller decide o que mostrar).
  Future<void> connect(
    String url,
    String token, {
    RtcTokenGenerator? tokenGenerator,
  });

  /// Desconecta e limpa todo o estado (participantes e streams seguem
  /// vivos para um novo [connect]).
  Future<void> disconnect();

  /// Habilita o microfone local (publica/desmuta a track de mic).
  Future<void> enableMicrophone();

  /// Desabilita o microfone local (muta a track de mic).
  Future<void> disableMicrophone();

  /// Habilita a câmera local (publica a track de câmera, ou desmuta a
  /// publicação existente). A câmera NUNCA é publicada no [connect] —
  /// começa OFF; só esta chamada liga o vídeo.
  ///
  /// Erros de permissão/hardware propagam para o controller decidir a
  /// mensagem — uma falha de câmera NÃO derruba a sessão.
  Future<void> enableCamera();

  /// Desabilita a câmera local (muta a publicação — ela PERMANECE
  /// publicada, como o mic).
  Future<void> disableCamera();

  /// Publica a tela local (track de screenShareVideo) capturando a fonte
  /// [sourceId] (id do DesktopCapturerSource obtido via
  /// `RtcScreenSharePicker`). No-op quando o share já está ativo. A câmera
  /// NÃO é afetada — share e câmera coexistem.
  ///
  /// Erros de captura propagam para o controller decidir a mensagem — falha
  /// de share NUNCA derruba a sessão.
  Future<void> startScreenShare(String sourceId);

  /// Encerra o compartilhamento de tela local. DIFERENTE da câmera, DESPUBLICA
  /// a track (o SDK remove a publicação em setScreenShareEnabled(false)).
  Future<void> stopScreenShare();

  /// Referência renderizável da TELA de [participantId], ou null quando não
  /// está compartilhando (track inexistente ou publicação mutada). Nulo
  /// também quando desconectado/participante desconhecido. Reusa
  /// [RtcVideoTrackRef]/`RtcVideoView` — sem tipo novo de track.
  RtcVideoTrackRef? screenTrackOf(String participantId);

  /// Define a qualidade de recepção do vídeo da câmera remota de
  /// [participantId] (low/medium/high). Sem efeito quando o participante é
  /// desconhecido, é o local, ou a câmera dele está OFF/ausente.
  Future<void> setQuality(String participantId, RtcVideoQuality quality);

  /// Lista as câmeras disponíveis no dispositivo (enumerateDevices
  /// `type: 'videoinput'`). Labels podem vir vazias antes da permissão.
  Future<List<RtcVideoDevice>> listCameraDevices();

  /// Troca a câmera local em uso para [deviceId] (id de [RtcVideoDevice]).
  /// Sem efeito quando a câmera está OFF — a primeira [enableCamera] usa o
  /// device default.
  Future<void> switchCamera(String deviceId);

  /// Define o perfil de qualidade de PUBLICAÇÃO da câmera local (o "teto"
  /// de resolução/fps/bitrate). `auto` mantém o comportamento adaptativo
  /// (simulcast + dynacast). Pode ser chamado com a câmera OFF (fica
  /// pendente para a próxima [enableCamera]) ou LIGADA (aplica ao vivo,
  /// despublicando+republicando a track — blip visual breve). Erros de
  /// captura propagam para o controller decidir a mensagem — uma falha
  /// NÃO derruba a sessão.
  Future<void> setCameraQuality(RtcCameraQuality quality);

  /// Perfil de câmera atualmente configurado (default: [RtcCameraQuality.auto]).
  RtcCameraQuality get cameraQuality;

  /// Referência renderizável da câmera de [participantId], ou null quando a
  /// câmera está OFF/ausente (track inexistente ou publicação mutada).
  /// Nulo também quando desconectado/participante desconhecido. A UI passa
  /// o ref ao `RtcVideoView` sem ver o tipo concreto.
  RtcVideoTrackRef? videoTrackOf(String participantId);

  /// Identity do participante LOCAL na sala atual (nulo quando desconectado).
  ///
  /// A UI usa para destacar o usuário no painel e para casar eventos de mic
  /// local; a ordenação "local primeiro" também depende dele.
  String? get localParticipantId;

  /// Snapshot da lista atual de participantes da sala (nova lista a cada
  /// mudança: join/leave, mic e fala).
  Stream<List<RtcParticipant>> get participants;

  /// Eventos discretos da sala de voz ([RtcEvent]).
  Stream<RtcEvent> get events;
}
