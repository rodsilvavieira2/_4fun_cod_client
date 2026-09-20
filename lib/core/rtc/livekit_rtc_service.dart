import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, visibleForTesting;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

// `SpeakingChangedEvent` e `ReconnectingEvent` (mixin, events.dart:71)
// existem TAMBÉM no livekit_client (colisão de nome com eventos do contrato);
// o projeto usa os do rtc_service.dart.
import 'package:livekit_client/livekit_client.dart'
    hide SpeakingChangedEvent, ReconnectingEvent;

import '../logging/app_logger.dart';
import '../native/native_media_backend.dart';
import 'local_audio_gain_processor.dart';
import 'rtc_service.dart';
import 'screen_share_adaptive.dart';

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
  LiveKitRtcService({
    RoomOptions? roomOptions,
    NativeMediaServices? nativeMediaServices,
    AppLogger? logger,
  }) : _roomOptions = roomOptions ?? defaultRoomOptions,
       _nativeMediaServices =
           nativeMediaServices ??
           const DefaultNativeMediaServicesFactory().create(
             currentRuntimePlatform,
           ) {
    _logger = logger;
  }

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
  ///   perfil Auto (1080p60, topo da escada adaptativa), com simulcast
  ///   calculado pelo SDK.
  static final RoomOptions defaultRoomOptions = RoomOptions(
    defaultAudioCaptureOptions: _buildMicrophoneCaptureOptions(
      noiseSuppressionMode: RtcNoiseSuppressionMode.webrtc,
      defaults: const AudioCaptureOptions(),
    ),
    defaultAudioPublishOptions: const AudioPublishOptions(
      encoding: AudioEncoding(maxBitrate: 64000),
    ),
    adaptiveStream: true,
    dynacast: true,
    defaultVideoPublishOptions: const VideoPublishOptions(
      simulcast: true,
      // Publicação inicial = topo da escada (1080p60, 8 Mbps): o modo Auto
      // já transmite em Full HD 60 fps do primeiro frame, sem rampa de ~60s
      // até o teto. Rede fraca cai via controlador adaptativo (2 amostras
      // ruins = 1 degrau). 720p60 (3,5 Mbps) via chip Médio no Go Live.
      screenShareEncoding: VideoEncoding(maxBitrate: 8000000, maxFramerate: 60),
    ),
  );

  /// Teto de captura do screen share. A fonte nasce em 1080p60 para que o
  /// sender possa subir de 15/30 para 60 FPS sem recriar a track ou reabrir
  /// o picker.
  static const VideoParameters screenShareH1080FPS60 = VideoParameters(
    dimensions: VideoDimensions(1920, 1080),
    encoding: VideoEncoding(maxBitrate: 8000000, maxFramerate: 60),
  );

  @visibleForTesting
  static AudioCaptureOptions microphoneCaptureOptionsForTesting({
    bool? noiseSuppressionEnabled,
    RtcNoiseSuppressionMode? noiseSuppressionMode,
    String? deviceId,
    AudioCaptureOptions defaults = const AudioCaptureOptions(),
  }) => _buildMicrophoneCaptureOptions(
    noiseSuppressionMode:
        noiseSuppressionMode ??
        (noiseSuppressionEnabled == false
            ? RtcNoiseSuppressionMode.off
            : RtcNoiseSuppressionMode.webrtc),
    deviceId: deviceId,
    defaults: defaults,
  );

  static AudioCaptureOptions _buildMicrophoneCaptureOptions({
    required RtcNoiseSuppressionMode noiseSuppressionMode,
    String? deviceId,
    required AudioCaptureOptions defaults,
  }) {
    final useWebRtcSuppression =
        noiseSuppressionMode == RtcNoiseSuppressionMode.webrtc;
    // Studio roda o pipeline próprio (DeepFilterNet + AGC/compressor/limiter
    // nativos, após o AEC): desliga o NS e o AGC do WebRTC para nenhum
    // estágio rodar em duplicidade. O AEC continua no WebRTC em todos os
    // modos. Diagnóstico do silêncio (2026-09-16): a hipótese de gate do DF
    // por falta de AGC caiu — inputPeak 30917 provou captura saudável em
    // escala S16 e o clamp ±1 do pipeline zerava tudo. Com o AutoScale
    // nativo normalizando a escala, o AGC próprio assume sozinho.
    final useWebRtcAgc = noiseSuppressionMode != RtcNoiseSuppressionMode.studio;
    return AudioCaptureOptions(
      deviceId: deviceId,
      echoCancellation: true,
      noiseSuppression: useWebRtcSuppression,
      autoGainControl: useWebRtcAgc,
      // Studio usa o HPF RBJ 60 Hz próprio (pré-rede): desliga o HPF do
      // WebRTC no modo studio para não filtrar duas vezes (round 10).
      highPassFilter: noiseSuppressionMode != RtcNoiseSuppressionMode.studio,
      echoCancellationMode: defaults.echoCancellationMode,
      noiseSuppressionMode: defaults.noiseSuppressionMode,
      autoGainControlMode: defaults.autoGainControlMode,
      highPassFilterMode: defaults.highPassFilterMode,
      voiceIsolation: useWebRtcSuppression,
      typingNoiseDetection: useWebRtcSuppression,
      stopAudioCaptureOnMute: defaults.stopAudioCaptureOnMute,
      processor: defaults.processor,
    );
  }

  /// Opções da sala. O microfone é publicado conforme a preferência global
  /// pendente, que no primeiro uso é ativa.
  final RoomOptions _roomOptions;
  final NativeMediaServices _nativeMediaServices;

  /// Logger opcional (injetado pelo provider) para o probe de stats do
  /// screen share. Null em testes/widget — cai para `debugPrint`.
  ///
  /// `late final` porque um formal inicializador (`this._logger`) geraria
  /// um parâmetro nomeado privado, inutilizável fora desta library.
  late final AppLogger? _logger;

  Room? _room;
  RtcTokenGenerator? _tokenGenerator;

  /// URL da sala do último [connect] — preservada pelo loop de reconexão
  /// automática (zerada no [_cleanupRoom], junto com o [_tokenGenerator]).
  String? _livekitUrl;
  bool _disposed = false;

  /// Perfil escolhido para o screen share. Fica pendente entre shares e é
  /// resetado no [_cleanupRoom] (sessão nova = auto).
  RtcScreenShareQuality _screenShareQuality = RtcScreenShareQuality.auto;

  /// Qualidade EFETIVA do share local (`<= _screenShareQuality`), decidida
  /// pelo [_adaptiveController]. Sem share ativo, espelha o objetivo.
  RtcScreenShareQuality _screenShareEffective = RtcScreenShareQuality.auto;

  /// Controlador adaptativo (spec V1 — só screen share): o teto é sempre o
  /// objetivo do usuário; a efetiva desce rápido e sobe devagar.
  final ScreenShareAdaptiveController _adaptiveController =
      ScreenShareAdaptiveController(target: RtcScreenShareQuality.auto);

  /// Época do share: invalida amostras adaptativas em voo. Toda ação que
  /// troca o estado de qualidade (start/stop/troca manual/teardown)
  /// incrementa — o passo automático só comita se a época for a mesma
  /// antes E depois dos awaits (sender, sala e escolha intactos).
  int _screenShareEpoch = 0;

  void _bumpScreenShareEpoch() {
    _screenShareEpoch++;
  }

  /// Câmera escolhida no sheet. Fica em memória durante a sessão para que a
  /// seleção feita no preview também seja usada quando a câmera for publicada.
  String? _selectedCameraId;

  /// Preferências de áudio são locais e sobrevivem à sala atual. Quando não
  /// há room, ficam pendentes para o próximo connect.
  String? _selectedAudioInputId;
  String? _selectedAudioOutputId;
  bool _microphoneEnabled = true;
  bool _remoteAudioEnabled = true;
  RtcNoiseSuppressionMode _noiseSuppressionMode =
      RtcNoiseSuppressionMode.webrtc;
  RtcNoiseSuppressionMode _effectiveNoiseSuppressionMode =
      RtcNoiseSuppressionMode.webrtc;
  bool _deepFilterNetAvailable = false;
  bool _deepFilterNetInstalled = false;

  /// Volume de voz (fatia volumes): entrada `0.0..1.0`, demais `0.0..2.0`.
  /// Pendentes sem sala — aplicados em publicação/subscribe/reconexão/device.
  double _inputGain = 1.0;
  double _outputGain = 1.0;
  final Map<String, double> _participantGains = {};

  /// Ganho individual do ÁUDIO DA TRANSMISSÃO por identity (só faixas
  /// screenShareAudio — o slider do tile de tela não toca na voz).
  final Map<String, double> _screenShareAudioGains = {};

  /// Transmissões com áudio LIBERADO pelo opt-in "Assistir" (identities).
  /// Default deny: toda `screenShareAudio` remota nasce parada até
  /// [setScreenShareAudioEnabled] liberar. Só afeta `screenShareAudio` — a
  /// voz (microfone) nunca passa por aqui. Pendente sem sala (vale para
  /// tracks futuras); limpo no teardown/cleanup (sessão nova = nada
  /// assistido) e podado no disconnect do participante.
  final Set<String> _watchedScreenAudioIds = {};

  /// Ganho pendente da fonte: voz usa [_participantGains], transmissão usa
  /// [_screenShareAudioGains].
  double _sourceGain(String identity, bool isScreenShareAudio) =>
      isScreenShareAudio
      ? _screenShareAudioGains[identity] ?? 1.0
      : _participantGains[identity] ?? 1.0;
  LocalAudioGainProcessor? _localAudioGainProcessor;

  /// Serialização/coalescing das aplicações de volume durante o arraste do
  /// slider: só o valor mais recente é efetivamente aplicado por rodada.
  Future<void> _volumeApplyChain = Future<void>.value();
  bool _volumeApplyInFlight = false;
  bool _volumeApplyDirty = false;

  /// Track de preview criada fora da room. Ela nunca é publicada e só existe
  /// enquanto o sheet de configurações está aberto.
  LocalVideoTrack? _cameraPreviewTrack;

  /// Serializa start/switch/stop do preview: fechar o sheet durante uma
  /// abertura de câmera não pode deixar uma captura órfã no hardware.
  Future<void> _cameraPreviewOperation = Future<void>.value();

  /// Incrementado antes de cada abertura/fechamento. Uma abertura que termina
  /// depois de o sheet ser fechado deve liberar a track recém-criada, sem
  /// devolvê-la à UI nem mantê-la como captura ativa.
  int _cameraPreviewGeneration = 0;

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

  /// Atualiza o ping exibido no painel de voz usando o RTT do par ICE que
  /// está carregando a conexão com o servidor LiveKit.
  static const Duration _latencyPollInterval = Duration(seconds: 5);
  Timer? _latencyTimer;
  int _latencyGeneration = 0;
  bool _latencyPollInFlight = false;
  int? _lastLatencyMs;

  @override
  RtcScreenShareQuality get screenShareQuality => _screenShareQuality;

  @override
  RtcScreenShareQuality get effectiveScreenShareQuality =>
      _screenShareEffective;

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

  @override
  Stream<void> get mediaDevicesChanged =>
      Hardware.instance.onDeviceChange.stream.map<void>((_) {});

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
    _rtcDebug(
      'rtc connect solicitado '
      '(url=$url, mic=$_microphoneEnabled, input=${_selectedAudioInputId ?? '-'}, '
      'noiseRequested=${_noiseSuppressionMode.name}, '
      'noiseEffective=${_effectiveNoiseSuppressionMode.name}, '
      'deepFilterAvailable=$_deepFilterNetAvailable)',
    );
    // Sempre parte de um estado limpo (idempotente com um connect anterior).
    // O await garante que o disconnect/dispose nativos do Room ANTERIOR
    // terminaram antes de criar o novo (sem dois Room/PeerConnection vivos).
    await disconnect();
    _tokenGenerator = tokenGenerator;
    _livekitUrl = url; // preservada para o loop de reconexão automática

    final effectiveOptions = _effectiveRoomOptions();
    final room = Room(roomOptions: effectiveOptions);
    _room = room;
    _wire(room);

    try {
      _rtcDebug('rtc room.connect iniciando (url=$url)');
      await room.connect(url, token);
      _rtcDebug('rtc room.connect concluído (url=$url)');
    } catch (error, stackTrace) {
      _rtcError('rtc room.connect falhou (url=$url)', error, stackTrace);
      await _cleanupRoom();
      rethrow; // o controller trata o erro (token inválido, servidor fora etc.)
    }

    // Publica o mic já no estado desejado. A preferência pode ter sido
    // alterada fora da sala e não pode gerar uma janela em que o usuário
    // entra transmitindo antes de o controller conseguir mutá-lo.
    final localParticipant = room.localParticipant;
    if (localParticipant == null) {
      // Impossível na prática pós-connect (o Room sempre tem o participante
      // local); sem ele não há mic a publicar.
      return;
    }
    try {
      final captureOptions = _currentMicrophoneCaptureOptions(room);
      _rtcDebug(
        'rtc mic publish iniciando '
        '(enabled=$_microphoneEnabled, options=${_describeAudioCaptureOptions(captureOptions)})',
      );
      await localParticipant.setMicrophoneEnabled(
        _microphoneEnabled,
        audioCaptureOptions: captureOptions,
      );
      await _applyInputVolumeToMicrophone();
      _rtcDebug('rtc mic publish concluído (enabled=$_microphoneEnabled)');
    } catch (error, stackTrace) {
      _rtcError('rtc mic publish falhou', error, stackTrace);
      // Falha ao publicar o mic: NUNCA deixa o Room órfão — limpa e propaga.
      await _cleanupRoom();
      rethrow;
    }
    // Seed do snapshot: local + participantes REMOTOS já presentes (o SDK
    // 2.11 NÃO emite eventos para eles no join response — ver
    // [_seedParticipants]). Sem isso a UI mostraria a sala vazia até alguém
    // publicar track/mutar.
    _seedParticipants(room);
    _startLatencyMonitor(room);
    _scheduleVolumeApply();
  }

  @override
  Future<void> disconnect() {
    _rtcDebug('rtc disconnect solicitado');
    return _cleanupRoom();
  }

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

  /// Tópico das data messages de som de UI (ADR-0001). Versionado (`/v1`)
  /// para permitir mudar o payload sem quebrar clients antigos (que ignoram
  /// tópicos desconhecidos).
  static const voiceSoundTopic = 'voice-sound/v1';

  @override
  Future<void> publishVoiceSound(RtcVoiceSound sound) async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    // Best-effort: o som local já tocou e a sessão não pode cair porque o
    // anúncio falhou (rede instável, sala morrendo...).
    try {
      await localParticipant.publishData(
        utf8.encode(jsonEncode({'sound': sound.name})),
        reliable: true,
        topic: voiceSoundTopic,
      );
    } catch (error, stackTrace) {
      _rtcDebug('rtc publishVoiceSound falhou (${sound.name}): $error');
      _rtcError('rtc publishVoiceSound falhou (${sound.name})', error, stackTrace);
    }
  }

  /// Converte um sinal `voice-sound/v1` em [VoiceSoundSignalEvent].
  /// Formato desconhecido/malformado = ignorado (nunca derruba a sala).
  void _handleVoiceSoundSignal(DataReceivedEvent event) {
    if (event.topic != voiceSoundTopic) return;
    final sender = event.participant?.identity;
    if (sender == null || sender.isEmpty) return;
    RtcVoiceSound? sound;
    try {
      final decoded = jsonDecode(utf8.decode(event.data));
      if (decoded is Map<String, dynamic>) {
        final name = decoded['sound'];
        if (name is String) {
          sound = RtcVoiceSound.values.cast<RtcVoiceSound?>().firstWhere(
            (value) => value?.name == name,
            orElse: () => null,
          );
        }
      }
    } catch (_) {
      return;
    }
    if (sound == null) return;
    _emitEvent(VoiceSoundSignalEvent(participantId: sender, sound: sound));
  }

  @override
  Future<void> enableMicrophone() async {
    final room = _room;
    if (room == null || _disposed) {
      if (!_disposed) _microphoneEnabled = true;
      _rtcDebug(
        'rtc enableMicrophone pendente '
        '(room=${room != null}, disposed=$_disposed)',
      );
      return;
    }
    final localParticipant = room.localParticipant;
    if (localParticipant == null) {
      _microphoneEnabled = true;
      _rtcWarn('rtc enableMicrophone sem participante local');
      return;
    }
    final options = _currentMicrophoneCaptureOptions(room);
    _rtcDebug(
      'rtc enableMicrophone aplicando '
      '(options=${_describeAudioCaptureOptions(options)})',
    );
    await localParticipant.setMicrophoneEnabled(
      true,
      audioCaptureOptions: options,
    );
    _microphoneEnabled = true;
    await _applyInputVolumeToMicrophone();
    // O estado é atualizado pelos eventos TrackMuted/Unmuted +
    // LocalTrackPublished/Unpublished.
  }

  @override
  Future<void> disableMicrophone() async {
    final room = _room;
    if (room == null || _disposed) {
      if (!_disposed) _microphoneEnabled = false;
      _rtcDebug(
        'rtc disableMicrophone pendente '
        '(room=${room != null}, disposed=$_disposed)',
      );
      return;
    }
    final localParticipant = room.localParticipant;
    if (localParticipant == null) {
      _microphoneEnabled = false;
      _rtcWarn('rtc disableMicrophone sem participante local');
      return;
    }
    _rtcDebug('rtc disableMicrophone aplicando');
    await localParticipant.setMicrophoneEnabled(false);
    _microphoneEnabled = false;
  }

  @override
  Future<void> enableCamera() async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    // Se o usuário pedir publicação enquanto há um preview temporário, nunca
    // mantenha duas capturas da mesma webcam. O preview é local; a publicação
    // assume o hardware agora.
    await stopCameraPreview();
    final existingTrack = localParticipant
        .getTrackPublicationBySource(TrackSource.camera)
        ?.track;
    if (_selectedCameraId != null && existingTrack is LocalVideoTrack) {
      await existingTrack.switchCamera(_selectedCameraId!);
    }
    // A câmera segue integralmente os defaults de captura/publicação do SDK e
    // do dispositivo, exceto pelo device escolhido no sheet. O controle de
    // qualidade pertence apenas ao screen share e nunca recria nem republica
    // esta track.
    await localParticipant.setCameraEnabled(
      true,
      cameraCaptureOptions: _cameraCaptureOptions(),
    );
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
  Future<RtcVideoTrackRef> startCameraPreview({String? deviceId}) {
    final generation = ++_cameraPreviewGeneration;
    return _runCameraPreviewOperation(() async {
      if (!_isCurrentCameraPreviewGeneration(generation)) {
        throw StateError('Preview da câmera cancelado.');
      }
      final room = _room;
      final localParticipant = room?.localParticipant;
      if (room == null || localParticipant == null || _disposed) {
        throw StateError(
          'Não há sessão de voz ativa para pré-visualizar a câmera.',
        );
      }

      final publication = localParticipant.getTrackPublicationBySource(
        TrackSource.camera,
      );
      final publishedTrack = publication?.track;
      if (publication != null &&
          !publication.muted &&
          publishedTrack is VideoTrack) {
        // Já existe uma captura PUBLICADA. Reutilizá-la evita abrir a webcam
        // duas vezes e mantém a privacidade/estado exatamente como estavam.
        await _stopCameraPreviewUnlocked();
        if (!_isCurrentCameraPreviewGeneration(generation)) {
          throw StateError('Preview da câmera cancelado.');
        }
        return LiveKitVideoTrackRef(publishedTrack as VideoTrack);
      }

      final desiredDeviceId = deviceId ?? _selectedCameraId;
      final preview = _cameraPreviewTrack;
      if (preview != null) {
        if (desiredDeviceId != null && desiredDeviceId != _selectedCameraId) {
          await preview.switchCamera(desiredDeviceId);
          _selectedCameraId = desiredDeviceId;
        }
        if (!_isCurrentCameraPreviewGeneration(generation)) {
          throw StateError('Preview da câmera cancelado.');
        }
        return LiveKitVideoTrackRef(preview);
      }

      LocalVideoTrack? createdTrack;
      try {
        createdTrack = await _nativeMediaServices.camera.createCameraTrack(
          _cameraCaptureOptions(deviceId: desiredDeviceId),
        );
        if (!_isCurrentCameraPreviewGeneration(generation)) {
          await _discardCameraPreviewTrack(createdTrack);
          throw StateError('Preview da câmera cancelado.');
        }
        await createdTrack.start();
        if (!_isCurrentCameraPreviewGeneration(generation)) {
          await _discardCameraPreviewTrack(createdTrack);
          throw StateError('Preview da câmera cancelado.');
        }
        _cameraPreviewTrack = createdTrack;
        if (desiredDeviceId != null) _selectedCameraId = desiredDeviceId;
        return LiveKitVideoTrackRef(createdTrack);
      } catch (_) {
        if (createdTrack != null) {
          await _discardCameraPreviewTrack(createdTrack);
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> stopCameraPreview() {
    // Invalida ANTES de aguardar a fila. Assim, se getUserMedia concluir
    // depois do fechamento do sheet, a abertura descarta a track na hora.
    _cameraPreviewGeneration++;
    return _runCameraPreviewOperation(_stopCameraPreviewUnlocked);
  }

  @override
  Future<void> setScreenShareQuality(RtcScreenShareQuality quality) async {
    final room = _room;
    if (room == null || _disposed) return;
    final localParticipant = room.localParticipant;
    if (localParticipant == null) return;
    final publication = localParticipant.getTrackPublicationBySource(
      TrackSource.screenShareVideo,
    );
    if (publication == null || publication.track is! LocalVideoTrack) {
      if (quality == _screenShareQuality) return;
      // Sem share ativo, a escolha fica pendente para o próximo início.
      _screenShareQuality = quality;
      _screenShareEffective = quality;
      _adaptiveController.setTarget(quality);
      _bumpScreenShareEpoch();
      return;
    }

    // Com share ativo, o no-op compara com o alvo ATIVO (não com o
    // pendente): um one-shot pode divergir do pendente, e nesse caso
    // escolher o valor do pendente TEM que aplicar no sender.
    // Divergir da efetiva também não é no-op — a escolha explícita
    // reassume o teto na hora (ver abaixo).
    if (quality == _adaptiveController.target &&
        quality == _screenShareEffective) {
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
      // Escolha explícita do usuário: a efetiva assume o teto na hora.
      _adaptiveController.setTarget(quality);
      _setEffectiveQuality(quality);
      _bumpScreenShareEpoch();
    } catch (_) {
      if (quality == RtcScreenShareQuality.auto) rethrow;
      try {
        await _applyScreenShareQuality(
          sender,
          baseline,
          RtcScreenShareQuality.auto,
        );
        _screenShareQuality = RtcScreenShareQuality.auto;
        _adaptiveController.setTarget(RtcScreenShareQuality.auto);
        _setEffectiveQuality(RtcScreenShareQuality.auto);
        _bumpScreenShareEpoch();
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
    bool includeSystemAudio = true,
    RtcScreenShareQuality? quality,
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
        // One-shot (modal Go Live): aplica o pedido sem tocar no pendente.
        final requested = quality ?? _screenShareQuality;
        // Teto adaptativo deste share = qualidade pedida; a efetiva começa
        // no teto (one-shot não altera o pendente para o próximo share).
        _adaptiveController.setTarget(requested);
        _screenShareEffective = requested;
        _bumpScreenShareEpoch();
        if (baseline.isEmpty) {
          if (quality == null) {
            _screenShareQuality = RtcScreenShareQuality.auto;
          }
        }
        if (requested != RtcScreenShareQuality.auto && baseline.isNotEmpty) {
          try {
            await _applyScreenShareQuality(sender, baseline, requested);
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
            // Fallback silencioso para Auto: no modo one-shot o pendente é
            // preservado — o controller então reporta o pedido em vez do
            // efetivo neste caso raro (sender recusou os parâmetros).
            // O fio está em Auto: a adaptação parte desse teto real.
            _adaptiveController.setTarget(RtcScreenShareQuality.auto);
            _screenShareEffective = RtcScreenShareQuality.auto;
            _bumpScreenShareEpoch();
            if (quality == null) {
              _screenShareQuality = RtcScreenShareQuality.auto;
            }
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
    // Share encerrado: a efetiva volta ao pendente e a adaptação congela
    // (o poll só adapta com share ativo).
    _screenShareEffective = _screenShareQuality;
    _adaptiveController.setTarget(_screenShareQuality);
    _bumpScreenShareEpoch();
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
    final captureOptions = systemAudioCaptureOptionsFor(monitorId);
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
    await _runCameraPreviewOperation(() async {
      final room = _room;
      if (_disposed) return;
      // A preferência precisa sobreviver mesmo fora de uma chamada: a próxima
      // publicação/preview já deve abrir na câmera selecionada.
      _selectedCameraId = deviceId;
      if (room == null) return;
      final localParticipant = room.localParticipant;
      if (localParticipant == null) return;

      final preview = _cameraPreviewTrack;
      if (preview != null) {
        // API nativa 2.11.0: restartTrack interno, sem republicar nada.
        await preview.switchCamera(deviceId);
        return;
      }

      final track = localParticipant
          .getTrackPublicationBySource(TrackSource.camera)
          ?.track;
      if (track is LocalVideoTrack) {
        await track.switchCamera(deviceId);
      }
      // Com a câmera OFF e sem preview, a seleção ainda precisa sobreviver
      // para o próximo enableCamera().
    });
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
  Future<List<RtcAudioDevice>> listAudioInputDevices() async {
    final devices = await _nativeMediaServices.audioDevices.listInputs();
    return [
      for (final device in devices)
        RtcAudioDevice(
          id: device.deviceId,
          label: device.label,
          kind: RtcMediaDeviceKind.audioInput,
        ),
    ];
  }

  @override
  Future<List<RtcAudioDevice>> listAudioOutputDevices() async {
    final devices = await _nativeMediaServices.audioDevices.listOutputs();
    return [
      for (final device in devices)
        RtcAudioDevice(
          id: device.deviceId,
          label: device.label,
          kind: RtcMediaDeviceKind.audioOutput,
        ),
    ];
  }

  @override
  Future<void> selectAudioInput(String? deviceId) async {
    if (_disposed) return;
    final devices = await _nativeMediaServices.audioDevices.listInputs();
    final device = _resolveAudioDevice(devices, deviceId);
    if (device == null) {
      if (deviceId != null) {
        throw StateError('Microfone selecionado não está disponível.');
      }
      _selectedAudioInputId = null;
      return;
    }
    final room = _room;
    if (room != null) {
      await room.setAudioInputDevice(device);
      _selectedAudioInputId = deviceId;
      _syncRoomAudioCaptureOptions(room);
      await _applyInputVolumeToMicrophone();
    } else if (!kIsWeb) {
      await _nativeMediaServices.audioDevices.selectInput(device);
    }
    _selectedAudioInputId = deviceId;
  }

  @override
  Future<void> selectAudioOutput(String? deviceId) async {
    if (_disposed) return;
    final devices = await _nativeMediaServices.audioDevices.listOutputs();
    final device = _resolveAudioDevice(devices, deviceId);
    if (device == null) {
      if (deviceId != null) {
        throw StateError('Saída de áudio selecionada não está disponível.');
      }
      _selectedAudioOutputId = null;
      return;
    }
    final room = _room;
    if (room != null) {
      await room.setAudioOutputDevice(device);
    } else if (!kIsWeb) {
      await _nativeMediaServices.audioDevices.selectOutput(device);
    }
    _selectedAudioOutputId = deviceId;
    // Troca de dispositivo pode recriar os elementos de áudio (web): reaplica.
    _scheduleVolumeApply();
  }

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) async {
    final room = _room;
    if (room == null || _disposed) {
      if (!_disposed) _remoteAudioEnabled = enabled;
      return;
    }
    final previous = _remoteAudioEnabled;
    // Atualiza antes de percorrer as tracks para que uma inscrição concorrente
    // respeite imediatamente a decisão em [_wire].
    _remoteAudioEnabled = enabled;
    try {
      for (final participant in room.remoteParticipants.values) {
        for (final publication in participant.audioTrackPublications) {
          final track = publication.track;
          if (track is! RemoteAudioTrack) continue;
          if (enabled) {
            // Undeafen respeita o opt-in de transmissão: screenShareAudio de
            // quem não está sendo assistido continua parado.
            if (publication.source == TrackSource.screenShareAudio &&
                !_watchedScreenAudioIds.contains(participant.identity)) {
              continue;
            }
            await track.start();
          } else {
            await track.stop();
          }
        }
      }
      if (enabled) _scheduleVolumeApply();
    } catch (_) {
      _remoteAudioEnabled = previous;
      rethrow;
    }
  }

  /// Opt-in de áudio da transmissão (espelho do opt-in de vídeo do
  /// `VoiceController.toggleWatch`): só publicações `screenShareAudio`
  /// remotas. A voz (microfone) nunca passa por aqui; local/desconhecido é
  /// no-op. Sem sala, a preferência fica pendente para publicações futuras.
  ///
  /// Atua na PUBLICAÇÃO (`enable()`/`disable()` → `UpdateTrackSettings` no
  /// servidor), nunca na track (`stop()` nativo encerra a
  /// `MediaStreamTrack` de vez e `start()` não revive; além disso o
  /// `TrackSubscribedEvent` chega antes do `start()` do SDK, então `stop()`
  /// ali é no-op garantido).
  @override
  Future<void> setScreenShareAudioEnabled(
    String identity,
    bool enabled,
  ) async {
    if (identity.isEmpty || _disposed) {
      if (!_disposed) {
        if (enabled) {
          _watchedScreenAudioIds.add(identity);
        } else {
          _watchedScreenAudioIds.remove(identity);
        }
      }
      return;
    }
    final room = _room;
    // Local nunca entra no opt-in (sempre audível/visível para si).
    if (room?.localParticipant?.identity == identity) return;
    if (room == null) {
      if (enabled) {
        _watchedScreenAudioIds.add(identity);
      } else {
        _watchedScreenAudioIds.remove(identity);
      }
      return;
    }
    if (enabled) {
      _watchedScreenAudioIds.add(identity);
      final publication = _screenShareAudioPublicationOf(room, identity);
      if (publication == null) {
        _rtcDebug('rtc screen audio enable pendente (sem publicação): $identity');
        return;
      }
      try {
        // Deafen global soberano: a preferência da publicação é liberada,
        // mas a track só volta a tocar no undeafen (que reaplica o volume).
        await publication.enable();
        if (!_remoteAudioEnabled) return;
        final track = publication.track;
        if (track == null) return;
        final gain = effectiveVolumeGain(
          _outputGain,
          _sourceGain(identity, true),
        );
        await _applyTrackVolume(track, gain);
      } catch (error, stackTrace) {
        _rtcError(
          'rtc screen audio enable falhou para $identity',
          error,
          stackTrace,
        );
      }
      return;
    }
    _watchedScreenAudioIds.remove(identity);
    final publication = _screenShareAudioPublicationOf(room, identity);
    if (publication == null) {
      _rtcDebug('rtc screen audio disable sem publicação: $identity');
      return;
    }
    try {
      await publication.disable();
    } catch (error, stackTrace) {
      _rtcError(
        'rtc screen audio disable falhou para $identity',
        error,
        stackTrace,
      );
    }
  }

  /// Publicação remota de `screenShareAudio` de [identity], ou null sem
  /// participante ou sem publicação. Funciona mesmo com `track == null`
  /// (antes do subscribe terminar) — `disable()`/`enable()` operam por `sid`.
  RemoteTrackPublication<RemoteAudioTrack>? _screenShareAudioPublicationOf(
    Room room,
    String identity,
  ) {
    final participant = room.remoteParticipants[identity];
    if (participant == null) return null;
    for (final publication in participant.audioTrackPublications) {
      if (publication.source == TrackSource.screenShareAudio) {
        return publication;
      }
    }
    return null;
  }

  /// Normaliza ganho público para `0.0..2.0`.
  static double normalizeVolumeGain(double gain) =>
      gain.isNaN ? 1.0 : gain.clamp(0.0, 2.0);

  /// Normaliza ganho do microfone publicado para `0.0..1.0`.
  static double normalizeInputGain(double gain) =>
      gain.isNaN ? 1.0 : gain.clamp(0.0, 1.0);

  /// Ganho efetivo: `saída × participante`, teto `4.0`.
  static double effectiveVolumeGain(
    double outputGain,
    double participantGain,
  ) => (normalizeVolumeGain(outputGain) * normalizeVolumeGain(participantGain))
      .clamp(0.0, 4.0);

  @override
  Future<void> setOutputVolume(double gain) async {
    _outputGain = normalizeVolumeGain(gain);
    _scheduleVolumeApply();
  }

  @override
  Future<void> setInputVolume(double gain) async {
    _inputGain = normalizeInputGain(gain);
    await _applyInputVolumeToMicrophone();
  }

  Future<void> setNoiseSuppressionEnabled(bool enabled) async {
    await setNoiseSuppressionMode(
      enabled ? RtcNoiseSuppressionMode.webrtc : RtcNoiseSuppressionMode.off,
    );
  }

  @override
  Future<RtcNoiseSuppressionStatus> setNoiseSuppressionMode(
    RtcNoiseSuppressionMode mode,
  ) async {
    _rtcDebug(
      'rtc noise mode solicitado '
      '(requested=${mode.name}, currentRequested=${_noiseSuppressionMode.name}, '
      'currentEffective=${_effectiveNoiseSuppressionMode.name})',
    );
    if (_disposed) {
      return _noiseSuppressionStatus(requestedMode: mode);
    }

    final previousRequestedMode = _noiseSuppressionMode;
    final previousEffectiveMode = _effectiveNoiseSuppressionMode;
    final previousDeepFilterNetAvailable = _deepFilterNetAvailable;

    final status = await _resolveNoiseSuppressionMode(mode);
    _rtcDebug(
      'rtc noise mode resolvido '
      '(requested=${status.requestedMode.name}, effective=${status.effectiveMode.name}, '
      'deepFilterAvailable=${status.deepFilterNetAvailable}, message=${status.message ?? '-'})',
    );
    _noiseSuppressionMode = status.requestedMode;
    _effectiveNoiseSuppressionMode = status.effectiveMode;
    _deepFilterNetAvailable = status.deepFilterNetAvailable;

    final room = _room;
    if (room == null) {
      _rtcDebug('rtc noise mode aplicado como pendente (sem sala ativa)');
      return status;
    }

    final localParticipant = room.localParticipant;
    final publication = localParticipant?.getTrackPublicationBySource(
      TrackSource.microphone,
    );
    final track = publication?.track;
    final nextRoomOptions = _syncRoomAudioCaptureOptions(room);

    if (track is! LocalAudioTrack) {
      _rtcWarn('rtc noise mode sem LocalAudioTrack para reiniciar');
      return status;
    }

    final previousTrackOptions = track.currentOptions;
    final nextTrackOptions = _microphoneCaptureOptions(
      base: previousTrackOptions,
      deviceId: nextRoomOptions.deviceId,
    );

    try {
      if (publication?.muted ?? track.muted) {
        _rtcDebug('rtc noise mode aplicado em track mutada (sem restart)');
        track.currentOptions = nextTrackOptions;
        return status;
      }
      _rtcDebug(
        'rtc noise mode reiniciando track '
        '(options=${_describeAudioCaptureOptions(nextTrackOptions)})',
      );
      await track.restartTrack(nextTrackOptions);
      await _applyInputVolumeToMicrophone();
      _rtcDebug('rtc noise mode restart concluído');
      return status;
    } catch (error, stackTrace) {
      _rtcError('rtc noise mode falhou; revertendo', error, stackTrace);
      _noiseSuppressionMode = previousRequestedMode;
      _effectiveNoiseSuppressionMode = previousEffectiveMode;
      _deepFilterNetAvailable = previousDeepFilterNetAvailable;
      await _setDeepFilterNetEnabled(
        previousEffectiveMode == RtcNoiseSuppressionMode.studio,
      );
      _syncRoomAudioCaptureOptions(room);
      track.currentOptions = previousTrackOptions;
      rethrow;
    }
  }

  RtcNoiseSuppressionStatus _noiseSuppressionStatus({
    RtcNoiseSuppressionMode? requestedMode,
    String? message,
  }) => RtcNoiseSuppressionStatus(
    requestedMode: requestedMode ?? _noiseSuppressionMode,
    effectiveMode: _effectiveNoiseSuppressionMode,
    deepFilterNetAvailable: _deepFilterNetAvailable,
    message: message,
  );

  Future<RtcNoiseSuppressionStatus> _resolveNoiseSuppressionMode(
    RtcNoiseSuppressionMode requestedMode,
  ) async {
    if (requestedMode != RtcNoiseSuppressionMode.studio) {
      await _setDeepFilterNetEnabled(false);
      return RtcNoiseSuppressionStatus(
        requestedMode: requestedMode,
        effectiveMode: requestedMode,
        deepFilterNetAvailable: _deepFilterNetAvailable,
      );
    }

    final enabled = await _setDeepFilterNetEnabled(true);
    if (enabled) {
      return const RtcNoiseSuppressionStatus(
        requestedMode: RtcNoiseSuppressionMode.studio,
        effectiveMode: RtcNoiseSuppressionMode.studio,
        deepFilterNetAvailable: true,
      );
    }
    return const RtcNoiseSuppressionStatus(
      requestedMode: RtcNoiseSuppressionMode.studio,
      effectiveMode: RtcNoiseSuppressionMode.webrtc,
      deepFilterNetAvailable: false,
      message: 'Studio indisponível neste dispositivo. Usando Normal.',
    );
  }

  Future<bool> _setDeepFilterNetEnabled(bool enabled) async {
    if (!enabled && !_deepFilterNetInstalled) {
      _deepFilterNetAvailable = false;
      _rtcDebug('rtc deepFilter desativação ignorada (não instalado)');
      return false;
    }
    try {
      _rtcDebug('rtc deepFilter ${enabled ? 'ativando' : 'desativando'}');
      final available = await rtc
          .NativeAudioManagement.setDeepFilterNoiseSuppressionEnabled(enabled);
      _deepFilterNetAvailable = available;
      _deepFilterNetInstalled = enabled && available;
      _rtcDebug(
        'rtc deepFilter retorno '
        '(requested=$enabled, available=$available, installed=$_deepFilterNetInstalled)',
      );
      if (enabled && available) _scheduleDeepFilterStatsSample();
      return enabled ? available : false;
    } catch (error, stackTrace) {
      _rtcError(
        'rtc deepFilter ${enabled ? 'ativar' : 'desativar'} falhou',
        error,
        stackTrace,
      );
      _deepFilterNetAvailable = false;
      _deepFilterNetInstalled = false;
      return false;
    }
  }

  /// Amostra os contadores nativos ~5 s após ativar o Studio e registra no
  /// log. É a prova, no app rodando, de que o APM está (ou não) entregando
  /// áudio à rede: `processedHops == 0` com `active == true` = bypass
  /// silencioso.
  void _scheduleDeepFilterStatsSample() {
    Future.delayed(const Duration(seconds: 5), () async {
      if (_disposed) return;
      if (_effectiveNoiseSuppressionMode != RtcNoiseSuppressionMode.studio) {
        return;
      }
      try {
        final stats = await rtc.NativeAudioManagement.getDeepFilterStats();
        _rtcDebug('rtc deepFilter stats $stats');
        final active = stats['active'] == true;
        final processedHops = (stats['processedHops'] as num?)?.toInt() ?? 0;
        if (active && processedHops == 0) {
          _rtcError(
            'rtc deepFilter BYPASS: Studio ativo mas nenhum hop processado '
            '(bypassedFrames=${stats['bypassedFrames']}, '
            'lastRateHz=${stats['lastRateHz']})',
            StateError('deepfilter-bypass'),
            StackTrace.current,
          );
        }
      } catch (error, stackTrace) {
        _rtcError('rtc deepFilter stats falhou', error, stackTrace);
      }
    });
  }

  @override
  Future<void> setParticipantVolume(String identity, double gain) async {
    if (identity.isEmpty) return;
    final room = _room;
    // Local nunca recebe volume individual; desconhecido sem sala → pendente.
    if (room?.localParticipant?.identity == identity) return;
    final normalized = normalizeVolumeGain(gain);
    if (normalized == 1.0) {
      _participantGains.remove(identity);
    } else {
      _participantGains[identity] = normalized;
    }
    _scheduleVolumeApply();
  }

  @override
  Future<void> setParticipantSourceVolume(
    String identity,
    RtcAudioSource source,
    double gain,
  ) async {
    if (identity.isEmpty) return;
    final room = _room;
    // Local nunca recebe volume individual; desconhecido sem sala → pendente.
    if (room?.localParticipant?.identity == identity) return;
    final normalized = normalizeVolumeGain(gain);
    final target = source == RtcAudioSource.screenShareAudio
        ? _screenShareAudioGains
        : _participantGains;
    if (normalized == 1.0) {
      target.remove(identity);
    } else {
      target[identity] = normalized;
    }
    _scheduleVolumeApply();
  }

  void _scheduleVolumeApply() {
    if (_disposed) return;
    if (_volumeApplyInFlight) {
      _volumeApplyDirty = true;
      return;
    }
    _volumeApplyInFlight = true;
    _volumeApplyChain = _volumeApplyChain.then((_) async {
      do {
        _volumeApplyDirty = false;
        await _applyAllVolumes();
      } while (_volumeApplyDirty && !_disposed);
      _volumeApplyInFlight = false;
    });
  }

  Future<void> _applyAllVolumes() async {
    final room = _room;
    if (room == null || _disposed) return;
    for (final participant in room.remoteParticipants.values) {
      await _applyParticipantVolumes(
        participant.identity,
        participant.audioTrackPublications,
      );
    }
  }

  Future<void> _applyParticipantVolumes(
    String identity,
    Iterable<RemoteTrackPublication> publications,
  ) async {
    for (final publication in publications) {
      final track = publication.track;
      if (track is! RemoteAudioTrack) continue;
      // A fonte decide o ganho: voz usa o ganho da voz, áudio de share usa
      // o ganho da transmissão — um nunca afeta o outro.
      final gain = effectiveVolumeGain(
        _outputGain,
        _sourceGain(
          identity,
          publication.source == TrackSource.screenShareAudio,
        ),
      );
      try {
        await _applyTrackVolume(track, gain);
      } catch (e) {
        // Best-effort por faixa: registra e reaplica no próximo evento
        // (subscribe/reconexão/device/undeafen).
        debugPrint('[rtc] volume falhou para $identity: $e');
      }
    }
  }

  Future<void> _applyTrackVolume(RemoteAudioTrack track, double gain) async {
    // O fork aplica via GainNode dedicado (web, com boost > 1.0) ou
    // Helper.setVolume (nativo, best-effort); armazena pré-start e registra
    // falha com reaplicação no próximo evento pelo chamador.
    await track.setVolume(gain);
  }

  Future<void> _applyInputVolumeToMicrophone() async {
    final track = _room?.localParticipant
        ?.getTrackPublicationBySource(TrackSource.microphone)
        ?.track;
    if (track is! LocalAudioTrack || _disposed) return;

    final currentProcessor = _localAudioGainProcessor;
    final LocalAudioGainProcessor processor;
    if (currentProcessor != null && track.processor == currentProcessor) {
      processor = currentProcessor;
    } else {
      processor = createLocalAudioGainProcessor(_inputGain);
      _localAudioGainProcessor = processor;
      await track.setProcessor(processor);
    }
    await processor.setGain(_inputGain);
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
  Future<void> setScreenQuality(
    String participantId,
    RtcVideoQuality quality,
  ) async {
    final room = _room;
    if (room == null || _disposed) return;
    // Recepção remota de TELA: local/desconhecido/sem share → no-op.
    // Mapa de dedupe separado da câmera no controller (publicações
    // independentes — o share em destaque não rebaixa a câmera em miniatura).
    final remoteParticipant = room.remoteParticipants[participantId];
    if (remoteParticipant == null) return;
    final publication = remoteParticipant.getTrackPublicationBySource(
      TrackSource.screenShareVideo,
    );
    if (publication == null) return; // share OFF/ausente → no-op
    final videoQuality = switch (quality) {
      RtcVideoQuality.low => VideoQuality.LOW,
      RtcVideoQuality.medium => VideoQuality.MEDIUM,
      RtcVideoQuality.high => VideoQuality.HIGH,
    };
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
      final computed = parameters.encodings?.map((e) => e.toMap()).toList();
      final base = baseline.map((e) => e.toMap()).toList();
      throw StateError(
        'Sender recusou os parâmetros do screen share. '
        'baseline=$base computed=$computed',
      );
    }
    _logScreenShareStats(sender, quality, phase: 'pos-troca');
    // Segunda amostra após estabilizar o encoder (prova wire do fps
    // efetivo — temporário até a telemetria permanente da Wave 3).
    unawaited(
      Future<void>.delayed(const Duration(seconds: 4)).then((_) async {
        if (_disposed || _room == null) return;
        await _logScreenShareStats(sender, quality, phase: 'estabilizado');
      }),
    );
  }

  /// Probe temporário (Wave 1): registra no log os stats `outbound-rtp` do
  /// screen share após a troca de qualidade — resolução, fps e bytes por
  /// camada. Sem isso, só o RTT é coletado e não há como confirmar o fps
  /// efetivo no fio. Será substituído pela telemetria permanente (Wave 3).
  Future<void> _logScreenShareStats(
    rtc.RTCRtpSender sender,
    RtcScreenShareQuality quality, {
    required String phase,
  }) async {
    try {
      final stats = await sender.getStats();
      final outbound = stats.where((s) => s.type == 'outbound-rtp').toList();
      if (outbound.isEmpty) {
        _statsLog(
          'screen stats [$phase] pedido=$quality: sem outbound-rtp '
          '(${stats.length} relatórios)',
        );
        return;
      }
      for (final s in outbound) {
        final v = s.values;
        _statsLog(
          'screen stats [$phase] pedido=$quality '
          'rid=${v['rid']} ${v['frameWidth']}x${v['frameHeight']} '
          'fps=${v['framesPerSecond']} bytes=${v['bytesSent']} '
          'limit=${v['qualityLimitationReason']}',
        );
      }
    } catch (e) {
      debugPrint('[rtc] screen stats [$phase] indisponíveis: $e');
    }
  }

  void _statsLog(String message) {
    final logger = _logger;
    if (logger != null) {
      logger.i(message, tag: 'voice');
    } else {
      debugPrint('[rtc] $message');
    }
  }

  void _rtcDebug(String message) {
    final logger = _logger;
    if (logger != null) {
      logger.d(message, tag: 'voice');
    } else {
      debugPrint('[rtc] $message');
    }
  }

  void _rtcWarn(String message) {
    final logger = _logger;
    if (logger != null) {
      logger.w(message, tag: 'voice');
    } else {
      debugPrint('[rtc] WARNING $message');
    }
  }

  void _rtcError(String message, Object error, StackTrace stackTrace) {
    final logger = _logger;
    if (logger != null) {
      logger.e(message, error: error, stackTrace: stackTrace, tag: 'voice');
    } else {
      debugPrint('[rtc] ERROR $message: $error');
    }
  }

  static String _describeAudioCaptureOptions(AudioCaptureOptions options) {
    return 'device=${options.deviceId ?? '-'}, '
        'aec=${options.echoCancellation}, '
        'ns=${options.noiseSuppression}, '
        'agc=${options.autoGainControl}, '
        'hp=${options.highPassFilter}, '
        'voiceIsolation=${options.voiceIsolation}, '
        'typing=${options.typingNoiseDetection}';
  }

  /// Atualiza a efetiva e notifica a UI (sem duplicar o evento).
  void _setEffectiveQuality(RtcScreenShareQuality quality) {
    if (_screenShareEffective == quality) return;
    _screenShareEffective = quality;
    _emitEvent(ScreenShareEffectiveQualityChangedEvent(effective: quality));
  }

  /// Passo adaptativo (spec V1): avalia os stats do sender do screen share
  /// a cada amostra do timer de latência e ajusta a efetiva sem derrubar
  /// a publicação. Best-effort: qualquer falha só adia a próxima amostra —
  /// nunca reconecta, nunca corta áudio.
  ///
  /// Concorrência: cada `await` revalida época, sala e track ([epoch] +
  /// [_isCurrentScreenShare]) — troca manual, stop ou teardown no meio do
  /// voo invalida a amostra em vez de aplicar valor stale por cima.
  Future<void> _adaptScreenShareQuality(Room room, int generation) async {
    final epoch = _screenShareEpoch;
    if (_disposed ||
        generation != _latencyGeneration ||
        !identical(_room, room)) {
      return;
    }
    final track = _activeScreenShareTrack(room);
    final sender = track?.sender;
    final baseline = _screenShareEncodingBaseline;
    if (track == null ||
        sender == null ||
        baseline == null ||
        baseline.isEmpty) {
      return;
    }
    final sample = await _collectAdaptiveSample(sender);
    if (!_isCurrentScreenShare(room, generation, epoch, track)) return;
    final proposed = _adaptiveController.propose(sample);
    if (proposed == null || proposed == _screenShareEffective) return;
    try {
      await _applyScreenShareQuality(sender, baseline, proposed);
    } catch (error) {
      // Passo automático recusado: mantém a efetiva atual e tenta de novo
      // na próxima amostra. Sem fallback para Auto — subiria o bitrate
      // justamente em rede ruim.
      debugPrint(
        '[rtc] adaptação do share falhou '
        '(mantida $_screenShareEffective): $error',
      );
      return;
    }
    if (!_isCurrentScreenShare(room, generation, epoch, track)) {
      // Troca manual/stop/teardown durante o apply: o fio já não é nosso —
      // não comita nem emite sobre o estado novo.
      debugPrint('[rtc] adaptação descartada (época $epoch expirada)');
      return;
    }
    _adaptiveController.commit(proposed);
    _statsLog(
      'screen adaptativo: objetivo=${_adaptiveController.target} '
      'efetiva=$proposed',
    );
    _setEffectiveQuality(proposed);
  }

  /// Track de vídeo do share local ativo, ou null sem publicação válida.
  /// (Objeto estável do SDK — serve como identidade entre awaits.)
  LocalVideoTrack? _activeScreenShareTrack(Room room) {
    final localParticipant = room.localParticipant;
    if (localParticipant == null || !localParticipant.isScreenShareEnabled()) {
      return null;
    }
    final track = localParticipant
        .getTrackPublicationBySource(TrackSource.screenShareVideo)
        ?.track;
    return track is LocalVideoTrack ? track : null;
  }

  /// Vale para o passo adaptativo: mesma sala, generation e época, e a
  /// MESMA track (troca manual/stop/teardown invalida a amostra em voo).
  /// Não compara o sender: o getter pode devolver um wrapper novo por
  /// chamada conforme o backend, mas a track Dart é estável.
  bool _isCurrentScreenShare(
    Room room,
    int generation,
    int epoch,
    LocalVideoTrack track,
  ) {
    if (_disposed ||
        generation != _latencyGeneration ||
        epoch != _screenShareEpoch ||
        !identical(_room, room)) {
      return false;
    }
    return identical(_activeScreenShareTrack(room), track);
  }

  /// Coleta a amostra de rede do passo adaptativo: RTT do último poll da
  /// conexão + limitação/perda dos stats do sender (best-effort, null
  /// quando indisponível — o controlador ignora a dimensão).
  Future<ScreenShareNetworkSample> _collectAdaptiveSample(
    rtc.RTCRtpSender sender,
  ) async {
    String? limitation;
    double? loss;
    try {
      final stats = await sender.getStats();
      limitation = adaptiveLimitationFromStats(stats);
      loss = adaptiveLossFromStats(stats);
    } catch (error) {
      debugPrint('[rtc] stats adaptativos indisponíveis: $error');
    }
    return ScreenShareNetworkSample(
      rttMs: _lastLatencyMs,
      lossFraction: loss,
      limitationReason: limitation,
    );
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
        // Opt-in não sobrevive à saída: evita liberar áudio stale se a
        // mesma identity voltar a compartilhar na próxima sala.
        _watchedScreenAudioIds.remove(id);
        if (_participantsById.remove(id) != null) {
          _emitEvent(ParticipantLeftEvent(participantId: id));
          _emitSnapshot();
        }
      }),
      // Sinais de som de UI (ADR-0001): data messages no tópico
      // `voice-sound/v1` viram VoiceSoundSignalEvent; o controller decide
      // se toca (eco, cooldown e Deafen ficam com ele).
      room.events.on<DataReceivedEvent>(_handleVoiceSoundSignal),
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
        unawaited(_applyInputVolumeToMicrophone());
        _scheduleVolumeApply();
      }),
      // Publicação/despublicação de tracks (remoto e local) e mute/unmute:
      // re-deriva o estado de mic do participante afetado e emite
      // MicEnabledChangedEvent se mudou.
      room.events.on<TrackPublishedEvent>((e) {
        // Opt-in de transmissão no nível da PUBLICAÇÃO (antes do subscribe
        // existir): `screenShareAudio` não assistido já nasce desabilitado
        // no servidor — sem corrida com o `start()` do SDK e sem destruir
        // a track. Local nunca entra no opt-in. A voz (microfone) segue
        // tocando normalmente ao entrar no canal.
        final publication = e.publication;
        if (publication.source == TrackSource.screenShareAudio &&
            e.participant.identity != room.localParticipant?.identity &&
            !_watchedScreenAudioIds.contains(e.participant.identity)) {
          unawaited(publication.disable().catchError((Object err, StackTrace st) {
            _rtcError(
              'rtc screen audio disable no publish falhou '
              'para ${e.participant.identity}',
              err,
              st,
            );
          }));
        }
        _syncParticipant(e.participant);
        _emitSnapshot();
      }),
      room.events.on<TrackSubscribedEvent>((e) {
        // Ensurdecer é uma decisão local. Tracks que chegam depois do clique
        // também não podem começar a tocar.
        if (!_remoteAudioEnabled && e.track is RemoteAudioTrack) {
          unawaited((e.track as RemoteAudioTrack).stop());
        } else if (e.track is RemoteAudioTrack) {
          // Opt-in de transmissão: operado na PUBLICAÇÃO (`disable()`), que
          // é idempotente em qualquer momento do ciclo de vida — nunca
          // `stop()` na track (no nativo encerra a MediaStreamTrack de vez
          // e o `start()` posterior não revive; além disso este evento chega
          // antes do `start()` do SDK, quando `stop()` é no-op garantido).
          final isScreenShareAudio =
              e.publication.source == TrackSource.screenShareAudio;
          if (isScreenShareAudio &&
              !_watchedScreenAudioIds.contains(e.participant.identity)) {
            unawaited(e.publication.disable().catchError((
              Object err,
              StackTrace st,
            ) {
              _rtcError(
                'rtc screen audio disable no subscribe falhou '
                'para ${e.participant.identity}',
                err,
                st,
              );
            }));
          } else {
            // Nova faixa remota (voz ou áudio de screen share assistido):
            // aplica o ganho efetivo pendente (saída × fonte) — cada fonte
            // só toca nas suas.
            final track = e.track as RemoteAudioTrack;
          final gain = effectiveVolumeGain(
            _outputGain,
            _sourceGain(
              e.participant.identity,
              e.publication.source == TrackSource.screenShareAudio,
            ),
          );
          unawaited(
            _applyTrackVolume(track, gain).catchError((Object err) {
              debugPrint(
                '[rtc] volume falhou para ${e.participant.identity}: $err',
              );
            }),
          );
          }
        }
        _syncParticipant(e.participant);
        _emitSnapshot();
      }),
      room.events.on<TrackUnpublishedEvent>((e) {
        _syncParticipant(e.participant);
        _emitSnapshot();
      }),
      room.events.on<LocalTrackPublishedEvent>((e) {
        if (e.publication.track is LocalAudioTrack &&
            e.publication.source == TrackSource.microphone) {
          unawaited(_applyInputVolumeToMicrophone());
        }
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
        if (e.participant is LocalParticipant &&
            e.publication.source == TrackSource.microphone) {
          unawaited(_applyInputVolumeToMicrophone());
        }
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

      final room = Room(roomOptions: _effectiveRoomOptions());
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
        // Reaplica a preferência global antes de notificar a UI. Câmera/share
        // locais continuam desligados após a reconexão.
        await localParticipant.setMicrophoneEnabled(
          _microphoneEnabled,
          audioCaptureOptions: _currentMicrophoneCaptureOptions(room),
        );
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
      _startLatencyMonitor(room);
      _scheduleVolumeApply();
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
    _rtcDebug(
      'rtc cleanup iniciado '
      '(hasRoom=${_room != null}, url=${_livekitUrl ?? '-'})',
    );
    _tokenGenerator = null;
    _livekitUrl = null;
    _screenShareQuality = RtcScreenShareQuality.auto;
    _screenShareEffective = RtcScreenShareQuality.auto;
    _adaptiveController.setTarget(RtcScreenShareQuality.auto);
    _bumpScreenShareEpoch();
    _screenShareEncodingBaseline = null;
    await _teardownRoom();
    _rtcDebug('rtc cleanup concluído');
  }

  AudioCaptureOptions _microphoneCaptureOptions({
    required AudioCaptureOptions base,
    String? deviceId,
  }) => _buildMicrophoneCaptureOptions(
    noiseSuppressionMode: _effectiveNoiseSuppressionMode,
    deviceId: deviceId,
    defaults: base,
  );

  AudioCaptureOptions _currentMicrophoneCaptureOptions([Room? room]) {
    final base =
        room?.roomOptions.defaultAudioCaptureOptions ??
        _roomOptions.defaultAudioCaptureOptions;
    return _microphoneCaptureOptions(
      base: base,
      deviceId: _selectedAudioInputId ?? base.deviceId,
    );
  }

  AudioCaptureOptions _syncRoomAudioCaptureOptions(Room room) {
    final options = _currentMicrophoneCaptureOptions(room);
    // O SDK atual só expõe o default mutável pela engine interna; mantemos o
    // uso isolado aqui, igual ao acesso de stats da conexão.
    // ignore: invalid_use_of_internal_member
    room.engine.roomOptions = room.roomOptions.copyWith(
      defaultAudioCaptureOptions: options,
    );
    return options;
  }

  RoomOptions _effectiveRoomOptions() {
    var options = _roomOptions.copyWith(
      defaultAudioCaptureOptions: _microphoneCaptureOptions(
        base: _roomOptions.defaultAudioCaptureOptions,
        deviceId: _selectedAudioInputId,
      ),
    );
    final audioInputId = _selectedAudioInputId;
    if (audioInputId != null) {
      options = options.copyWith(
        defaultAudioCaptureOptions: options.defaultAudioCaptureOptions.copyWith(
          deviceId: audioInputId,
        ),
      );
    }
    final audioOutputId = _selectedAudioOutputId;
    if (audioOutputId != null) {
      options = options.copyWith(
        defaultAudioOutputOptions: options.defaultAudioOutputOptions.copyWith(
          deviceId: audioOutputId,
        ),
      );
    }
    return options;
  }

  MediaDevice? _resolveAudioDevice(
    List<MediaDevice> devices,
    String? requestedId,
  ) {
    if (devices.isEmpty) return null;
    if (requestedId == null) return devices.first;
    for (final device in devices) {
      if (device.deviceId == requestedId) return device;
    }
    return null;
  }

  CameraCaptureOptions _cameraCaptureOptions({String? deviceId}) {
    final selectedDeviceId = deviceId ?? _selectedCameraId;
    final defaults = _roomOptions.defaultCameraCaptureOptions;
    if (selectedDeviceId == null) return defaults;
    return defaults.copyWith(deviceId: selectedDeviceId);
  }

  Future<T> _runCameraPreviewOperation<T>(Future<T> Function() operation) {
    final run = _cameraPreviewOperation.then((_) => operation());
    // A fila deve sobreviver a uma falha de permissão: a próxima tentativa do
    // usuário (ou o fechamento do sheet) ainda precisa executar.
    _cameraPreviewOperation = run.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return run;
  }

  bool _isCurrentCameraPreviewGeneration(int generation) {
    return !_disposed && generation == _cameraPreviewGeneration;
  }

  Future<void> _discardCameraPreviewTrack(LocalVideoTrack track) async {
    try {
      // LocalVideoTrack.stop também faz dispose da MediaStream; é isso que
      // alcança trackDispose/streamDispose no plugin e libera o V4L2.
      await track.stop();
    } catch (error) {
      debugPrint('[rtc] falha ao descartar preview da câmera: $error');
    }
  }

  Future<void> _stopCameraPreviewUnlocked() async {
    final preview = _cameraPreviewTrack;
    _cameraPreviewTrack = null;
    if (preview == null) return;
    await _discardCameraPreviewTrack(preview);
  }

  /// Descarta o [Room] atual SEM mexer em [_tokenGenerator]/[_livekitUrl] —
  /// o loop de reconexão usa este teardown para não perder a sessão. AWAIT
  /// obrigatório: o [dispose] nativo é o que garante a liberação dos
  /// recursos WebRTC — retornar antes deixaria dois [Room]/PeerConnection
  /// vivos num reconnect rápido.
  Future<void> _teardownRoom() async {
    _stopLatencyMonitor();
    // O share morre com a sala: congela a adaptação e volta a efetiva ao
    // pendente (teto da próxima publicação).
    _screenShareEffective = _screenShareQuality;
    _adaptiveController.setTarget(_screenShareQuality);
    _bumpScreenShareEpoch();
    // Pode ser chamado tanto no disconnect quanto na reconexão automática.
    // Em ambos os casos, preview local não pode sobreviver à room antiga.
    await stopCameraPreview();
    // Invalida publicações de áudio de sistema pendentes DESTA sala: a sala
    // nova (reconexão/join) não pode herdar no-op silencioso nem ver a fila
    // da sala antiga (review codex — fix por época, não flag global).
    _systemAudioPublishEpoch++;
    _pendingSystemAudioPublish = null;
    // Sala nova = opt-in recomeça do zero (espelho do controller, que reseta
    // `watchedPublicationIds` no leave/reconnect): sem isso, uma identity
    // liberada na sala antiga teria o áudio auto-liberado na sala nova.
    _watchedScreenAudioIds.clear();
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

  void _startLatencyMonitor(Room room) {
    _stopLatencyMonitor(emitUnavailable: false);
    final generation = ++_latencyGeneration;
    unawaited(_pollConnectionLatency(room, generation));
    _latencyTimer = Timer.periodic(_latencyPollInterval, (_) {
      unawaited(_pollConnectionLatency(room, generation));
    });
  }

  void _stopLatencyMonitor({bool emitUnavailable = true}) {
    _latencyGeneration++;
    _latencyTimer?.cancel();
    _latencyTimer = null;
    _latencyPollInFlight = false;
    if (emitUnavailable && _lastLatencyMs != null) {
      _lastLatencyMs = null;
      _emitEvent(const ConnectionLatencyChangedEvent(latencyMs: null));
    }
  }

  Future<void> _pollConnectionLatency(Room room, int generation) async {
    if (_latencyPollInFlight ||
        _disposed ||
        generation != _latencyGeneration ||
        !identical(_room, room)) {
      return;
    }
    _latencyPollInFlight = true;
    try {
      // O SDK ainda não expõe stats da conexão na API pública. `engine` e
      // `primary` apontam para o PeerConnection escolhido pelo próprio
      // LiveKit; o fork está fixado no projeto e este acesso fica isolado aqui.
      // ignore: invalid_use_of_internal_member
      final peerConnection = room.engine.primary?.pc;
      if (peerConnection == null) return;
      final latencyMs = connectionLatencyMsFromStats(
        await peerConnection.getStats(),
      );
      if (_disposed ||
          generation != _latencyGeneration ||
          !identical(_room, room)) {
        return;
      }
      if (latencyMs != null && latencyMs != _lastLatencyMs) {
        _lastLatencyMs = latencyMs;
        _emitEvent(ConnectionLatencyChangedEvent(latencyMs: latencyMs));
      }
      // A adaptação do screen share reaproveita este timer (~5 s, spec V1).
      await _adaptScreenShareQuality(room, generation);
    } catch (error) {
      // Stats podem não existir nos primeiros instantes da negociação. A
      // próxima coleta tenta novamente sem afetar áudio ou vídeo.
      debugPrint('[rtc] medição de latência indisponível: $error');
    } finally {
      if (generation == _latencyGeneration) {
        _latencyPollInFlight = false;
      }
    }
  }
}

/// Extrai o RTT do par ICE selecionado de um relatório WebRTC.
///
/// O WebRTC define `currentRoundTripTime` em segundos; a UI trabalha com
/// milissegundos. Alguns backends não incluem o relatório `transport`, então
/// o fallback aceita o par marcado como `selected` ou como
/// `nominated+succeeded`.
@visibleForTesting
int? connectionLatencyMsFromStats(Iterable<rtc.StatsReport> reports) {
  final all = reports.toList(growable: false);
  final selectedPairIds = <String>{
    for (final report in all)
      if (report.type == 'transport' &&
          report.values['selectedCandidatePairId'] is String)
        report.values['selectedCandidatePairId'] as String,
  };

  rtc.StatsReport? selectedPair;
  for (final report in all) {
    if (report.type != 'candidate-pair') continue;
    if (selectedPairIds.contains(report.id)) {
      selectedPair = report;
      break;
    }
    final values = report.values;
    if (selectedPair == null && values['selected'] == true) {
      selectedPair = report;
    } else if (selectedPair == null &&
        values['nominated'] == true &&
        values['state'] == 'succeeded') {
      selectedPair = report;
    }
  }

  var seconds = _statNumber(selectedPair?.values['currentRoundTripTime']);
  if (seconds == null) {
    for (final report in all) {
      if (report.type != 'remote-inbound-rtp') continue;
      seconds = _statNumber(report.values['roundTripTime']);
      if (seconds != null) break;
    }
  }
  if (seconds == null || !seconds.isFinite || seconds < 0) return null;
  return (seconds * 1000).round().clamp(0, 60000).toInt();
}

double? _statNumber(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// Extrai o `qualityLimitationReason` mais relevante dos stats do sender do
/// screen share (`bandwidth` > `cpu` > demais). `none`/vazio/ausente vira
/// null (sem limitação). Função pura, testável isoladamente.
@visibleForTesting
String? adaptiveLimitationFromStats(Iterable<rtc.StatsReport> reports) {
  String? found;
  for (final report in reports) {
    if (report.type != 'outbound-rtp') continue;
    final raw = report.values['qualityLimitationReason'];
    if (raw is! String) continue;
    final limitation = raw.trim().toLowerCase();
    if (limitation.isEmpty || limitation == 'none') continue;
    if (limitation == 'bandwidth') return 'bandwidth';
    found ??= limitation;
  }
  return found;
}

/// Fração de perda `0.0..1.0` a partir do `fractionLost` do
/// `remote-inbound-rtp` (0..1 ou 0..255 conforme o backend). Só essa fonte:
/// o `fractionLost` do RTCP RR já é perda POR INTERVALO (desde o último RR),
/// enquanto os contadores cumulativos (`packetsLost/packetsSent`) mascaram
/// bursts recentes sob histórico antigo e subestimam (`lost/(lost+sent)`).
/// Null quando indisponível — o controlador ignora a dimensão.
/// Função pura, testável isoladamente.
@visibleForTesting
double? adaptiveLossFromStats(Iterable<rtc.StatsReport> reports) {
  for (final report in reports) {
    if (report.type != 'remote-inbound-rtp') continue;
    final fraction = _statNumber(report.values['fractionLost']);
    if (fraction == null) continue;
    final normalized = fraction > 1 ? fraction / 256 : fraction;
    if (normalized.isFinite && normalized >= 0) {
      return normalized.clamp(0.0, 1.0);
    }
  }
  return null;
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
    maxFramerate: 60,
    maxBitrate: 8000000,
  ),
  RtcScreenShareQuality.q1080p60 => const ScreenShareQualityProfile(
    scaleResolutionDownBy: 1,
    maxFramerate: 60,
    maxBitrate: 8000000,
  ),
  RtcScreenShareQuality.q720p60 => const ScreenShareQualityProfile(
    scaleResolutionDownBy: 1.5,
    maxFramerate: 60,
    maxBitrate: 3500000,
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
  RtcScreenShareQuality.q480p30 => const ScreenShareQualityProfile(
    scaleResolutionDownBy: 2.25,
    maxFramerate: 30,
    maxBitrate: 1200000,
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

@visibleForTesting
AudioCaptureOptions systemAudioCaptureOptionsFor(String deviceId) =>
    AudioCaptureOptions(
      deviceId: deviceId,
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
      highPassFilter: false,
      voiceIsolation: false,
      typingNoiseDetection: false,
    );

/// Transforma cada camada a partir do baseline do sender, preservando RID e
/// active. A proporção de bitrate/resolução entre as camadas simulcast
/// também é preservada.
///
/// Payload MÍNIMO de propósito: só `maxBitrate`, `maxFramerate` e
/// `scaleResolutionDownBy` são enviados; todo o resto vai null e o C++
/// (`updateRtpParameters`) conserva o valor nativo corrente. Ecoar o
/// baseline inteiro faz o libwebrtc recusar (`set_parameters` retorna
/// false): o SSRC do cache pode estar stale (`webrtc_interface`: "can't be
/// changed between getParameters/setParameters"), e campos como
/// `scalabilityMode: ''` (string vazia do roundtrip nativo→Dart) são
/// inválidos ao serem escritos de volta. Omitidos, só os 3 campos de
/// qualidade mudam.
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
      // Resto null de propósito (ver doc acima): o C++ conserva o valor
      // nativo corrente em vez de reescrever o echo do cache. Atenção:
      // `numTemporalLayers` tem default `= 1` no construtor, por isso o
      // null aqui é EXPLÍCITO — omitir o argumento reenviaria 1.
      numTemporalLayers: null,
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
