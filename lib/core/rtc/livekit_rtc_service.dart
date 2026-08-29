import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

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
/// - `ScreenShareCaptureOptions.sourceId` é opcional; sem sourceId, o SDK
///   delega a seleção de janela/display ao portal nativo do SO via
///   `navigator.mediaDevices.getDisplayMedia`;
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
  /// - câmera sem opções customizadas: captura e publicação seguem os
  ///   defaults do SDK/dispositivo;
  /// - screen share usa um teto de captura 1080p60 e publica inicialmente no
  ///   perfil Auto (1080p15), com simulcast calculado pelo SDK.
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
    defaultVideoPublishOptions: const VideoPublishOptions(
      simulcast: true,
      screenShareEncoding: VideoEncoding(maxBitrate: 2500000, maxFramerate: 15),
    ),
  );

  /// Teto de captura do screen share. A fonte nasce em 1080p60 para que o
  /// sender possa subir de 15/30 para 60 FPS sem recriar a track ou reabrir
  /// o picker.
  static const VideoParameters screenShareH1080FPS60 = VideoParameters(
    dimensions: VideoDimensions(1920, 1080),
    encoding: VideoEncoding(maxBitrate: 8000000, maxFramerate: 60),
  );

  /// Opções da sala (mic publicado ATIVO por padrão desde a Fase 7).
  final RoomOptions _roomOptions;

  Room? _room;
  RtcTokenGenerator? _tokenGenerator;

  /// URL da sala do último [connect] — preservada pelo loop de reconexão
  /// automática (zerada no [_cleanupRoom], junto com o [_tokenGenerator]).
  String? _livekitUrl;
  bool _disposed = false;

  /// Perfil escolhido para o screen share. Fica pendente entre shares e é
  /// resetado no [_cleanupRoom] (sessão nova = auto).
  RtcScreenShareQuality _screenShareQuality = RtcScreenShareQuality.auto;

  /// Cópia dos encodings originais do sender do screen share, capturados logo
  /// após a publicação em Auto. A cópia evita que uma alteração posterior
  /// mutile o baseline usado para calcular as demais qualidades.
  List<rtc.RTCRtpEncoding>? _screenShareEncodingBaseline;

  /// Época da publicação de áudio de sistema: incrementado a cada
  /// [_teardownRoom] para INVALIDAR publicações pendentes de salas antigas
  /// (uma captura travada na sala A não pode travar o share da sala B — nem
  /// o `finally` da operação antiga liberar a fila de uma operação nova).
  int _systemAudioPublishEpoch = 0;

  /// Publicação de áudio de sistema EM ANDAMENTO (serialização de chamadas
  /// concorrentes na MESMA sala). Null quando ocioso — ver [_publishSystemAudio].
  Future<void>? _pendingSystemAudioPublish;

  @override
  RtcScreenShareQuality get screenShareQuality => _screenShareQuality;

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
    // Seed do snapshot: local + participantes REMOTOS já presentes (o SDK
    // 2.11 NÃO emite eventos para eles no join response — ver
    // [_seedParticipants]). Sem isso a UI mostraria a sala vazia até alguém
    // publicar track/mutar.
    _seedParticipants(room);
  }

  @override
  Future<void> disconnect() => _cleanupRoom();

  @override
  Future<void> resumeAudio() async {
    final room = _room;
    if (room == null || _disposed) return;
    // startAudio nunca lança (try/catch interno — room.dart:1293-1305):
    // no web retoma os `<audio>` da sala dentro do gesto do usuário que
    // chamou este método; no desktop é no-op (startAllAudioElement → true).
    // O resultado real chega via AudioPlaybackStatusChanged (que emite
    // AudioPlaybackResumedEvent/AudioPlaybackBlockedEvent no _wire).
    await room.startAudio();
  }

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
    // A câmera segue integralmente os defaults de captura/publicação do SDK e
    // do dispositivo. O controle de qualidade pertence apenas ao screen
    // share e nunca recria nem republica esta track.
    await localParticipant.setCameraEnabled(true);
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
  Future<void> setScreenShareQuality(RtcScreenShareQuality quality) async {
    final room = _room;
    if (room == null || _disposed) return;
    if (quality == _screenShareQuality) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    final publication = localParticipant.getTrackPublicationBySource(
      TrackSource.screenShareVideo,
    );
    if (publication == null || publication.track is! LocalVideoTrack) {
      // Sem share ativo, a escolha fica pendente para o próximo início.
      _screenShareQuality = quality;
      return;
    }

    final track = publication.track as LocalVideoTrack;
    final sender = track.sender;
    if (sender == null) {
      throw StateError('Sender do screen share indisponível.');
    }
    final baseline =
        _screenShareEncodingBaseline ??
        _cloneScreenShareEncodings(sender.parameters.encodings ?? const []);
    if (baseline.isEmpty) {
      throw StateError('Screen share sem encodings configurados.');
    }
    _screenShareEncodingBaseline ??= baseline;
    final previousQuality = _screenShareQuality;

    try {
      await _applyScreenShareQuality(sender, baseline, quality);
      _screenShareQuality = quality;
    } catch (_) {
      if (quality == RtcScreenShareQuality.auto) rethrow;
      try {
        await _applyScreenShareQuality(
          sender,
          baseline,
          RtcScreenShareQuality.auto,
        );
        _screenShareQuality = RtcScreenShareQuality.auto;
      } catch (_) {
        // Se o fallback também for recusado, tente restaurar o último perfil
        // confirmado sem trocar track, sender ou estado do compartilhamento.
        try {
          await _applyScreenShareQuality(sender, baseline, previousQuality);
        } catch (_) {
          // O sender continua sob controle do SDK; a transmissão permanece
          // ativa e o getter conserva o último perfil confirmado.
        }
        rethrow;
      }
    }
  }

  @override
  Future<void> startScreenShare(
    String? sourceId, {
    bool includeSystemAudio = false,
  }) async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    // No-op quando o share já está ativo (isScreenShareEnabled é MÉTODO na
    // 2.11.0 — participant.dart:319-321).
    if (localParticipant.isScreenShareEnabled()) return;
    // Publica a track de screenShareVideo (participant/local.dart:791-877).
    // A câmera NÃO é afetada — share e câmera coexistem. Erros de captura
    // (TrackCreateException — ex. permissão negada; mobile nem chega a rodar,
    // local.dart:789-791) PROPAGAM para o controller: falha de share NUNCA
    // derruba a sessão (nada de _cleanupRoom aqui).
    await localParticipant.setScreenShareEnabled(
      true,
      // flutter_webrtc 1.6.0 já tem loopback nativo no Linux via libpulse
      // para getDisplayMedia({audio:true}). Esse caminho captura o monitor do
      // sink padrão (PipeWire/PulseAudio), ou seja, qualquer áudio tocando no
      // computador, sem depender de enumerateDevices expor ".monitor".
      captureScreenAudio: includeSystemAudio,
      // A fonte é capturada uma vez em 1080p60; o perfil do sender começa em
      // Auto (15 FPS) e pode subir para 60 ao vivo. O helper também explicita
      // maxFrameRate, campo lido pelo capturador desktop do Linux.
      screenShareCaptureOptions: screenShareCaptureOptionsFor(sourceId),
    );
    final publication = localParticipant.getTrackPublicationBySource(
      TrackSource.screenShareVideo,
    );
    if (publication?.track case final LocalVideoTrack track) {
      final sender = track.sender;
      if (sender != null) {
        final baseline = _cloneScreenShareEncodings(
          sender.parameters.encodings ?? const [],
        );
        _screenShareEncodingBaseline = baseline;
        if (baseline.isEmpty) {
          _screenShareQuality = RtcScreenShareQuality.auto;
        }
        if (_screenShareQuality != RtcScreenShareQuality.auto &&
            baseline.isNotEmpty) {
          try {
            await _applyScreenShareQuality(
              sender,
              baseline,
              _screenShareQuality,
            );
          } catch (_) {
            try {
              await _applyScreenShareQuality(
                sender,
                baseline,
                RtcScreenShareQuality.auto,
              );
            } catch (_) {
              // O share já está publicado no baseline Auto. A falha de
              // ambos os ajustes não pode encerrar nem reiniciar a captura.
            }
            _screenShareQuality = RtcScreenShareQuality.auto;
          }
        }
      }
    }
    // Áudio de sistema (opcional): SEMPRE depois do vídeo — falha de áudio
    // NUNCA bloqueia o share (SystemAudioPublishException cai no controller,
    // que decide a mensagem; a sessão fica intacta).
    if (includeSystemAudio &&
        localParticipant.getTrackPublicationBySource(
              TrackSource.screenShareAudio,
            ) ==
            null) {
      await _publishSystemAudio();
    }
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
    _screenShareEncodingBaseline = null;
  }

  /// Publica o ÁUDIO DE SISTEMA (track de screenShareAudio) capturando o
  /// device monitor/loopback do SO. Chamado por [startScreenShare] quando
  /// [includeSystemAudio] é true.
  ///
  /// Rota desktop: tentamos primeiro o caminho nativo do SDK via
  /// `captureScreenAudio`; se ele não publicar `screenShareAudio`, este método
  /// monta MANUALMENTE a track a partir de um device monitor/loopback.
  ///
  /// QUALQUER falha pós-publicação do vídeo vira [SystemAudioPublishException]
  /// (inclusive erros genéricos de captura/publish) — o controller distingue
  /// "share ativo sem áudio" de "share falhou"; nunca deixa a UI divergir do
  /// share real.
  Future<void> _publishSystemAudio() async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    // No-op quando a track JÁ está publicada — check POR SALA (cobre
    // chamadas concorrentes que chegam depois da 1ª publicar; não há estado
    // global que vaze entre salas — o _teardownRoom invalida a fila).
    if (localParticipant.getTrackPublicationBySource(
          TrackSource.screenShareAudio,
        ) !=
        null) {
      return;
    }
    // Serializa chamadas concorrentes NA MESMA sala: a 2ª aguarda a 1ª
    // terminar — ela publicou (no-op natural do check acima) OU lançou
    // SystemAudioPublishException (o await re-propaga para a 2ª também).
    final pending = _pendingSystemAudioPublish;
    if (pending != null) {
      await pending;
      return;
    }
    final epoch = _systemAudioPublishEpoch;
    final operation = _publishSystemAudioInner(localParticipant);
    _pendingSystemAudioPublish = operation;
    try {
      await operation;
    } on SystemAudioPublishException {
      rethrow;
    } catch (error) {
      // Falha GENÉRICA (createStream, getAudioTracks, addTrack/negotiate...):
      // o vídeo já saiu — converte para a exceção tipada para o controller
      // não tratá-la como "share falhou" (UI divergente do share real).
      throw SystemAudioPublishException(
        'Não foi possível publicar o áudio de sistema ($error).',
      );
    } finally {
      // Só libera a fila se a sala NÃO mudou no meio (senão o finally da
      // operação antiga liberaria a fila de uma operação nova).
      if (epoch == _systemAudioPublishEpoch) {
        _pendingSystemAudioPublish = null;
      }
    }
  }

  Future<void> _publishSystemAudioInner(
    LocalParticipant localParticipant,
  ) async {
    // 1. Enumera os devices de áudio (Hardware.instance é API pública
    //    exportada — hardware.dart) e acha o monitor/loopback por heurística
    //    de label (função pura testável).
    final List<MediaDevice> devices;
    try {
      devices = await Hardware.instance.audioInputs();
    } catch (_) {
      throw const SystemAudioPublishException(
        'Não foi possível listar os dispositivos de áudio.',
      );
    }
    final monitorId = findSystemAudioMonitorDevice(devices);
    if (monitorId == null) {
      throw const SystemAudioPublishException(
        'Nenhum dispositivo de áudio de sistema encontrado '
        '(monitor/loopback).',
      );
    }
    // 2. Captura do monitor com processamento de áudio DESLIGADO — AGC/NS/EC
    //    corrompem música/SFX (options.dart:335-351 — "attempt if supported").
    //    Construtor + createStream são @internal na 2.11.0 (track/local/
    //    audio.dart:162, local.dart:245): aceitos como dependência conhecida,
    //    documentada — o próprio SDK usa o padrão para o browser.
    final captureOptions = AudioCaptureOptions(
      deviceId: monitorId,
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
    );
    // ignore: invalid_use_of_internal_member
    final stream = await LocalTrack.createStream(captureOptions);
    // ignore: invalid_use_of_internal_member
    final track = LocalAudioTrack(
      TrackSource.screenShareAudio,
      stream,
      stream.getAudioTracks().first,
      captureOptions,
    );
    // 3. Publica como screenShareAudio (o source vem da track). Options:
    //    - name 'system-audio' (default seria 'microphone' — local.dart:183);
    //    - 128 kbps = presetMusicHighQualityStereo (audio_encoding.dart:64-69);
    //    - dtx:false (DTX faz gating em música — options.dart:510-513);
    //    - red:false HABILITA RED (bug do SDK: disableRed SEM negação —
    //      local.dart:189 — red:true desligaria).
    // Erros de captura/publish PROPAGAM — a track de vídeo já saiu (o SDK
    // faz track.stop() em falha de publish: shouldStopOnFailure lido antes
    // do start — local.dart:177-179).
    await localParticipant.publishAudioTrack(
      track,
      publishOptions: AudioPublishOptions(
        name: 'system-audio',
        encoding: AudioEncoding(maxBitrate: 128000),
        dtx: false,
        red: false,
      ),
    );
  }

  @override
  RtcVideoTrackRef? screenTrackOf(String participantId) {
    // Espelho exato de [videoTrackOf] com TrackSource.screenShareVideo.
    final room = _room;
    if (room == null || _disposed) return null;
    final localParticipant = room.localParticipant;
    final TrackPublication? publication;
    if (localParticipant?.identity == participantId) {
      publication = localParticipant?.getTrackPublicationBySource(
        TrackSource.screenShareVideo,
      );
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
    final track =
        localParticipant.getTrackPublicationBySource(TrackSource.camera)?.track
            as LocalVideoTrack?;
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
    final devices = await Hardware.instance.enumerateDevices(
      type: 'videoinput',
    );
    return [
      for (final device in devices)
        RtcVideoDevice(id: device.deviceId, label: device.label),
    ];
  }

  @override
  Future<void> setQuality(String participantId, RtcVideoQuality quality) async {
    final room = _room;
    if (room == null || _disposed) return;
    // Qualidade se aplica apenas à RECEPÇÃO remota: local/desconhecido → no-op.
    final remoteParticipant = room.remoteParticipants[participantId];
    if (remoteParticipant == null) return;
    final publication = remoteParticipant.getTrackPublicationBySource(
      TrackSource.camera,
    );
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
      publication = localParticipant?.getTrackPublicationBySource(
        TrackSource.camera,
      );
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

  Future<void> _applyScreenShareQuality(
    rtc.RTCRtpSender sender,
    List<rtc.RTCRtpEncoding> baseline,
    RtcScreenShareQuality quality,
  ) async {
    final parameters = sender.parameters;
    parameters.encodings = screenShareQualityEncodings(
      baseline: baseline,
      quality: quality,
    );
    final applied = await sender.setParameters(parameters);
    if (!applied) {
      throw StateError('Sender recusou os parâmetros do screen share.');
    }
  }

  void _wire(Room room) {
    _roomListeners.addAll([
      room.events.on<ParticipantConnectedEvent>((e) {
        final isLocal =
            e.participant.identity == room.localParticipant?.identity;
        _syncParticipant(e.participant);
        // Participantes REMOTOS emitem joined (o local entra no snapshot sem
        // evento — quem chamou o connect já sabe que entrou).
        if (!isLocal) {
          _emitEvent(
            ParticipantJoinedEvent(
              participant: _participantsById[e.participant.identity]!,
            ),
          );
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
      // Playback de áudio remoto (web: autoplay policy do browser — o vídeo
      // renderiza, mas o `<audio>` remoto pode ser bloqueado até um gesto do
      // usuário; desktop/nativo não emite). O SDK já faz a ponte per-track →
      // evento público de room: `RemoteParticipant.addSubscribedMediaTrack`
      // encaminha o `AudioPlaybackFailed` da track para `room.engine.events`
      // (participant/remote.dart:223-232) e o Room chama
      // `_handleAudioPlaybackFailed` (room.dart:671-673) → emite
      // `AudioPlaybackStatusChanged`. Como `_audioEnabled` começa true
      // (room.dart:107), a PRIMEIRA falha passa o guard e emite — não há
      // bloqueio silencioso. O `isPlaying: true` sai de um `startAudio`
      // bem-sucedido (retomada dentro do gesto do usuário).
      room.events.on<AudioPlaybackStatusChanged>((e) {
        _emitEvent(
          e.isPlaying
              ? const AudioPlaybackResumedEvent()
              : const AudioPlaybackBlockedEvent(),
        );
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

  /// Seed do snapshot pós-connect: sincroniza o local e TODOS os
  /// participantes REMOTOS já presentes na sala.
  ///
  /// Necessário porque o livekit_client 2.11 NÃO emite eventos para os
  /// participantes do join response: `Room.connect` usa
  /// `_getOrCreateRemoteParticipant` diretamente e DESCARTA o resultado
  /// (core/room.dart:548-552) — `ParticipantConnectedEvent`/
  /// `TrackPublishedEvent` só saem em updates AO VIVO (_onParticipantUpdateEvent,
  /// room.dart:779-833). Sem este seed, quem entra numa sala ocupada vê o
  /// painel vazio até alguém publicar track nova/mutar.
  ///
  /// NÃO emite `ParticipantJoinedEvent` sintético para os remotos (eles já
  /// estavam lá — quem chamou o connect só precisa do snapshot); o loop é
  /// síncrono (sem await), então nenhum evento ao vivo intercala no meio; e
  /// `_syncParticipant` é idempotente por identity (Map), seguro mesmo se um
  /// evento chegar logo depois com estado mais novo.
  void _seedParticipants(Room room) {
    final localParticipant = room.localParticipant;
    if (localParticipant != null) _syncParticipant(localParticipant);
    for (final remote in room.remoteParticipants.values) {
      _syncParticipant(remote);
    }
    _emitSnapshot();
  }

  /// Re-deriva o [RtcParticipant] de um [Participant] do LiveKit e emite
  /// [MicEnabledChangedEvent]/[CameraEnabledChangedEvent]/
  /// [ScreenShareEnabledChangedEvent]/[SystemAudioEnabledChangedEvent] se o
  /// estado mudou. O participante entra no mapa mesmo se ainda não tinha
  /// evento joined (robustez).
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
      // Espelho do screen share: o SDK JÁ expõe o estado da track de
      // screenShareAudio (participant.dart:325-327 — éScreenShareAudioEnabled).
      isSystemAudioEnabled: participant.isScreenShareAudioEnabled(),
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
    if (previous != null &&
        previous.isSystemAudioEnabled != updated.isSystemAudioEnabled) {
      _emitEvent(
        SystemAudioEnabledChangedEvent(
          participantId: id,
          isSystemAudioEnabled: updated.isSystemAudioEnabled,
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
        _participantsById[entry.key] = entry.value.copyWith(
          isSpeaking: nowSpeaking,
        );
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
    _participantsController.add(
      _participantsById.values.toList(growable: false),
    );
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

      // Participantes ANTIGOS saem do snapshot; o local re-entra junto com
      // os REMOTOS já presentes na sala nova (mesmo furo do connect: o SDK
      // não emite eventos para participantes do join response — ver
      // [_seedParticipants]).
      _participantsById.clear();
      _seedParticipants(room);
      // Sem startAudio explícito aqui (decisão): o Room novo nasce com
      // `_audioEnabled = true` (room.dart:107) e, se o autoplay do browser
      // ainda bloquear o áudio remoto, a ponte track→room do SDK reemite
      // AudioPlaybackStatusChanged(false) — o banner reaparece sozinho e o
      // gesto do usuário (toque) chama resumeAudio. Forçar startAudio sem
      // gesto não desbloquearia o autoplay de qualquer forma.
      _emitEvent(const ReconnectedEvent());
      return;
    }

    // Esgotou as 3 tentativas: volta o comportamento de queda (idle).
    _emitEvent(const DisconnectedEvent());
    await _cleanupRoom();
  }

  /// Encerramento definitivo da sessão: zera o token generator e a URL (a
  /// reconexão automática não pode mais acontecer), volta o perfil de
  /// screen share para `auto` (sessão nova = padrão) e descarta o [Room].
  /// Idempotente (chamado pelo próprio disconnect e pelo
  /// [RoomDisconnectedEvent] sem reconexão).
  Future<void> _cleanupRoom() async {
    _tokenGenerator = null;
    _livekitUrl = null;
    _screenShareQuality = RtcScreenShareQuality.auto;
    _screenShareEncodingBaseline = null;
    await _teardownRoom();
  }

  /// Descarta o [Room] atual SEM mexer em [_tokenGenerator]/[_livekitUrl] —
  /// o loop de reconexão usa este teardown para não perder a sessão. AWAIT
  /// obrigatório: o [dispose] nativo é o que garante a liberação dos
  /// recursos WebRTC — retornar antes deixaria dois [Room]/PeerConnection
  /// vivos num reconnect rápido.
  Future<void> _teardownRoom() async {
    // Invalida publicações de áudio de sistema pendentes DESTA sala: a sala
    // nova (reconexão/join) não pode herdar no-op silencioso nem ver a fila
    // da sala antiga (review codex — fix por época, não flag global).
    _systemAudioPublishEpoch++;
    _pendingSystemAudioPublish = null;
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

/// Acha o device de "monitor"/loopback (áudio de sistema) na lista de
/// devices de áudio do SO — função PURA (testável isoladamente).
///
/// Heurística de label (case-insensitive): contém 'monitor' (PipeWire
/// `alsa_output.*.monitor`, PulseAudio "Monitor of …"), 'loopback'
/// (PipeWire `pw-loopback` → "[Loopback]"), 'cable' (VB-Cable "CABLE
/// Output"), 'stereo mix' (Realtek) ou 'what u hear' (Creative) — estes
/// dois últimos são devices de captura de sistema comuns no Windows.
/// Retorna o PRIMEIRO match (ordem do enumerate — suficiente na V1, sem
/// picker) ou null quando não há nenhum.
String? findSystemAudioMonitorDevice(Iterable<MediaDevice> devices) {
  for (final device in devices) {
    final label = device.label.toLowerCase();
    if (label.contains('monitor') ||
        label.contains('loopback') ||
        label.contains('cable') ||
        label.contains('stereo mix') ||
        label.contains('what u hear')) {
      return device.deviceId;
    }
  }
  return null;
}

/// Teto de publicação de um perfil de screen share.
class ScreenShareQualityProfile {
  const ScreenShareQualityProfile({
    required this.scaleResolutionDownBy,
    required this.maxFramerate,
    required this.maxBitrate,
  });

  final double scaleResolutionDownBy;
  final int maxFramerate;
  final int maxBitrate;
}

/// Mapeamento exato dos perfis públicos para os limites enviados ao WebRTC.
ScreenShareQualityProfile screenShareQualityProfile(
  RtcScreenShareQuality quality,
) => switch (quality) {
  RtcScreenShareQuality.auto => const ScreenShareQualityProfile(
    scaleResolutionDownBy: 1,
    maxFramerate: 15,
    maxBitrate: 2500000,
  ),
  RtcScreenShareQuality.q1080p60 => const ScreenShareQualityProfile(
    scaleResolutionDownBy: 1,
    maxFramerate: 60,
    maxBitrate: 8000000,
  ),
  RtcScreenShareQuality.q1080p30 => const ScreenShareQualityProfile(
    scaleResolutionDownBy: 1,
    maxFramerate: 30,
    maxBitrate: 5000000,
  ),
  RtcScreenShareQuality.q1080p15 => const ScreenShareQualityProfile(
    scaleResolutionDownBy: 1,
    maxFramerate: 15,
    maxBitrate: 2500000,
  ),
  RtcScreenShareQuality.q720p15 => const ScreenShareQualityProfile(
    scaleResolutionDownBy: 1.5,
    maxFramerate: 15,
    maxBitrate: 1500000,
  ),
  RtcScreenShareQuality.q360p3 => const ScreenShareQualityProfile(
    scaleResolutionDownBy: 3,
    maxFramerate: 3,
    maxBitrate: 200000,
  ),
};

/// Opções fixas da captura: uma fonte 1080p60 permite alterar apenas os
/// parâmetros do sender enquanto o compartilhamento permanece ativo.
ScreenShareCaptureOptions screenShareCaptureOptionsFor(String? sourceId) =>
    ScreenShareCaptureOptions(
      sourceId: sourceId,
      maxFrameRate: 60,
      params: LiveKitRtcService.screenShareH1080FPS60,
    );

/// Transforma cada camada a partir do baseline do sender, preservando RID,
/// SSRC, active e as prioridades. A proporção de bitrate/resolução entre as
/// camadas simulcast também é preservada.
List<rtc.RTCRtpEncoding> screenShareQualityEncodings({
  required List<rtc.RTCRtpEncoding> baseline,
  required RtcScreenShareQuality quality,
}) {
  final profile = screenShareQualityProfile(quality);
  final reference = baseline.reduce((a, b) {
    final aScale = a.scaleResolutionDownBy ?? 1;
    final bScale = b.scaleResolutionDownBy ?? 1;
    return aScale <= bScale ? a : b;
  });
  final referenceScale = reference.scaleResolutionDownBy ?? 1;
  final referenceBitrate = reference.maxBitrate ?? profile.maxBitrate;

  return baseline.map((encoding) {
    final scale = encoding.scaleResolutionDownBy ?? 1;
    final bitrate = encoding.maxBitrate ?? referenceBitrate;
    final bitrateRatio = referenceBitrate == 0 ? 1 : bitrate / referenceBitrate;
    return rtc.RTCRtpEncoding(
      rid: encoding.rid,
      active: encoding.active,
      maxBitrate: (profile.maxBitrate * bitrateRatio).round(),
      maxFramerate: profile.maxFramerate,
      scaleResolutionDownBy:
          profile.scaleResolutionDownBy * scale / referenceScale,
      minBitrate: encoding.minBitrate,
      numTemporalLayers: encoding.numTemporalLayers,
      ssrc: encoding.ssrc,
      scalabilityMode: encoding.scalabilityMode,
      priority: encoding.priority,
      networkPriority: encoding.networkPriority,
    );
  }).toList();
}

List<rtc.RTCRtpEncoding> _cloneScreenShareEncodings(
  List<rtc.RTCRtpEncoding> encodings,
) => encodings
    .map(
      (encoding) => rtc.RTCRtpEncoding(
        rid: encoding.rid,
        active: encoding.active,
        maxBitrate: encoding.maxBitrate,
        maxFramerate: encoding.maxFramerate,
        scaleResolutionDownBy: encoding.scaleResolutionDownBy,
        minBitrate: encoding.minBitrate,
        numTemporalLayers: encoding.numTemporalLayers,
        ssrc: encoding.ssrc,
        scalabilityMode: encoding.scalabilityMode,
        priority: encoding.priority,
        networkPriority: encoding.networkPriority,
      ),
    )
    .toList();

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
