import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

// `SpeakingChangedEvent` e `ReconnectingEvent` (mixin, events.dart:71)
// existem TAMBÉM no livekit_client (colisão de nome com eventos do contrato);
// o projeto usa os do rtc_service.dart.
import 'package:livekit_client/livekit_client.dart'
    hide SpeakingChangedEvent, ReconnectingEvent;

import 'rtc_service.dart';

/// Implementação de [RtcService] sobre o LiveKit.
///
/// ÚNICO arquivo de LÓGICA do projeto autorizado a importar `livekit_client`
/// (invariante de arquitetura do 4fun_cod: a UI só enxerga [RtcService] e o
/// widget de renderização [RtcVideoView], em `rtc_video_view.dart`).
///
/// API validada na 2.11.0 (ver skill 4fun-cod-codebase):
/// - [RoomOptions] (incl. `defaultAudioCaptureOptions`/`defaultAudioPublishOptions`)
///   vai no CONSTRUTOR do [Room], não no `connect()`;
/// - eventos via `room.events.on<T>(...)` — a API antiga `room.on<RoomEvent>`
///   não existe mais;
/// - `TrackPublication.muted` é getter-only: mutar é via `publication.mute()`
///   (e desmutar via `unmute()`), que mantêm o estado `muted` em sincronia
///   com o servidor;
/// - `isMicrophoneEnabled()` é MÉTODO (não getter) no [Participant]; o mesmo
///   vale para `isCameraEnabled()` (participant.dart:309);
/// - `connectionState` colide com o enum `ConnectionState` do Flutter —
///   este serviço nunca lê esse enum, só reage a [RoomDisconnectedEvent];
/// - `RoomOptions`/`ConnectOptions` NÃO têm `tokenGenerator` na 2.11.0: a
///   função recebida em [connect] é apenas armazenada (ver [tokenGenerator])
///   para o controller obter tokens frescos e reconectar manualmente;
/// - `adaptiveStream`/`dynacast` são FALSE por default no client
///   (options.dart:298-299) — a Fase 5 os liga no [defaultRoomOptions];
///   dynacast requer simulcast (options.dart:264);
/// - NÃO existe `RemoteVideoTrackPublication` na 2.11.0: `setVideoQuality`
///   vive no [RemoteTrackPublication] genérico (publication/remote.dart:302);
/// - `LocalVideoTrack.switchCamera(deviceId)` é a API nativa de troca de
///   câmera (track/local/video.dart:299 — restartTrack interno);
/// - widget de renderização = `VideoTrackRenderer` (não existe `VideoView`);
/// - `isScreenShareEnabled()` é MÉTODO, espelho exato de `isCameraEnabled()`
///   (participant.dart:319-321);
/// - `setScreenShareEnabled(false)` DESPUBLICA a track de screenShareVideo
///   (e a screenShareAudio se existir) — diferente da câmera, que muta e
///   mantém a publicação (participant/local.dart:805-810);
/// - `ScreenShareCaptureOptions.sourceId` é o id do DesktopCapturerSource
///   (mapeado para `deviceId` do super — track/options.dart:156-159);
/// - o seletor de fonte `ScreenSelectDialog` é `@experimental` (2.11.0) —
///   isolado no wrapper `RtcScreenSharePicker` (screen_share_picker.dart).
class LiveKitRtcService implements RtcService {
  LiveKitRtcService({RoomOptions? roomOptions})
      : _roomOptions = roomOptions ?? defaultRoomOptions;

  /// Configuração de áudio da Fase 4 (default do serviço — a UI nunca
  /// configura isso): echo cancellation + noise suppression + AGC na
  /// captura e Opus em ABR com teto de 64 kbps na publicação (range do
  /// plano: 32–64k; o encoder WebRTC opera em ABR entre o piso e o teto).
  ///
  /// Pitfall 2.11.0: [AudioCaptureOptions] NÃO tem campo `enabled` — o
  /// "mic mutado por padrão" era feito no [connect] via `publication.mute()`;
  /// desde a Fase 7 o mic entra ATIVO (requisito "áudio por padrão").
  ///
  /// Vídeo (Fase 5/7):
  /// - `adaptiveStream`/`dynacast` ligados no CLIENT (defaults false —
  ///   options.dart:298-299); dynacast requer simulcast (options.dart:264);
  /// - `defaultCameraCaptureOptions` h1080_60 (Fase 7): a 1ª publicação de
  ///   câmera usa estes params (o SDK clampa às dimensões reais do device);
  ///   o modo `auto` do seletor equivale a estes defaults;
  /// - `videoSimulcastLayers` h180/h540/h1080_60: `simulcast` já é default
  ///   true, mas fica explícito; `videoEncoding` fica null de propósito —
  ///   o SDK sugere os encodings a partir dos layers (options.dart:461-469).
  static final RoomOptions defaultRoomOptions = RoomOptions(
    defaultAudioCaptureOptions: const AudioCaptureOptions(
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
    ),
    defaultAudioPublishOptions: const AudioPublishOptions(
      encoding: AudioEncoding(maxBitrate: 64000),
    ),
    adaptiveStream: true,
    dynacast: true,
    defaultCameraCaptureOptions: const CameraCaptureOptions(
      params: h1080_60,
    ),
    defaultVideoPublishOptions: const VideoPublishOptions(
      simulcast: true,
      videoSimulcastLayers: [
        VideoParametersPresets.h180_169,
        VideoParametersPresets.h540_169,
        h1080_60,
      ],
    ),
  );

  /// 1080p@60 CUSTOM — NENHUM preset do SDK tem 60fps (máx 30 em
  /// `video_parameters.dart`). Teto da Fase 7 (decisão: parar em 1080p60;
  /// o h1440_169 existente é 1440p@30/5Mbps e ficou fora de escopo).
  /// Bitrate ~6 Mbps (referência de encoders para 1080p60 H.264/VP8).
  static const VideoParameters h1080_60 = VideoParameters(
    dimensions: VideoDimensions(1920, 1080),
    encoding: VideoEncoding(maxBitrate: 6000000, maxFramerate: 60),
  );

  /// 480p 16:9 custom — o SDK só tem `h480_43` (4:3); o seletor usa 16:9.
  static const VideoParameters h480_169 = VideoParameters(
    dimensions: VideoDimensions(854, 480),
    encoding: VideoEncoding(maxBitrate: 800000, maxFramerate: 30),
  );

  /// 240p 16:9 custom — SDK não tem preset 240p 16:9.
  static const VideoParameters h240_169 = VideoParameters(
    dimensions: VideoDimensions(426, 240),
    encoding: VideoEncoding(maxBitrate: 200000, maxFramerate: 30),
  );

  /// 144p 16:9 custom — SDK não tem preset 144p 16:9.
  static const VideoParameters h144_169 = VideoParameters(
    dimensions: VideoDimensions(256, 144),
    encoding: VideoEncoding(maxBitrate: 100000, maxFramerate: 15),
  );

  /// Opções da sala (mic publicado ATIVO por padrão desde a Fase 7).
  final RoomOptions _roomOptions;

  Room? _room;
  RtcTokenGenerator? _tokenGenerator;
  /// URL da sala do último [connect] — preservada pelo loop de reconexão
  /// automática (zerada no [_cleanupRoom], junto com o [_tokenGenerator]).
  String? _livekitUrl;
  bool _disposed = false;

  /// Perfil de qualidade de PUBLICAÇÃO da câmera local (default: auto).
  /// Aplicado na 1ª [enableCamera] e reaplicado ao vivo por
  /// [setCameraQuality]. Resetado no [_cleanupRoom] (sessão nova = auto).
  RtcCameraQuality _cameraQuality = RtcCameraQuality.auto;

  /// Perfil da ÚLTIMA publicação de câmera BEM-SUCEDIDA. Comparado com
  /// [_cameraQuality] no [enableCamera] para detectar perfil pendente com
  /// publicação existente (desligou→trocou perfil→religou): se divergirem,
  /// republica em vez de só desmutar. Atualizado só APÓS publish/republish
  /// bem-sucedido (rollback natural em falha).
  RtcCameraQuality _appliedCameraQuality = RtcCameraQuality.auto;

  @override
  RtcCameraQuality get cameraQuality => _cameraQuality;

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
    _livekitUrl = url; // preservada para o loop de reconexão automática

    final room = Room(roomOptions: _roomOptions);
    _room = room;
    _wire(room);

    try {
      await room.connect(url, token);
    } catch (_) {
      await _cleanupRoom();
      rethrow; // o controller trata o erro (token inválido, servidor fora etc.)
    }

    // Publica o mic ATIVO por padrão (Fase 7 — requisito "áudio por
    // padrão"; a Fase 4 publicava mutado via publication.mute(), removido).
    // O AEC/NS/AGC do defaultRoomOptions mitigam eco/ruído; o usuário pode
    // mutar a qualquer momento pelo botão da barra de controles.
    final localParticipant = room.localParticipant;
    if (localParticipant == null) {
      // Impossível na prática pós-connect (o Room sempre tem o participante
      // local); sem ele não há mic a publicar.
      return;
    }
    try {
      await localParticipant.setMicrophoneEnabled(true);
    } catch (_) {
      // Falha ao publicar o mic: NUNCA deixa o Room órfão — limpa e propaga.
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

  @override
  Future<void> enableCamera() async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    final publication =
        localParticipant.getTrackPublicationBySource(TrackSource.camera);
    // Publicação existente COM o perfil já aplicado: apenas desmuta
    // (participant/local.dart:795-821). Se o perfil PENDENTE diverge do
    // aplicado (desligou→trocou perfil→religou), republica — senão o perfil
    // escolhido seria descartado silenciosamente (fix CRÍTICO do review).
    // Decisão extraída em [cameraNeedsRepublish] (função pura testável).
    if (!cameraNeedsRepublish(
      hasPublication: publication != null,
      pending: _cameraQuality,
      applied: _appliedCameraQuality,
    )) {
      // Erros de permissão/hardware (TrackCreateException, exceptions.dart:81)
      // PROPAGAM — o controller decide a mensagem; falha de câmera NUNCA
      // derruba a sessão (nada de _cleanupRoom aqui).
      await localParticipant.setCameraEnabled(true);
      return;
    }
    if (publication != null) {
      // Perfil pendente diferente do aplicado: despublica para republicar
      // com as novas options. DIFERENTE do setCameraQuality (que cria a
      // track antes de remover), aqui o usuário já está religando a câmera
      // — se o create falhar, a câmera simplesmente não liga (estado
      // visível e esperado, sem publicação órfã).
      await localParticipant.removePublishedTrack(publication.sid);
    }
    // 1ª publicação OU re-publicação com perfil novo: nasce no perfil
    // selecionado (Fase 7 — o `auto` equivale aos defaults do RoomOptions).
    final (captureOptions, publishOptions) = _optionsFor(_cameraQuality);
    final track = await LocalVideoTrack.createCameraTrack(captureOptions);
    await localParticipant
        .publishVideoTrack(track, publishOptions: publishOptions);
    // Só após o sucesso: o perfil aplicado agora é o corrente (rollback
    // natural se o create/publish falhar — _appliedCameraQuality intacto).
    _appliedCameraQuality = _cameraQuality;
  }

  @override
  Future<void> disableCamera() async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    // setCameraEnabled(false) → publication.mute(stopOnMute: true)
    // (participant/local.dart:797-814): a publicação PERMANECE publicada
    // (como o mic); o estado é reconciliado pelos eventos já ouvidos.
    await localParticipant.setCameraEnabled(false);
  }

  @override
  Future<void> setCameraQuality(RtcCameraQuality quality) async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    // Câmera OFF: perfil fica PENDENTE — a próxima enableCamera() aplica
    // (e o enableCamera detecta divergência com o aplicado). Grava já o
    // pendente; nada foi publicado ainda, então não há estado inconsistente.
    if (!localParticipant.isCameraEnabled()) {
      _cameraQuality = quality;
      return;
    }

    // Câmera LIGADA: troca ao vivo sem sair da sala. restartTrack recria a
    // captura no MESMO sender mas NÃO renegocia os publish options
    // (bitrate/simulcast layers ficam os do publish original — local.dart:289
    // + _publishVideoTrack usa lastPublishOptions/defaults). Para mudar o
    // teto de publicação é preciso despublicar + republicar com as novas
    // options (padrão real validado no commetchat/commet via MCP grep).
    //
    // Ordem defensiva: CRIA a track nova ANTES de remover a antiga — se o
    // create falhar (hardware não suporta o perfil), a publicação atual
    // permanece intacta e _cameraQuality NÃO muda (rollback natural; o
    // controller também não atualiza o estado em erro — sem divergência).
    // Se o PUBLISH falhar após o remove, o LocalTrackUnpublishedEvent já
    // reconcilia isCameraEnabled para false (câmera cai como "off", nunca
    // em estado zumbi) — fail-safe pelo padrão de eventos do serviço.
    final (captureOptions, publishOptions) = _optionsFor(quality);
    final track = await LocalVideoTrack.createCameraTrack(captureOptions);
    final publication =
        localParticipant.getTrackPublicationBySource(TrackSource.camera);
    if (publication != null) {
      await localParticipant.removePublishedTrack(publication.sid);
    }
    // Erros de captura/publish (TrackCreateException) PROPAGAM — o
    // controller decide a mensagem; falha NUNCA derruba a sessão.
    await localParticipant
        .publishVideoTrack(track, publishOptions: publishOptions);
    // Só após o sucesso: perfil pendente E aplicado passam a ser o novo
    // (em falha, _cameraQuality continua o antigo = estado do controller).
    _cameraQuality = quality;
    _appliedCameraQuality = quality;
  }

  @override
  Future<void> startScreenShare(String sourceId) async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    // No-op quando o share já está ativo (isScreenShareEnabled é MÉTODO na
    // 2.11.0 — participant.dart:319-321).
    if (localParticipant.isScreenShareEnabled()) return;
    // Publica a track de screenShareVideo (participant/local.dart:774-779).
    // A câmera NÃO é afetada — share e câmera coexistem. Erros de captura
    // (TrackCreateException — ex. permissão negada; mobile nem chega a rodar,
    // local.dart:789-791) PROPAGAM para o controller: falha de share NUNCA
    // derruba a sessão (nada de _cleanupRoom aqui).
    await localParticipant.setScreenShareEnabled(
      true,
      screenShareCaptureOptions: ScreenShareCaptureOptions(
        sourceId: sourceId,
        // Plano: máx 1080p30 — preset h1080FPS30 EXISTE na 2.11.0
        // (video_parameters.dart:298-304). captureScreenAudio fica FALSE:
        // browser-only (options.dart:143); V1 sem áudio de sistema (OUT).
        params: VideoParametersPresets.screenShareH1080FPS30,
      ),
    );
  }

  @override
  Future<void> stopScreenShare() async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    // DIFERENTE da câmera: setScreenShareEnabled(false) DESPUBLICA a track
    // (setSourceEnabled remove a publicação de screenShareVideo e a
    // screenShareAudio se existir — participant/local.dart:805-810). Não
    // chamar removePublishedTrack manualmente — o SDK faz. Com o share já
    // inativo é no-op natural do SDK.
    await localParticipant.setScreenShareEnabled(false);
  }

  @override
  RtcVideoTrackRef? screenTrackOf(String participantId) {
    // Espelho exato de [videoTrackOf] com TrackSource.screenShareVideo.
    final room = _room;
    if (room == null || _disposed) return null;
    final localParticipant = room.localParticipant;
    final TrackPublication? publication;
    if (localParticipant?.identity == participantId) {
      publication = localParticipant
          ?.getTrackPublicationBySource(TrackSource.screenShareVideo);
    } else {
      publication = room.remoteParticipants[participantId]
          ?.getTrackPublicationBySource(TrackSource.screenShareVideo);
    }
    if (publication == null || publication.muted) return null;
    final track = publication.track;
    // Defensivo: publicação de screen share é sempre vídeo, mas o cast
    // direto quebraria se algum dia mudar de source — `is VideoTrack` cobre.
    if (track is! VideoTrack) return null;
    return LiveKitVideoTrackRef(track);
  }

  @override
  Future<void> switchCamera(String deviceId) async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    final track = localParticipant
        .getTrackPublicationBySource(TrackSource.camera)
        ?.track as LocalVideoTrack?;
    if (track == null) {
      // Câmera OFF: sem track local para trocar — no-op. switchCamera só
      // tem efeito com a câmera ligada; a 1ª enableCamera() usa o device
      // default (ou o deviceId configurado em defaultCameraCaptureOptions).
      return;
    }
    // API nativa 2.11.0 (track/local/video.dart:299-315): restartTrack
    // interno — NUNCA despublicar/republicar para trocar de câmera.
    await track.switchCamera(deviceId);
  }

  @override
  Future<List<RtcVideoDevice>> listCameraDevices() async {
    // Hardware.instance.enumerateDevices(type: 'videoinput') → List<MediaDevice>
    // com deviceId/label/kind/groupId (hardware/hardware.dart:100-107) — a
    // mesma API usada pelo exemplo oficial do SDK.
    final devices =
        await Hardware.instance.enumerateDevices(type: 'videoinput');
    return [
      for (final device in devices)
        RtcVideoDevice(id: device.deviceId, label: device.label),
    ];
  }

  @override
  Future<void> setQuality(
    String participantId,
    RtcVideoQuality quality,
  ) async {
    final room = _room;
    if (room == null || _disposed) return;
    // Qualidade se aplica apenas à RECEPÇÃO remota: local/desconhecido → no-op.
    final remoteParticipant = room.remoteParticipants[participantId];
    if (remoteParticipant == null) return;
    final publication = remoteParticipant
        .getTrackPublicationBySource(TrackSource.camera);
    if (publication == null) return; // câmera remota OFF/ausente → no-op
    final videoQuality = switch (quality) {
      RtcVideoQuality.low => VideoQuality.LOW,
      RtcVideoQuality.medium => VideoQuality.MEDIUM,
      RtcVideoQuality.high => VideoQuality.HIGH,
    };
    // 2.11.0: NÃO existe RemoteVideoTrackPublication — setVideoQuality vive
    // no RemoteTrackPublication genérico (publication/remote.dart:302-307).
    // Com adaptiveStream ativo, o client faz MERGE da preferência manual
    // com a visibilidade dos views (o mais conservador vence).
    await publication.setVideoQuality(videoQuality);
  }

  @override
  RtcVideoTrackRef? videoTrackOf(String participantId) {
    final room = _room;
    if (room == null || _disposed) return null;
    final localParticipant = room.localParticipant;
    final TrackPublication? publication;
    if (localParticipant?.identity == participantId) {
      publication = localParticipant
          ?.getTrackPublicationBySource(TrackSource.camera);
    } else {
      publication = room.remoteParticipants[participantId]
          ?.getTrackPublicationBySource(TrackSource.camera);
    }
    if (publication == null || publication.muted) return null;
    final track = publication.track;
    // Defensivo: publicação de camera é sempre vídeo, mas o cast direto
    // quebraria se algum dia mudar de source — `is VideoTrack` cobre.
    if (track is! VideoTrack) return null;
    return LiveKitVideoTrackRef(track);
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

  /// Perfil de qualidade → opções de captura e publicação da câmera local.
  /// `auto` devolve EXATAMENTE os defaults do [defaultRoomOptions] (Fase 7:
  /// simulcast h180/h540/h1080_60 + dynacast). Perfis fixos escalonam 3
  /// camadas simulcast até o teto escolhido (LiveKit aceita máx 3) — o
  /// dynacast continua protegendo assinantes com banda ruim; abaixo de
  /// 480p o simulcast perde o valor e cai para 1 camada.
  (CameraCaptureOptions, VideoPublishOptions) _optionsFor(
    RtcCameraQuality quality,
  ) =>
      cameraQualityOptions(quality);

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
      // Sala caiu: motivo não iniciado pelo app (servidor encerrou/rede) →
      // reconexão automática reason-gated (até 3 tentativas com token
      // fresco); clientInitiated/duplicateIdentity mantêm o comportamento
      // antigo (DisconnectedEvent imediato + cleanup). O clientInitiated do
      // nosso próprio disconnect() já não chega aqui (_teardownRoom cancela
      // os listeners ANTES do room.disconnect()) — o gate é a defesa dupla.
      room.events.on<RoomDisconnectedEvent>((e) {
        final reason = e.reason;
        final shouldReconnect =
            reason != DisconnectReason.clientInitiated &&
            reason != DisconnectReason.duplicateIdentity &&
            _tokenGenerator != null &&
            !_disposed;
        if (shouldReconnect) {
          unawaited(_reconnectWithRetries());
        } else {
          _emitEvent(DisconnectedEvent());
          unawaited(_cleanupRoom());
        }
      }),
    ]);
  }

  /// Re-deriva o [RtcParticipant] de um [Participant] do LiveKit e emite
  /// [MicEnabledChangedEvent]/[CameraEnabledChangedEvent]/
  /// [ScreenShareEnabledChangedEvent] se o estado mudou. O participante
  /// entra no mapa mesmo se ainda não tinha evento joined (robustez).
  ///
  /// Os eventos já ouvidos em [_wire] (TrackPublished/Unpublished, local e
  /// remoto, TrackMuted/Unmuted) cobrem câmera, mic E screen share — basta
  /// re-derivar os flags aqui; NÃO é preciso listener novo.
  void _syncParticipant(Participant participant) {
    final id = participant.identity;
    final previous = _participantsById[id];
    final updated = RtcParticipant(
      id: id,
      name: participant.name.isEmpty ? id : participant.name,
      isMicrophoneEnabled: participant.isMicrophoneEnabled(),
      isCameraEnabled: participant.isCameraEnabled(),
      isScreenSharing: participant.isScreenShareEnabled(),
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
    if (previous != null &&
        previous.isCameraEnabled != updated.isCameraEnabled) {
      _emitEvent(
        CameraEnabledChangedEvent(
          participantId: id,
          isCameraEnabled: updated.isCameraEnabled,
        ),
      );
    }
    if (previous != null &&
        previous.isScreenSharing != updated.isScreenSharing) {
      _emitEvent(
        ScreenShareEnabledChangedEvent(
          participantId: id,
          isScreenSharing: updated.isScreenSharing,
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

  /// Reconexão automática pós-queda da sala (motivo não iniciado pelo app):
  /// até 3 tentativas (1s/2s/4s) com token fresco, preservando a sessão —
  /// [_tokenGenerator]/[_livekitUrl] ficam intactos (só o [_teardownRoom]
  /// descarta o [Room] morto). Sucesso → participantes limpos + mic MUTADO
  /// (padrão do connect) + [ReconnectedEvent]; esgotado → [DisconnectedEvent]
  /// (o controller volta para idle). NUNCA emite [DisconnectedEvent] durante
  /// o processo.
  Future<void> _reconnectWithRetries() async {
    final tokenGenerator = _tokenGenerator;
    final url = _livekitUrl;
    if (tokenGenerator == null || url == null) {
      // Sem sessão preservada (usuário saiu/desconectou antes do handler
      // rodar, ou o connect nunca passou token generator): cai direto.
      _emitEvent(DisconnectedEvent());
      await _cleanupRoom();
      return;
    }

    // ANTES do teardown: a UI liga o banner antes de ver a sala esvaziar.
    _emitEvent(const ReconnectingEvent());
    await _teardownRoom();

    const delays = [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ];
    for (final delay in delays) {
      await Future<void>.delayed(delay);
      // O usuário saiu/desconectou no meio (o _cleanupRoom já zerou o token
      // generator): aborta SILENCIOSAMENTE — NÃO emitir nada.
      if (_disposed || _tokenGenerator == null) return;

      // Token FRESCO: o token do connect inicial tem validade curta (10m).
      String token;
      try {
        token = await tokenGenerator();
      } catch (error) {
        debugPrint('[rtc] falha ao obter token de reconexão: $error');
        break;
      }

      final room = Room(roomOptions: _roomOptions);
      _room = room;
      _wire(room);
      try {
        await room.connect(url, token);
      } catch (error) {
        debugPrint('[rtc] tentativa de reconexão falhou: $error');
        await _teardownRoom();
        continue;
      }

      final localParticipant = room.localParticipant;
      if (localParticipant == null) {
        // Impossível na prática pós-connect (o Room sempre tem o participante
        // local); sem ele não há mic a republicar.
        await _teardownRoom();
        continue;
      }
      try {
        // Mesmo padrão do connect (Fase 7): mic publicado ATIVO (requisito
        // "áudio por padrão"; a Fase 4 republicava mutado). Câmera/share
        // locais recomeçam DESLIGADOS (risco V1 documentado no contrato do
        // ReconnectedEvent).
        await localParticipant.setMicrophoneEnabled(true);
      } catch (error) {
        debugPrint('[rtc] falha ao republicar o mic na reconexão: $error');
        await _teardownRoom();
        continue;
      }

      // Participantes ANTIGOS saem do snapshot; o local re-entra sozinho.
      _participantsById.clear();
      _syncParticipant(localParticipant);
      _emitSnapshot();
      _emitEvent(const ReconnectedEvent());
      return;
    }

    // Esgotou as 3 tentativas: volta o comportamento de queda (idle).
    _emitEvent(const DisconnectedEvent());
    await _cleanupRoom();
  }

  /// Encerramento definitivo da sessão: zera o token generator e a URL (a
  /// reconexão automática não pode mais acontecer), volta o perfil de
  /// câmera para `auto` (sessão nova = padrão) e descarta o [Room].
  /// Idempotente (chamado pelo próprio disconnect e pelo
  /// [RoomDisconnectedEvent] sem reconexão).
  Future<void> _cleanupRoom() async {
    _tokenGenerator = null;
    _livekitUrl = null;
    _cameraQuality = RtcCameraQuality.auto;
    _appliedCameraQuality = RtcCameraQuality.auto;
    await _teardownRoom();
  }

  /// Descarta o [Room] atual SEM mexer em [_tokenGenerator]/[_livekitUrl] —
  /// o loop de reconexão usa este teardown para não perder a sessão. AWAIT
  /// obrigatório: o [dispose] nativo é o que garante a liberação dos
  /// recursos WebRTC — retornar antes deixaria dois [Room]/PeerConnection
  /// vivos num reconnect rápido.
  Future<void> _teardownRoom() async {
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

/// Decisão PURA (testável isoladamente) de quando [LiveKitRtcService.enableCamera]
/// deve REPUBLICAR a track de câmera em vez de apenas desmutar a publicação
/// existente:
/// - sem publicação → precisa republicar (1ª ligada);
/// - publicação existe e perfil pendente == perfil aplicado → só unmute;
/// - publicação existe e perfil pendente != aplicado → precisa republicar
///   (usuário trocou o perfil com a câmera DESLIGADA — fix CRÍTICO do review
///   de SPEC Fase 7; sem esta regra o perfil escolhido era descartado).
bool cameraNeedsRepublish({
  required bool hasPublication,
  required RtcCameraQuality pending,
  required RtcCameraQuality applied,
}) =>
    !hasPublication || pending != applied;

/// Função PURA (testável isoladamente) que mapeia um perfil de qualidade
/// de publicação para as opções de captura/publicação da câmera local.
///
/// `auto` e `q1080` compartilham o teto 1080p60 com simulcast h180/h540/
/// h1080_60 (diferença conceitual: `auto` deixa o dynacast decidir por
/// banda; `q1080` é a escolha explícita do mesmo teto — opções idênticas
/// por design). Perfis abaixo de 480p caem para 1 camada (simulcast perde
/// o valor em resoluções pequenas).
///
/// As constantes de vídeo ([LiveKitRtcService.h1080_60] etc.) são públicas
/// da classe para os testes conferirem os valores esperados.
(CameraCaptureOptions, VideoPublishOptions) cameraQualityOptions(
  RtcCameraQuality quality,
) {
  switch (quality) {
    case RtcCameraQuality.auto:
    case RtcCameraQuality.q1080:
      return (
        const CameraCaptureOptions(params: LiveKitRtcService.h1080_60),
        const VideoPublishOptions(
          simulcast: true,
          videoSimulcastLayers: [
            VideoParametersPresets.h180_169,
            VideoParametersPresets.h540_169,
            LiveKitRtcService.h1080_60,
          ],
        ),
      );
    case RtcCameraQuality.q720:
      return (
        const CameraCaptureOptions(
          params: VideoParametersPresets.h720_169,
        ),
        const VideoPublishOptions(
          simulcast: true,
          videoSimulcastLayers: [
            VideoParametersPresets.h180_169,
            VideoParametersPresets.h360_169,
            VideoParametersPresets.h720_169,
          ],
        ),
      );
    case RtcCameraQuality.q480:
      // Camadas 16:9 escalonadas até 480p (h120/h240 16:9 não existem no
      // SDK — h180/h360/h480 preservam o padrão do projeto).
      return (
        const CameraCaptureOptions(params: LiveKitRtcService.h480_169),
        const VideoPublishOptions(
          simulcast: true,
          videoSimulcastLayers: [
            VideoParametersPresets.h180_169,
            VideoParametersPresets.h360_169,
            LiveKitRtcService.h480_169,
          ],
        ),
      );
    case RtcCameraQuality.q360:
      return (
        const CameraCaptureOptions(
          params: VideoParametersPresets.h360_169,
        ),
        VideoPublishOptions(
          simulcast: false,
          videoEncoding: VideoParametersPresets.h360_169.encoding,
        ),
      );
    case RtcCameraQuality.q240:
      return (
        const CameraCaptureOptions(params: LiveKitRtcService.h240_169),
        VideoPublishOptions(
          simulcast: false,
          videoEncoding: LiveKitRtcService.h240_169.encoding,
        ),
      );
    case RtcCameraQuality.q144:
      return (
        const CameraCaptureOptions(params: LiveKitRtcService.h144_169),
        VideoPublishOptions(
          simulcast: false,
          videoEncoding: LiveKitRtcService.h144_169.encoding,
        ),
      );
  }
}

/// Ref opaco concreto de track de vídeo (Fase 5).
///
/// Só o [LiveKitRtcService] cria (em [LiveKitRtcService.videoTrackOf]) e só
/// o `RtcVideoView` (core/rtc/rtc_video_view.dart) consome — a UI em
/// features/ nunca vê o tipo LiveKit.
class LiveKitVideoTrackRef extends RtcVideoTrackRef {
  const LiveKitVideoTrackRef(this.track);

  /// Track de vídeo resolvida (LocalVideoTrack ou RemoteVideoTrack — ambas
  /// usam o mixin [VideoTrack]; o renderer gerencia o ciclo de vida).
  final VideoTrack track;
}
