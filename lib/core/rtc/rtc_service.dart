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
/// `name`/`isMicrophoneEnabled`/`isSpeaking` tenham mudado.
class RtcParticipant {
  const RtcParticipant({
    required this.id,
    required this.name,
    required this.isMicrophoneEnabled,
    required this.isSpeaking,
  });

  /// Identity do participante no LiveKit (`user_<userId>`).
  final String id;

  /// Nome de exibição (fallback: a própria identity quando vazio).
  final String name;

  /// Se o microfone está publicado e não-mutado (fala o quê o outro lado
  /// ouve; escopo voz da Fase 4 — câmera/screen são Fase 5/6).
  final bool isMicrophoneEnabled;

  /// Se o participante está falando agora (ActiveSpeakersChangedEvent).
  final bool isSpeaking;

  RtcParticipant copyWith({
    String? name,
    bool? isMicrophoneEnabled,
    bool? isSpeaking,
  }) {
    return RtcParticipant(
      id: id,
      name: name ?? this.name,
      isMicrophoneEnabled: isMicrophoneEnabled ?? this.isMicrophoneEnabled,
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

/// Abstração de voz em tempo real (Fase 4 — LiveKit por baixo).
///
/// Escopo voz apenas: câmera (Fase 5) e screen share (Fase 6) entram como
/// métodos novos aqui quando forem implementados. A UI conversa só com esta
/// interface; a implementação concreta fica em `livekit_rtc_service.dart`.
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
