import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

// `SpeakingChangedEvent` existe TAMBÉM no livekit_client (colisão de nome
// com o RtcEvent do contrato); o projeto usa o do rtc_service.dart.
import 'package:livekit_client/livekit_client.dart'
    hide SpeakingChangedEvent;

import 'rtc_service.dart';

/// Implementação de [RtcService] sobre o LiveKit.
///
/// ÚNICO arquivo do projeto autorizado a importar `livekit_client`
/// (invariante de arquitetura do 4fun_cod: a UI só enxerga [RtcService]).
///
/// API validada na 2.11.0 (ver skill 4fun-cod-codebase):
/// - [RoomOptions] (incl. `defaultAudioCaptureOptions`/`defaultAudioPublishOptions`)
///   vai no CONSTRUTOR do [Room], não no `connect()`;
/// - eventos via `room.events.on<T>(...)` — a API antiga `room.on<RoomEvent>`
///   não existe mais;
/// - `TrackPublication.muted` é getter-only: mutar é via `publication.mute()`
///   (e desmutar via `unmute()`), que mantêm o estado `muted` em sincronia
///   com o servidor;
/// - `isMicrophoneEnabled()` é MÉTODO (não getter) no [Participant];
/// - `connectionState` colide com o enum `ConnectionState` do Flutter —
///   este serviço nunca lê esse enum, só reage a [RoomDisconnectedEvent];
/// - `RoomOptions`/`ConnectOptions` NÃO têm `tokenGenerator` na 2.11.0: a
///   função recebida em [connect] é apenas armazenada (ver [tokenGenerator])
///   para o controller obter tokens frescos e reconectar manualmente.
class LiveKitRtcService implements RtcService {
  LiveKitRtcService({RoomOptions? roomOptions})
      : _roomOptions = roomOptions ?? defaultRoomOptions;

  /// Configuração de áudio da Fase 4 (default do serviço — a UI nunca
  /// configura isso): echo cancellation + noise suppression + AGC na
  /// captura e Opus em ABR com teto de 64 kbps na publicação (range do
  /// plano: 32–64k; o encoder WebRTC opera em ABR entre o piso e o teto).
  ///
  /// Pitfall 2.11.0: [AudioCaptureOptions] NÃO tem campo `enabled` — o
  /// "mic mutado por padrão" é feito no [connect] via `publication.mute()`.
  static final RoomOptions defaultRoomOptions = RoomOptions(
    defaultAudioCaptureOptions: const AudioCaptureOptions(
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
    ),
    defaultAudioPublishOptions: const AudioPublishOptions(
      encoding: AudioEncoding(maxBitrate: 64000),
    ),
  );

  /// Opções da sala (mic publicado muted por padrão no [connect]).
  final RoomOptions _roomOptions;

  Room? _room;
  RtcTokenGenerator? _tokenGenerator;
  bool _disposed = false;

  /// identity → participante atual da sala.
  final Map<String, RtcParticipant> _participantsById = {};

  final StreamController<List<RtcParticipant>> _participantsController =
      StreamController<List<RtcParticipant>>.broadcast();
  final StreamController<RtcEvent> _eventsController =
      StreamController<RtcEvent>.broadcast();

  /// Canceladores dos listeners do [Room] atual (limpos no disconnect).
  final List<CancelListenFunc> _roomListeners = [];

  @override
  Stream<List<RtcParticipant>> get participants =>
      _participantsController.stream;

  @override
  Stream<RtcEvent> get events => _eventsController.stream;

  /// Gerador de token passado no último [connect], disponível para o
  /// controller obter um token fresco numa reconexão manual.
  RtcTokenGenerator? get tokenGenerator => _tokenGenerator;

  @override
  String? get localParticipantId => _room?.localParticipant?.identity;

  @override
  Future<void> connect(
    String url,
    String token, {
    RtcTokenGenerator? tokenGenerator,
  }) async {
    // Sempre parte de um estado limpo (idempotente com um connect anterior).
    // O await garante que o disconnect/dispose nativos do Room ANTERIOR
    // terminaram antes de criar o novo (sem dois Room/PeerConnection vivos).
    await disconnect();
    _tokenGenerator = tokenGenerator;

    final room = Room(roomOptions: _roomOptions);
    _room = room;
    _wire(room);

    try {
      await room.connect(url, token);
    } catch (_) {
      await _cleanupRoom();
      rethrow; // o controller trata o erro (token inválido, servidor fora etc.)
    }

    // Publica o mic MUTADO por padrão: o usuário entra na sala sem
    // transmitir áudio; habilita via enableMicrophone().
    //
    // RISCO ACEITO (V1): entre `setMicrophoneEnabled(true)` e `mute()` há uma
    // janela de milissegundos em que a track pode ir à rede destapada. O SDK
    // 2.11.0 não permite publicar já mutado (`AudioCaptureOptions` não tem
    // `enabled`); o mute é o mais cedo possível após a publicação.
    final localParticipant = room.localParticipant;
    if (localParticipant == null) {
      // Impossível na prática pós-connect (o Room sempre tem o participante
      // local); sem ele não há mic a publicar.
      return;
    }
    try {
      final micPublication =
          await localParticipant.setMicrophoneEnabled(true);
      if (micPublication != null && !micPublication.muted) {
        await micPublication.mute(); // `muted` é getter-only na 2.11.0
      }
    } catch (_) {
      // Falha ao publicar/mutar o mic: NUNCA deixa o Room órfão com o mic
      // destapado (invariante "mic sempre entra mutado") — limpa e propaga.
      await _cleanupRoom();
      rethrow;
    }
    // O participante local entra no snapshot sem evento joined (quem chamou
    // o connect já sabe que entrou).
    _syncParticipant(localParticipant);
    _emitSnapshot();
  }

  @override
  Future<void> disconnect() => _cleanupRoom();

  @override
  Future<void> enableMicrophone() async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    await localParticipant.setMicrophoneEnabled(true);
    // O estado é atualizado pelos eventos TrackMuted/Unmuted +
    // LocalTrackPublished/Unpublished.
  }

  @override
  Future<void> disableMicrophone() async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    await localParticipant.setMicrophoneEnabled(false);
  }

  /// Encerramento definitivo (provider descartado): desconecta, limpa
  /// estado e fecha os streams.
  void dispose() {
    if (_disposed) return;
    // Fire-and-forget: o provider está sendo descartado; o cleanup segue
    // em background mas NUNCA lança (try/catch interno).
    unawaited(_cleanupRoom());
    _disposed = true;
    _participantsController.close();
    _eventsController.close();
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  void _wire(Room room) {
    _roomListeners.addAll([
      room.events.on<ParticipantConnectedEvent>((e) {
        final isLocal = e.participant.identity == room.localParticipant?.identity;
        _syncParticipant(e.participant);
        // Participantes REMOTOS emitem joined (o local entra no snapshot sem
        // evento — quem chamou o connect já sabe que entrou).
        if (!isLocal) {
          _emitEvent(ParticipantJoinedEvent(participant: _participantsById[e.participant.identity]!));
        }
        _emitSnapshot();
      }),
      room.events.on<ParticipantDisconnectedEvent>((e) {
        final id = e.participant.identity;
        if (_participantsById.remove(id) != null) {
          _emitEvent(ParticipantLeftEvent(participantId: id));
          _emitSnapshot();
        }
      }),
      // Reconexão automática do SDK em blips de rede: loga a transição
      // (a UI continua em connected; se a reconexão falhar de vez, o
      // RoomDisconnectedEvent abaixo volta o controller para idle).
      // Eventos vazios na 2.11.0 (sem payload) — só o fato importa.
      room.events.on<RoomReconnectingEvent>((_) {
        debugPrint('[rtc] reconexão completa em andamento');
      }),
      room.events.on<RoomResumingEvent>((_) {
        debugPrint('[rtc] retomando sinal (peer connections ativas)');
      }),
      room.events.on<RoomReconnectedEvent>((_) {
        debugPrint('[rtc] reconexão concluída');
      }),
      // Publicação/despublicação de tracks (remoto e local) e mute/unmute:
      // re-deriva o estado de mic do participante afetado e emite
      // MicEnabledChangedEvent se mudou.
      room.events.on<TrackPublishedEvent>((e) {
        _syncParticipant(e.participant);
        _emitSnapshot();
      }),
      room.events.on<TrackUnpublishedEvent>((e) {
        _syncParticipant(e.participant);
        _emitSnapshot();
      }),
      room.events.on<LocalTrackPublishedEvent>((e) {
        _syncParticipant(e.participant);
        _emitSnapshot();
      }),
      room.events.on<LocalTrackUnpublishedEvent>((e) {
        _syncParticipant(e.participant);
        _emitSnapshot();
      }),
      room.events.on<TrackMutedEvent>((e) {
        _syncParticipant(e.participant);
        _emitSnapshot();
      }),
      room.events.on<TrackUnmutedEvent>((e) {
        _syncParticipant(e.participant);
        _emitSnapshot();
      }),
      room.events.on<ActiveSpeakersChangedEvent>((e) {
        _applySpeakers(e.speakers);
        _emitSnapshot();
      }),
      room.events.on<ParticipantNameUpdatedEvent>((e) {
        _syncParticipant(e.participant);
        _emitSnapshot();
      }),
      // Sala caiu por conta própria (servidor encerrou/rede): avisa o
      // controller (que volta para idle) e limpa o estado; os streams
      // seguem vivos para um novo connect().
      room.events.on<RoomDisconnectedEvent>((_) {
        _emitEvent(DisconnectedEvent());
        unawaited(_cleanupRoom());
      }),
    ]);
  }

  /// Re-deriva o [RtcParticipant] de um [Participant] do LiveKit e emite
  /// [MicEnabledChangedEvent] se o estado de mic mudou. O participante
  /// entra no mapa mesmo se ainda não tinha evento joined (robustez).
  void _syncParticipant(Participant participant) {
    final id = participant.identity;
    final previous = _participantsById[id];
    final updated = RtcParticipant(
      id: id,
      name: participant.name.isEmpty ? id : participant.name,
      isMicrophoneEnabled: participant.isMicrophoneEnabled(),
      isSpeaking: previous?.isSpeaking ?? false,
    );
    _participantsById[id] = updated;

    if (previous != null &&
        previous.isMicrophoneEnabled != updated.isMicrophoneEnabled) {
      _emitEvent(
        MicEnabledChangedEvent(
          participantId: id,
          isMicrophoneEnabled: updated.isMicrophoneEnabled,
        ),
      );
    }
  }

  /// Aplica a lista de falantes do [ActiveSpeakersChangedEvent]: quem está
  /// fora da lista parou de falar, quem entrou começou.
  void _applySpeakers(List<Participant> speakers) {
    final speakingIds = speakers.map((p) => p.identity).toSet();
    // Snapshot antes de iterar: o handler não pode mutar o mapa enquanto
    // percorre (os eventos são síncronos por listener, mas o mapa é
    // compartilhado com os demais listeners).
    for (final entry in _participantsById.entries.toList()) {
      final nowSpeaking = speakingIds.contains(entry.key);
      if (entry.value.isSpeaking != nowSpeaking) {
        _participantsById[entry.key] =
            entry.value.copyWith(isSpeaking: nowSpeaking);
        _emitEvent(
          SpeakingChangedEvent(
            participantId: entry.key,
            isSpeaking: nowSpeaking,
          ),
        );
      }
    }
  }

  void _emitSnapshot() {
    if (_disposed) return;
    _participantsController
        .add(_participantsById.values.toList(growable: false));
  }

  void _emitEvent(RtcEvent event) {
    if (_disposed) return;
    _eventsController.add(event);
  }

  /// Cancela listeners, limpa o mapa e desconecta/descarta o [Room] atual.
  /// Idempotente (chamado pelo próprio disconnect e pelo
  /// [RoomDisconnectedEvent]). AWAIT obrigatório: o [dispose] nativo é o que
  /// garante a liberação dos recursos WebRTC — retornar antes deixaria dois
  /// [Room]/PeerConnection vivos num reconnect rápido.
  Future<void> _cleanupRoom() async {
    _tokenGenerator = null;
    for (final cancel in _roomListeners) {
      cancel();
    }
    _roomListeners.clear();
    _participantsById.clear();
    final room = _room;
    _room = null;
    if (room != null) {
      try {
        await room.disconnect();
      } catch (error) {
        debugPrint('[rtc] disconnect falhou (ignorado): $error');
      }
      try {
        await room.dispose();
      } catch (error) {
        debugPrint('[rtc] dispose falhou (ignorado): $error');
      }
    }
    _emitSnapshot();
  }
}
