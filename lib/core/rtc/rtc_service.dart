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
/// Fonte de áudio remoto para volume individual: a voz (microfone) ou o
/// áudio que acompanha um compartilhamento de tela (transmissão).
enum RtcAudioSource { microphone, screenShareAudio }

class RtcParticipant {
  const RtcParticipant({
    required this.id,
    required this.name,
    required this.isMicrophoneEnabled,
    required this.isCameraEnabled,
    required this.isScreenSharing,
    required this.isSystemAudioEnabled,
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

  /// Se está publicando o ÁUDIO DE SISTEMA (track de screenShareAudio —
  /// som de jogos/vídeos/música junto com o share de tela). Espelho de
  /// [isScreenSharing]; o áudio em si não trafega por aqui.
  final bool isSystemAudioEnabled;

  /// Se o participante está falando agora (ActiveSpeakersChangedEvent).
  final bool isSpeaking;

  RtcParticipant copyWith({
    String? name,
    bool? isMicrophoneEnabled,
    bool? isCameraEnabled,
    bool? isScreenSharing,
    bool? isSystemAudioEnabled,
    bool? isSpeaking,
  }) {
    return RtcParticipant(
      id: id,
      name: name ?? this.name,
      isMicrophoneEnabled: isMicrophoneEnabled ?? this.isMicrophoneEnabled,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      isSystemAudioEnabled: isSystemAudioEnabled ?? this.isSystemAudioEnabled,
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

/// Um participante começou/parou de transmitir o ÁUDIO DE SISTEMA junto
/// com o screen share (publicação/despublicação da track de
/// screenShareAudio — Fase 6.1). Espelho do [ScreenShareEnabledChangedEvent].
class SystemAudioEnabledChangedEvent extends RtcEvent {
  const SystemAudioEnabledChangedEvent({
    required this.participantId,
    required this.isSystemAudioEnabled,
  });

  final String participantId;
  final bool isSystemAudioEnabled;
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

/// O playback de áudio remoto está BLOQUEADO pelo browser (política de
/// autoplay — `NotAllowedError` no web). A UI deve mostrar um affordance e
/// chamar [RtcService.resumeAudio] num gesto do usuário. Desktop/nativo não
/// emite (sem autoplay policy).
class AudioPlaybackBlockedEvent extends RtcEvent {
  const AudioPlaybackBlockedEvent();
}

/// O playback de áudio remoto foi RETOMADO ([RtcService.resumeAudio]
/// bem-sucedido — o gesto do usuário desbloqueou o áudio no web).
class AudioPlaybackResumedEvent extends RtcEvent {
  const AudioPlaybackResumedEvent();
}

/// Latência atual da conexão de voz até o servidor LiveKit.
///
/// O valor é o RTT do par ICE selecionado pelo WebRTC, em milissegundos.
/// `null` indica que a medição ainda não está disponível ou que a conexão
/// está sendo refeita.
class ConnectionLatencyChangedEvent extends RtcEvent {
  const ConnectionLatencyChangedEvent({required this.latencyMs});

  final int? latencyMs;
}

/// A qualidade EFETIVA do screen share local mudou por decisão do
/// controlador adaptativo (ou assumiu o objetivo após ação do usuário).
/// `effective` é sempre `<=` o objetivo; a UI mostra `objetivo · efetivo`
/// quando diferem.
class ScreenShareEffectiveQualityChangedEvent extends RtcEvent {
  const ScreenShareEffectiveQualityChangedEvent({required this.effective});

  final RtcScreenShareQuality effective;
}

/// Qualidade de recepção de vídeo remoto (Fase 5).
///
/// SEM `off`: "desligar" um tile é decisão da UI (não montar o RtcVideoView).
/// O enum do LiveKit tem apenas LOW/MEDIUM/HIGH — o serviço traduz
/// low/medium/high; OFF não existe no protocolo.
enum RtcVideoQuality { low, medium, high }

/// Qualidade de PUBLICAÇÃO da câmera local (Fase 7) — o "teto" de
/// resolução/fps/bitrate da tela ou janela transmitida.
///
/// A câmera não usa este controle: permanece nos defaults de captura e
/// publicação do LiveKit/dispositivo.
enum RtcScreenShareQuality {
  auto,
  q1080p60,
  q1080p30,
  q1080p15,
  q720p15,
  q360p3,
}

/// Categoria de um dispositivo de mídia disponível no sistema.
enum RtcMediaDeviceKind { audioInput, audioOutput, videoInput }

/// Dispositivo de mídia enumerado pelo sistema operacional/navegador.
class RtcMediaDevice {
  const RtcMediaDevice({
    required this.id,
    required this.label,
    required this.kind,
  });

  /// deviceId do MediaDevice (usado em [RtcService.switchCamera]).
  final String id;

  /// Label amigável (pode vir vazio antes da permissão de câmera).
  final String label;

  final RtcMediaDeviceKind kind;
}

/// Dispositivo de captura de vídeo (câmera).
class RtcVideoDevice extends RtcMediaDevice {
  const RtcVideoDevice({required super.id, required super.label})
    : super(kind: RtcMediaDeviceKind.videoInput);
}

/// Dispositivo de áudio de entrada ou saída.
class RtcAudioDevice extends RtcMediaDevice {
  const RtcAudioDevice({
    required super.id,
    required super.label,
    required super.kind,
  }) : assert(
         kind == RtcMediaDeviceKind.audioInput ||
             kind == RtcMediaDeviceKind.audioOutput,
       );
}

/// Referência OPACA a uma track de vídeo.
///
/// A UI recebe isto de [RtcService.videoTrackOf] e passa ao `RtcVideoView`
/// (core/rtc/rtc_video_view.dart) sem conhecer o tipo concreto (que vive no
/// LiveKit). Só o `LiveKitRtcService` sabe resolvê-lo para o renderer.
abstract class RtcVideoTrackRef {
  const RtcVideoTrackRef();
}

/// Falha ao publicar o ÁUDIO DE SISTEMA durante o screen share (nenhum
/// device monitor/loopback no SO, permissão negada, etc.).
///
/// O share de VÍDEO NÃO é afetado — a track de tela já foi publicada quando
/// esta exceção é lançada. O controller decide a mensagem; a sessão nunca
/// cai (mesmo invariante de falha de captura do share).
class SystemAudioPublishException implements Exception {
  const SystemAudioPublishException(this.message);

  final String message;

  @override
  String toString() => message;
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
  ///
  /// Sem sala ativa, registra a preferência para o próximo [connect].
  Future<void> enableMicrophone();

  /// Desabilita o microfone local (muta a track de mic).
  ///
  /// Sem sala ativa, registra a preferência para o próximo [connect].
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

  /// Inicia um preview LOCAL da câmera, sem publicar vídeo na sala.
  ///
  /// Quando a câmera já está transmitindo, devolve a própria track publicada
  /// para evitar uma segunda captura do hardware. Quando está desligada,
  /// cria uma track temporária, que deve ser liberada com
  /// [stopCameraPreview]. Erros de permissão/hardware propagam sem afetar a
  /// sessão de voz nem o estado de publicação da câmera.
  Future<RtcVideoTrackRef> startCameraPreview({String? deviceId});

  /// Libera a captura temporária criada por [startCameraPreview]. Nunca para
  /// nem muta uma câmera que já esteja publicada na sala.
  Future<void> stopCameraPreview();

  /// Publica a tela local (track de screenShareVideo). Quando [sourceId] é
  /// nulo, o SDK delega a escolha de janela/display ao portal nativo do SO.
  /// No-op quando o share já está ativo. A câmera NÃO é afetada — share e
  /// câmera coexistem.
  ///
  /// Com [includeSystemAudio] true, publica TAMBÉM o áudio de sistema
  /// (track de screenShareAudio — som de jogos/vídeos/música) capturando o
  /// device monitor/loopback do SO. A falha do áudio NUNCA bloqueia o share:
  /// o vídeo sai primeiro e, sem device disponível, lança
  /// [SystemAudioPublishException] (o controller decide a mensagem).
  ///
  /// Erros de captura propagam para o controller decidir a mensagem — falha
  /// de share NUNCA derruba a sessão.
  ///
  /// [quality], quando informado, é one-shot: vale só para este share e NÃO
  /// altera o perfil pendente ([screenShareQuality]). Quando omitido, usa o
  /// perfil pendente (comportamento histórico).
  Future<void> startScreenShare(
    String? sourceId, {
    bool includeSystemAudio = true,
    RtcScreenShareQuality? quality,
  });

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

  /// Define a qualidade de recepção da TELA remota de [participantId]
  /// (low/medium/high). Sem efeito quando o participante é desconhecido,
  /// é o local, ou não está compartilhando tela. Implementação padrão
  /// no-op (a câmera usa [setQuality]); o LiveKit sobrescreve.
  Future<void> setScreenQuality(
    String participantId,
    RtcVideoQuality quality,
  ) async {}

  /// Lista as câmeras disponíveis no dispositivo (enumerateDevices
  /// `type: 'videoinput'`). Labels podem vir vazias antes da permissão.
  Future<List<RtcVideoDevice>> listCameraDevices();

  /// Lista os microfones disponíveis. Labels podem estar vazias antes da
  /// permissão no navegador.
  Future<List<RtcAudioDevice>> listAudioInputDevices();

  /// Lista as saídas de áudio disponíveis.
  Future<List<RtcAudioDevice>> listAudioOutputDevices();

  /// Emite quando o sistema informa adição/remoção de dispositivos.
  Stream<void> get mediaDevicesChanged;

  /// Define o microfone. `null` volta ao padrão atual do sistema.
  Future<void> selectAudioInput(String? deviceId);

  /// Define a saída de áudio. `null` volta ao padrão atual do sistema.
  Future<void> selectAudioOutput(String? deviceId);

  /// Liga/desliga localmente todo áudio remoto, sem sinalizar essa decisão à
  /// sala. Sem sala ativa, registra a preferência para as tracks da próxima
  /// conexão. O controller usa isso para implementar o ensurdecer.
  Future<void> setRemoteAudioEnabled(bool enabled);

  /// Define o volume geral de saída do áudio remoto, como ganho `0.0..2.0`
  /// (`1.0` = 100%). Valores fora da faixa são normalizados. Sem sala ativa,
  /// fica pendente para as tracks da próxima conexão. O ganho efetivo por
  /// participante é `saída × individual`, com teto `4.0`. Ganho `0.0` é
  /// silêncio (nunca vira stop/unsubscribe/deafen).
  Future<void> setOutputVolume(double gain);

  /// Define o ganho do microfone publicado, como ganho `0.0..1.0`
  /// (`1.0` = 100%). Sem sala ativa, fica pendente para a próxima publicação.
  /// Troca de microfone, reconnect e unmute devem reaplicar este ganho.
  Future<void> setInputVolume(double gain);

  /// Liga/desliga a supressão de ruído nativa do WebRTC no microfone local.
  ///
  /// Echo cancellation, AGC e high-pass continuam ligados. Sem sala ativa,
  /// fica pendente para a próxima publicação do microfone.
  Future<void> setNoiseSuppressionEnabled(bool enabled);

  /// Define o volume individual de um participante remoto, como ganho
  /// `0.0..2.0`. Aplica-se a TODAS as faixas de áudio dele (voz + áudio de
  /// screen share). Local/desconhecido → no-op seguro. Sem sala ativa, fica
  /// pendente e é aplicado quando as tracks chegarem.
  Future<void> setParticipantVolume(String identity, double gain);

  /// Define o volume individual de UMA fonte de áudio de um participante
  /// remoto (voz OU áudio da transmissão), como ganho `0.0..2.0`. A outra
  /// fonte não é afetada. Local/desconhecido → no-op seguro. Sem sala
  /// ativa, fica pendente e é aplicado quando as tracks chegarem.
  Future<void> setParticipantSourceVolume(
    String identity,
    RtcAudioSource source,
    double gain,
  );

  /// Seleciona a câmera usada pelo preview e pela publicação local.
  ///
  /// Com preview temporário, aplica a troca nele. Com a câmera publicada,
  /// troca a track ao vivo. Sem captura ativa, apenas registra a escolha para
  /// o próximo [enableCamera].
  Future<void> switchCamera(String deviceId);

  /// Define o teto de qualidade do compartilhamento de tela/janela.
  /// Antes do share, a escolha fica pendente para a próxima publicação; com
  /// share ativo, é aplicada no mesmo sender, sem trocar a track ou reabrir
  /// o seletor do sistema. Falhas não encerram a sessão.
  Future<void> setScreenShareQuality(RtcScreenShareQuality quality);

  /// Perfil de screen share atualmente configurado. Reseta para [auto] ao
  /// sair da sala ou desconectar.
  RtcScreenShareQuality get screenShareQuality;

  /// Qualidade EFETIVA do compartilhamento local (`<= screenShareQuality`),
  /// decidida pelo controlador adaptativo (spec de qualidade adaptativa,
  /// V1 — só screen share). Sem share ativo, é igual ao objetivo. A UI
  /// observa as trocas via [ScreenShareEffectiveQualityChangedEvent].
  RtcScreenShareQuality get effectiveScreenShareQuality;

  /// Retoma o playback de áudio remoto. Necessário no web quando a política
  /// de autoplay do browser bloqueou o áudio ([AudioPlaybackBlockedEvent]) —
  /// DEVE ser chamada dentro de um gesto do usuário (toque no banner/UI).
  /// Desktop/nativo: no-op seguro. Best-effort: o estado real chega via
  /// [AudioPlaybackBlockedEvent]/[AudioPlaybackResumedEvent].
  Future<void> resumeAudio();

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
