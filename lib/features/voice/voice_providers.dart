import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/native/native_media_backend.dart';
import '../../core/rtc/media_devices_provider.dart';
import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';
import '../../shared/models/voice.dart';
import '../servers/servers_providers.dart';
import 'voice_audio_processing_provider.dart';
import 'voice_controls_provider.dart';

/// Estado da sessão de voz de um canal.
enum VoiceSessionStatus { idle, connecting, connected, error }

/// Fonte visual destacada quando uma pessoa publica câmera e tela ao mesmo
/// tempo. O grid trata as duas publicações como tiles irmãos.
enum VoiceSpotlightSource { camera, screen }

/// Sentinel de "não fornecido": default dos parâmetros nullable de
/// [VoiceState.copyWith]. Omitir o parâmetro mantém o valor atual; passar
/// `null` EXPLICITAMENTE limpa o campo (nullable limpável). Padrão mínimo
/// para limpar [VoiceState.spotlightParticipantId] e
/// [VoiceState.selectedCameraId] — o projeto não tinha sentinel; documentado
/// aqui.
const Object _unset = Object();

/// Estado derivado do [RtcService] para o canal selecionado: status da
/// sessão, participantes ordenados (local primeiro, depois por nome), estado
/// do microfone, câmera e compartilhamento de tela LOCAIS (para a barra de
/// controles), o tile em destaque (spotlight), o spotlight automático do
/// share, o banner de reconexão e o cache de câmeras do sheet de settings.
class VoiceState {
  const VoiceState({
    this.status = VoiceSessionStatus.idle,
    this.errorMessage,
    this.participants = const [],
    this.isMicrophoneEnabled = false,
    this.isCameraEnabled = false,
    this.isScreenSharing = false,
    this.isSystemAudioEnabled = false,
    this.isDeafened = false,
    this.isReconnecting = false,
    this.isAudioBlocked = false,
    this.latencyMs,
    this.autoSpotlightActive = false,
    this.savedSpotlightParticipantId,
    this.spotlightParticipantId,
    this.spotlightSource,
    this.watchedPublicationIds = const {},
    this.filmstripVisible = true,
    this.isFullscreen = false,
    this.cameraDevices = const [],
    this.selectedCameraId,
    this.screenShareQuality = RtcScreenShareQuality.auto,
    this.screenShareEffectiveQuality,
  });

  final VoiceSessionStatus status;

  /// Mensagem amigável quando [status] é [VoiceSessionStatus.error].
  final String? errorMessage;

  /// Participantes da sala, local primeiro (ver [VoiceController._sort]).
  final List<RtcParticipant> participants;

  /// Se o microfone LOCAL está habilitado (espelho do botão mute; o
  /// participante local também aparece em [participants] com o mesmo
  /// estado, sincronizado pelos eventos do serviço).
  final bool isMicrophoneEnabled;

  /// Se a câmera LOCAL está habilitada (espelho do botão de câmera; o
  /// [CameraEnabledChangedEvent] do participante local reconcilia).
  final bool isCameraEnabled;

  /// Se a tela LOCAL está sendo compartilhada (espelho do botão de share; o
  /// [ScreenShareEnabledChangedEvent] do participante local reconcilia).
  final bool isScreenSharing;

  /// Se o áudio de sistema LOCAL está sendo transmitido agora (espelho do
  /// [SystemAudioEnabledChangedEvent] do participante local reconcilia).
  final bool isSystemAudioEnabled;

  /// Áudio remoto desligado localmente. É o espelho da preferência global de
  /// ensurdecer enquanto esta sessão estiver conectada.
  final bool isDeafened;

  /// Banner \"Reconectando…\": reconexão automática do serviço em andamento
  /// ([ReconnectingEvent] → [ReconnectedEvent]). A sessão continua
  /// `connected` — o banner é o ÚNICO efeito visível durante a reconexão.
  final bool isReconnecting;

  /// Playback de áudio remoto BLOQUEADO pelo browser (autoplay policy no
  /// web — [AudioPlaybackBlockedEvent]/[AudioPlaybackResumedEvent]). A UI
  /// mostra o banner tocável \"Áudio bloqueado — toque para ativar\" que
  /// chama [VoiceController.resumeAudio]. Desktop nunca liga.
  final bool isAudioBlocked;

  /// RTT atual até o servidor de voz. Nulo enquanto o WebRTC ainda não
  /// escolheu um par ICE ou durante uma reconexão.
  final int? latencyMs;

  /// Destaque automático do share em vigor (PRD §25): o 1º sharer vira
  /// spotlight e o estado anterior fica salvo em
  /// [savedSpotlightParticipantId]. Desligado ao terminar o share ou por
  /// dispensa manual do usuário (toque no sharer em destaque).
  final bool autoSpotlightActive;

  /// Spotlight ANTES do share automático começar (id manual ou null = grid)
  /// — restaurado quando ninguém mais compartilha. Limpável (sentinel).
  final String? savedSpotlightParticipantId;

  /// Id do participante em destaque (spotlight); null = grid. O snapshot de
  /// participantes revalida: destaque de tile sem câmera nem tela/saído é
  /// limpo.
  final String? spotlightParticipantId;

  /// Publicação destacada do participante. Nulo quando o painel está em
  /// grid; mantido separado do id para câmera e tela poderem coexistir.
  final VoiceSpotlightSource? spotlightSource;

  /// Publicações remotas que o usuário escolheu assistir (opt-in de vídeo).
  ///
  /// Chave `participantId:source` ([VoiceController.watchKey]). Vazio = nada
  /// assinado: tiles remotos mostram avatar + LIVE + "Assistir". O local
  /// nunca entra aqui (sempre renderiza). Resetado a cada sessão.
  final Set<String> watchedPublicationIds;

  /// Filmstrip de miniaturas visível (spotlight). Falso = palco imersivo.
  final bool filmstripVisible;

  /// Palco em fullscreen (janela cheia via window_manager, Linux/Windows).
  final bool isFullscreen;

  /// Cache da lista de câmeras do dispositivo (sheet de settings).
  final List<RtcVideoDevice> cameraDevices;

  /// Última seleção de câmera do sheet, persistida durante a sessão e usada
  /// tanto pelo preview local quanto pela próxima publicação da câmera.
  final String? selectedCameraId;

  /// Perfil de qualidade de PUBLICAÇÃO do compartilhamento local (default
  /// `auto`). Persistido só na sessão — resetado a cada join.
  final RtcScreenShareQuality screenShareQuality;

  /// Qualidade EFETIVA do share local decidida pelo controlador adaptativo.
  /// Null = igual ao objetivo ([screenShareQuality]) — a UI mostra só o
  /// objetivo; quando diferem, mostra `objetivo · adaptado em efetivo`.
  final RtcScreenShareQuality? screenShareEffectiveQuality;

  VoiceState copyWith({
    VoiceSessionStatus? status,
    Object? errorMessage = _unset,
    List<RtcParticipant>? participants,
    bool? isMicrophoneEnabled,
    bool? isCameraEnabled,
    bool? isScreenSharing,
    bool? isSystemAudioEnabled,
    bool? isDeafened,
    bool? isReconnecting,
    bool? isAudioBlocked,
    Object? latencyMs = _unset,
    bool? autoSpotlightActive,
    Object? savedSpotlightParticipantId = _unset,
    Object? spotlightParticipantId = _unset,
    Object? spotlightSource = _unset,
    Set<String>? watchedPublicationIds,
    bool? filmstripVisible,
    bool? isFullscreen,
    List<RtcVideoDevice>? cameraDevices,
    Object? selectedCameraId = _unset,
    RtcScreenShareQuality? screenShareQuality,
    Object? screenShareEffectiveQuality = _unset,
  }) {
    return VoiceState(
      status: status ?? this.status,
      // Sentinel: errorMessage é LIMPÁVEL — `copyWith(errorMessage: null)`
      // deve zerar a mensagem (o padrão `??` manteria a anterior, fazendo o
      // SnackBar de uma falha antiga nunca mais reaparecer).
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      participants: participants ?? this.participants,
      isMicrophoneEnabled: isMicrophoneEnabled ?? this.isMicrophoneEnabled,
      isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      isSystemAudioEnabled: isSystemAudioEnabled ?? this.isSystemAudioEnabled,
      isDeafened: isDeafened ?? this.isDeafened,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      isAudioBlocked: isAudioBlocked ?? this.isAudioBlocked,
      latencyMs: identical(latencyMs, _unset)
          ? this.latencyMs
          : latencyMs as int?,
      autoSpotlightActive: autoSpotlightActive ?? this.autoSpotlightActive,
      // Sentinel: savedSpotlightParticipantId é LIMPÁVEL — restaurar para
      // grid (null) deve funcionar; o padrão `??` manteria o id salvo.
      savedSpotlightParticipantId:
          identical(savedSpotlightParticipantId, _unset)
          ? this.savedSpotlightParticipantId
          : savedSpotlightParticipantId as String?,
      spotlightParticipantId: identical(spotlightParticipantId, _unset)
          ? this.spotlightParticipantId
          : spotlightParticipantId as String?,
      spotlightSource: identical(spotlightSource, _unset)
          ? this.spotlightSource
          : spotlightSource as VoiceSpotlightSource?,
      watchedPublicationIds:
          watchedPublicationIds ?? this.watchedPublicationIds,
      filmstripVisible: filmstripVisible ?? this.filmstripVisible,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      cameraDevices: cameraDevices ?? this.cameraDevices,
      selectedCameraId: identical(selectedCameraId, _unset)
          ? this.selectedCameraId
          : selectedCameraId as String?,
      screenShareQuality: screenShareQuality ?? this.screenShareQuality,
      screenShareEffectiveQuality:
          identical(screenShareEffectiveQuality, _unset)
          ? this.screenShareEffectiveQuality
          : screenShareEffectiveQuality as RtcScreenShareQuality?,
    );
  }
}

/// Sessão de voz de um canal (`autoDispose`): entrar/sair do canal,
/// mute/unmute, câmera/spotlight e espelho dos participantes do [RtcService].
///
/// Ciclo de vida:
/// - [join]: `POST /servers/:id/channels/:id/join` (token emitido pelo
///   backend) + [RtcService.connect]. Se o connect falhar (token expirado
///   na janela POST→handshake, servidor fora), refaz o `/join` UMA vez com
///   token fresco e reconecta — é o papel do `tokenGenerator` do contrato,
///   já que o SDK de mídia 2.11.0 não tem suporte nativo a ele.
/// - [leave]: [RtcService.disconnect] e volta para `idle`.
/// - Troca de canal/fechamento da view: o `autoDispose` descarta o
///   provider e o `ref.onDispose` desconecta — o usuário nunca fica
///   "preso" numa sala depois de navegar para outro canal.
///   Exceção: navegar para um canal de TEXTO mantém `_activeVoiceChannelId`
///   no shell, que segue observando o provider — a sessão persiste e o
///   shell pausa só a câmera/tela local (ver `_pauseLocalVideoOnTextView`).
/// - Queda da sala por conta própria: [DisconnectedEvent] volta para
///   `idle` (o serviço já limpou o estado interno).
class VoiceController
    extends
        AutoDisposeFamilyNotifier<
          VoiceState,
          ({String serverId, String channelId})
        > {
  StreamSubscription<List<RtcParticipant>>? _participantsSub;
  StreamSubscription<RtcEvent>? _eventsSub;
  bool _disposed = false;

  /// Geração do join em voo: [leave] incrementa para cancelar um [join]
  /// anterior ainda aguardando token/conexão. Sem isso, o connect tardio
  /// criaria uma sala órfã depois de o usuário já ter saído.
  int _joinGeneration = 0;

  /// Dedupe de qualidade por participante remoto: o tile reaplica a
  /// qualidade ao assumir/mudar de papel; o mapa evita chamadas repetidas
  /// de [RtcService.setQuality] para o mesmo par (id, qualidade).
  final Map<String, RtcVideoQuality> _lastQuality = {};

  /// Dedupe da qualidade de TELA (mapa separado: câmera e tela do mesmo
  /// participante são publicações independentes — o share em destaque não
  /// rebaixa a câmera em miniatura e vice-versa).
  final Map<String, RtcVideoQuality> _lastScreenQuality = {};

  /// Ids que compartilhavam tela no snapshot ANTERIOR — rastreio do
  /// spotlight automático (PRD §25), por SNAPSHOT (robusto a ordem de
  /// eventos: evento e snapshot chegam separados). Não vai pro estado.
  final Set<String> _lastSharers = {};

  @override
  VoiceState build(({String serverId, String channelId}) arg) {
    // Rebuild (invalidação/retry): o Riverpod reutiliza a instância do
    // notifier — zera o flag e cancela os listeners da build anterior.
    _disposed = false;
    _participantsSub?.cancel();
    _eventsSub?.cancel();

    final rtc = ref.watch(rtcServiceProvider);
    ref.listen<VoiceControlsState>(voiceControlsProvider, (_, controls) {
      if (_disposed || state.status != VoiceSessionStatus.connected) return;
      state = state.copyWith(
        isMicrophoneEnabled: controls.isMicrophoneEnabled,
        isDeafened: controls.isDeafened,
      );
    });
    _participantsSub = rtc.participants.listen(_applyParticipants);
    _eventsSub = rtc.events.listen(_applyEvent);

    ref.onDispose(() {
      _disposed = true;
      _participantsSub?.cancel();
      _eventsSub?.cancel();
      // Sai da sala ao trocar de canal/fechar a view (autoDispose). O
      // `dispose` DEFINITIVO do serviço é do provider de ciclo de vida
      // (rtcServiceProvider); aqui apenas desconecta e limpa a sala.
      unawaited(rtc.disconnect());
    });

    return const VoiceState();
  }

  /// Entra no canal de voz: obtém token no backend e conecta no LiveKit.
  Future<void> join() async {
    final current = state;
    if (current.status == VoiceSessionStatus.connecting) return;
    state = current.copyWith(
      status: VoiceSessionStatus.connecting,
      errorMessage: null,
      // Sessão nova = perfil de screen share default (decisão: por sessão).
      screenShareQuality: RtcScreenShareQuality.auto,
      screenShareEffectiveQuality: null,
      // Entrar começa limpo: nada assistido (opt-in total).
      watchedPublicationIds: const {},
      latencyMs: null,
      selectedCameraId: null,
    );
    try {
      // Segura o provider vivo durante o join assíncrono: no primeiro clique
      // ainda não há nenhum `watch` ativo e o autoDispose descartaria esta
      // instância no frame seguinte — o connect tardio criaria uma sala órfã
      // enquanto a UI já observa uma instância nova em `idle`.
      final keepAlive = ref.keepAlive();
      final generation = ++_joinGeneration;
      try {
        await ref.read(voiceControlsProvider.notifier).ensureInitialized();
        if (_disposed || generation != _joinGeneration) return;
        await ref
            .read(voiceAudioProcessingProvider.notifier)
            .ensureInitialized();
        if (_disposed || generation != _joinGeneration) return;
        await ref.read(audioDevicesProvider.notifier).ensureInitialized();
        if (_disposed || generation != _joinGeneration) return;
        final info = await _freshJoinInfo();
        if (_disposed || generation != _joinGeneration) return;
        await _connect(info, generation);
      } finally {
        keepAlive.close();
      }
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        status: VoiceSessionStatus.error,
        errorMessage: 'Não foi possível entrar no canal de voz.',
      );
    }
  }

  /// Sai do canal de voz e volta para `idle`.
  Future<void> leave() async {
    // Cancela um join em voo: sem isso, o connect tardio criaria uma sala
    // órfã depois de o usuário já ter saído.
    ++_joinGeneration;
    await ref.read(rtcServiceProvider).disconnect();
    await ref.read(voiceControlsProvider.notifier).resetPushToTalkPress();
    if (_disposed) return;
    state = state.copyWith(
      screenShareQuality: RtcScreenShareQuality.auto,
      screenShareEffectiveQuality: null,
    );
    if (_disposed) return;
    // A sala morreu: câmera/share pararam junto e o destaque não faz mais
    // sentido. `_lastQuality` e o rastreio de sharers também são resetados
    // (a sala acabou).
    _lastQuality.clear();
    _lastScreenQuality.clear();
    _lastSharers.clear();
    state = state.copyWith(
      status: VoiceSessionStatus.idle,
      participants: const [],
      isMicrophoneEnabled: false,
      isCameraEnabled: false,
      isScreenSharing: false,
      isSystemAudioEnabled: false,
      isDeafened: false,
      isReconnecting: false,
      isAudioBlocked: false,
      latencyMs: null,
      autoSpotlightActive: false,
      savedSpotlightParticipantId: null,
      spotlightParticipantId: null,
      spotlightSource: null,
      watchedPublicationIds: const {},
      filmstripVisible: true,
      isFullscreen: false,
      selectedCameraId: null,
      errorMessage: null,
    );
  }

  /// Retoma o playback de áudio remoto (web: gesto do usuário desbloqueia a
  /// autoplay policy — chamado pelo toque no banner \"Áudio bloqueado\").
  /// Sem estado otimista: o resultado real chega via
  /// [AudioPlaybackBlockedEvent]/[AudioPlaybackResumedEvent] (o banner só
  /// some quando o serviço confirma). Falha silenciosa = banner permanece.
  Future<void> resumeAudio() async {
    final current = state;
    if (current.status != VoiceSessionStatus.connected) return;
    await ref.read(rtcServiceProvider).resumeAudio();
  }

  /// Liga/desliga a preferência global de microfone. Fora da sala, ela fica
  /// pendente para o próximo connect; dentro, o RTC a aplica imediatamente.
  Future<void> toggleMicrophone() async {
    final changed = await ref
        .read(voiceControlsProvider.notifier)
        .toggleMicrophone();
    if (_disposed) return;
    final controls = ref.read(voiceControlsProvider);
    state = state.copyWith(
      isMicrophoneEnabled: controls.isMicrophoneEnabled,
      isDeafened: controls.isDeafened,
      errorMessage: changed ? null : controls.errorMessage,
    );
  }

  /// Alterna a preferência global de ensurdecer no estilo Discord.
  Future<void> toggleDeafen() async {
    final changed = await ref
        .read(voiceControlsProvider.notifier)
        .toggleDeafen();
    if (_disposed) return;
    final controls = ref.read(voiceControlsProvider);
    state = state.copyWith(
      isMicrophoneEnabled: controls.isMicrophoneEnabled,
      isDeafened: controls.isDeafened,
      errorMessage: changed ? null : controls.errorMessage,
    );
  }

  /// Liga/desliga a câmera local (botão da barra de controles). Espelho do
  /// [toggleMicrophone]: sem otimismo antes do await, erro de permissão não
  /// derruba a sessão e o [CameraEnabledChangedEvent] reconcilia.
  Future<void> toggleCamera() async {
    final current = state;
    if (current.status != VoiceSessionStatus.connected) return;
    final rtc = ref.read(rtcServiceProvider);
    try {
      if (current.isCameraEnabled) {
        await rtc.disableCamera();
      } else {
        await rtc.enableCamera();
      }
    } catch (_) {
      // Falha de permissão/hardware (TrackCreateException no LiveKit):
      // volta ao estado anterior e avisa — a sessão NÃO cai.
      if (_disposed) return;
      state = state.copyWith(
        status: VoiceSessionStatus.connected,
        isCameraEnabled: current.isCameraEnabled,
        errorMessage: 'Não foi possível alternar a câmera.',
      );
      return;
    }
    if (_disposed) return;
    state = state.copyWith(
      isCameraEnabled: !current.isCameraEnabled,
      errorMessage: null,
    );
  }

  /// Publica a tela local (botão de compartilhar; [sourceId] nulo delega a
  /// escolha ao navegador ou ao portal nativo do SO). Espelho do
  /// [toggleCamera]: sem
  /// otimismo antes do await, erro de captura NUNCA derruba a sessão e o
  /// [ScreenShareEnabledChangedEvent] local reconcilia.
  ///
  /// Com [includeSystemAudio] true (default), pede o áudio de sistema junto.
  /// Falha do áudio (sem device monitor no SO) NÃO bloqueia o share: o vídeo
  /// já saiu e o [SystemAudioPublishException] só troca a mensagem — o
  /// [ScreenShareEnabledChangedEvent] confirma o share na sequência.
  ///
  /// [kind] serve só ao aviso best-effort de fallback (regra 4 da SPEC):
  /// Windows + janela sem HWND válido faz o nativo cair no mix geral.
  ///
  /// [quality] one-shot (modal Go Live): vale só para este share, sem alterar
  /// o perfil pendente. Omitido, usa o pendente.
  Future<void> startScreenShare(
    String? sourceId, {
    bool includeSystemAudio = true,
    RtcScreenShareQuality? quality,
    RtcScreenShareSourceKind? kind,
  }) async {
    final current = state;
    if (current.status != VoiceSessionStatus.connected) return;
    if (current.isScreenSharing) {
      return; // já compartilhando (o serviço também no-op)
    }
    final rtc = ref.read(rtcServiceProvider);
    try {
      await rtc.startScreenShare(
        sourceId,
        includeSystemAudio: includeSystemAudio,
        quality: quality,
      );
    } on SystemAudioPublishException {
      // O VÍDEO saiu; só o áudio de sistema falhou (sem device monitor no
      // SO, permissão negada...). Mensagem específica — a sessão fica
      // intacta e o evento de share reconcilia o estado.
      if (_disposed) return;
      state = state.copyWith(
        status: VoiceSessionStatus.connected,
        isScreenSharing: true,
        screenShareQuality: quality ?? rtc.screenShareQuality,
        // Share novo começa na efetiva == objetivo; a adaptação ajusta depois.
        screenShareEffectiveQuality: null,
        errorMessage: 'Compartilhamento iniciado sem áudio de sistema.',
      );
      return;
    } catch (_) {
      // Falha de captura (TrackCreateException/DesktopCapturerSource):
      // volta ao estado anterior (sem otimismo) e avisa — a sessão fica
      // intacta (nenhum disconnect).
      if (_disposed) return;
      state = state.copyWith(
        status: VoiceSessionStatus.connected,
        isScreenSharing: current.isScreenSharing,
        errorMessage: 'Não foi possível iniciar o compartilhamento.',
      );
      return;
    }
    if (_disposed) return;
    // One-shot: o estado reflete o pedido (o pendente ficou intacto).
    // Pendente: o getter já reflete o pós-start (inclui fallback para Auto).
    final effectiveQuality = quality ?? rtc.screenShareQuality;
    final warnings = <String>[];
    if (effectiveQuality != (quality ?? current.screenShareQuality)) {
      warnings.add(
        'Não foi possível aplicar a qualidade escolhida; transmissão mantida em Auto.',
      );
    }
    if (_usedSystemMixFallback(
      kind: kind,
      sourceId: sourceId,
      includeAudio: includeSystemAudio,
    )) {
      warnings.add(
        'Não foi possível isolar o áudio da janela; transmitindo o áudio geral do sistema.',
      );
    }
    state = state.copyWith(
      isScreenSharing: true,
      screenShareQuality: effectiveQuality,
      screenShareEffectiveQuality: null,
      errorMessage: warnings.isEmpty ? null : warnings.join(' '),
    );
  }

  /// Best-effort (regra 4 da SPEC): detecta quando o nativo Windows caiu no
  /// mix geral — janela sem HWND decimal válido (o factory faz
  /// `stoull(source_id)` e usa o mix geral em qualquer falha). No Linux
  /// (system picker) o mix geral no modo janela é o comportamento
  /// documentado no modal — sem aviso.
  bool _usedSystemMixFallback({
    required RtcScreenShareSourceKind? kind,
    required String? sourceId,
    required bool includeAudio,
  }) {
    if (!includeAudio || kind != RtcScreenShareSourceKind.window) return false;
    final usesSystemPicker = ref
        .read(nativeMediaServicesProvider)
        .screenShare
        .capabilities
        .usesSystemPicker;
    if (usesSystemPicker) return false;
    return sourceId == null || int.tryParse(sourceId) == null;
  }

  /// Encerra o compartilhamento de tela local (botão ativo → parar).
  /// Espelho do [startScreenShare]: sem otimismo, falha não derruba a
  /// sessão; o [ScreenShareEnabledChangedEvent] local reconcilia.
  Future<void> stopScreenShare() async {
    final current = state;
    if (current.status != VoiceSessionStatus.connected) return;
    if (!current.isScreenSharing) return;
    final rtc = ref.read(rtcServiceProvider);
    try {
      await rtc.stopScreenShare();
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        status: VoiceSessionStatus.connected,
        isScreenSharing: current.isScreenSharing,
        errorMessage: 'Não foi possível encerrar o compartilhamento.',
      );
      return;
    }
    if (_disposed) return;
    state = state.copyWith(
      isScreenSharing: false,
      screenShareEffectiveQuality: null,
      errorMessage: null,
    );
  }

  /// Alterna o destaque (spotlight) de um participante: toque repetido no
  /// mesmo tile volta ao grid. O snapshot de participantes revalida —
  /// destaque de quem saiu ou desligou a câmera é limpo em [_applyParticipants].
  void toggleSpotlight(String participantId, {VoiceSpotlightSource? source}) {
    final participant = state.participants
        .where((item) => item.id == participantId)
        .firstOrNull;
    final targetSource =
        source ??
        (participant?.isScreenSharing == true
            ? VoiceSpotlightSource.screen
            : VoiceSpotlightSource.camera);
    final selectingCurrent =
        state.spotlightParticipantId == participantId &&
        state.spotlightSource == targetSource;
    if (state.autoSpotlightActive) {
      // QUALQUER seleção manual dispensa o destaque automático do share:
      // o usuário assumiu o controle. Tocar o próprio sharer volta ao grid;
      // tocar outro participante o destaca — em ambos os casos o auto é
      // desligado (senão o snapshot seguinte re-forçaria o sharer e o fim
      // do share restauraria um estado obsoleto, perdendo a seleção manual).
      state = state.copyWith(
        spotlightParticipantId: selectingCurrent ? null : participantId,
        spotlightSource: selectingCurrent ? null : targetSource,
        autoSpotlightActive: false,
        savedSpotlightParticipantId: null,
      );
      return;
    }
    if (selectingCurrent) {
      state = state.copyWith(
        spotlightParticipantId: null,
        spotlightSource: null,
      );
    } else {
      state = state.copyWith(
        spotlightParticipantId: participantId,
        spotlightSource: targetSource,
      );
    }
  }

  /// Chave de uma publicação assistível no [VoiceState.watchedPublicationIds].
  static String watchKey(String participantId, VoiceSpotlightSource source) =>
      '$participantId:${source.name}';

  /// Se o id é o participante local (sempre renderiza o próprio vídeo,
  /// nunca entra no opt-in).
  bool isLocalParticipant(String participantId) =>
      participantId == ref.read(rtcServiceProvider).localParticipantId;

  /// Se a publicação remota deve renderizar vídeo: local sempre, remoto só
  /// após opt-in ([toggleWatch]).
  bool isWatching(String participantId, VoiceSpotlightSource source) {
    if (isLocalParticipant(participantId)) return true;
    return state.watchedPublicationIds.contains(
      watchKey(participantId, source),
    );
  }

  /// Liga/desliga o opt-in de vídeo de uma publicação remota (clique no
  /// tile: assistir/parar). Múltiplos simultâneos permitidos. Local é no-op
  /// (sempre visível). Desligar limpa o dedupe de qualidade da fonte para
  /// religar reaplicar (o tile desmontado = OFF por omissão).
  void toggleWatch(String participantId, VoiceSpotlightSource source) {
    if (isLocalParticipant(participantId)) return;
    final key = watchKey(participantId, source);
    final next = {...state.watchedPublicationIds};
    if (next.contains(key)) {
      next.remove(key);
      if (source == VoiceSpotlightSource.screen) {
        _lastScreenQuality.remove(participantId);
      } else {
        _lastQuality.remove(participantId);
      }
    } else {
      next.add(key);
    }
    state = state.copyWith(watchedPublicationIds: next);
  }

  /// Mostra/oculta a filmstrip de miniaturas (spotlight). Puro flip de UI —
  /// nunca mexe em qualidade (o tile em miniatura segue `low`).
  void toggleFilmstrip() {
    state = state.copyWith(filmstripVisible: !state.filmstripVisible);
  }

  /// Liga/desliga o flag de fullscreen do palco. A chamada real de janela
  /// (`window_manager`, Linux/Windows) vive na UI (best-effort); aqui só o
  /// estado, para a UI expandir o stage e esconder a filmstrip.
  void setFullscreen(bool value) {
    if (state.isFullscreen == value) return;
    state = state.copyWith(isFullscreen: value);
  }

  /// Atualiza o cache de câmeras do sheet de settings. Falha de enumeração
  /// é silenciosa: mantém a lista atual, sem derrubar nada.
  Future<void> refreshCameraDevices() async {
    final current = state;
    if (current.status != VoiceSessionStatus.connected) return;
    final devicesController = ref.read(audioDevicesProvider.notifier);
    final List<RtcVideoDevice> devices;
    try {
      await devicesController.ensureInitialized();
      await devicesController.refresh();
      devices = ref.read(audioDevicesProvider).cameras;
    } catch (_) {
      // Hardware ausente/permissão pendente: mantém o cache anterior.
      return;
    }
    if (_disposed) return;
    // Seleção que saiu da lista nova é limpa (device não existe mais).
    final selectedId = ref.read(audioDevicesProvider).preferredCameraId;
    final selectedStillValid =
        selectedId != null && devices.any((d) => d.id == selectedId);
    state = state.copyWith(
      cameraDevices: devices,
      selectedCameraId: selectedStillValid ? selectedId : null,
    );
  }

  /// Seleciona uma câmera no sheet. O serviço aplica no preview local ou na
  /// track publicada e persiste a escolha para o próximo enableCamera().
  /// Retorna false quando a troca falha, para a UI preservar o radio anterior.
  Future<bool> selectCamera(String deviceId) async {
    final current = state;
    if (current.status != VoiceSessionStatus.connected) return false;
    final changed = await ref
        .read(audioDevicesProvider.notifier)
        .selectCamera(deviceId);
    if (!changed) {
      if (_disposed) return false;
      state = state.copyWith(
        status: VoiceSessionStatus.connected,
        errorMessage: 'Não foi possível trocar a câmera.',
      );
      return false;
    }
    if (_disposed) return false;
    // Só move o radio após o serviço confirmar: uma falha preserva a escolha
    // anterior, que é a única que sabemos estar realmente em uso.
    state = state.copyWith(selectedCameraId: deviceId, errorMessage: null);
    return true;
  }

  /// Define o perfil de qualidade do compartilhamento de tela/janela.
  /// Sem share ativo, fica pendente para o próximo início; com share ativo,
  /// aplica no mesmo sender sem interromper a transmissão.
  Future<void> setScreenShareQuality(RtcScreenShareQuality quality) async {
    final current = state;
    if (current.status != VoiceSessionStatus.connected) return;
    final rtc = ref.read(rtcServiceProvider);
    try {
      await rtc.setScreenShareQuality(quality);
    } catch (e, st) {
      // Sem este log, a causa real (sender null, baseline vazia, recusa
      // nativa) virava o toast genérico sem rastro em disco.
      ref
          .read(appLoggerProvider)
          .e(
            'screen quality falhou (pedido=$quality)',
            error: e,
            stackTrace: st,
            tag: 'voice',
          );
      if (_disposed) return;
      state = state.copyWith(
        status: VoiceSessionStatus.connected,
        errorMessage: 'Não foi possível ajustar a qualidade da transmissão.',
      );
      return;
    }
    if (_disposed) return;
    final effectiveQuality = rtc.screenShareQuality;
    state = state.copyWith(
      screenShareQuality: effectiveQuality,
      // Escolha explícita: a efetiva assume o objetivo na hora.
      screenShareEffectiveQuality: null,
      errorMessage: effectiveQuality == quality
          ? null
          : 'Não foi possível aplicar a qualidade escolhida; transmissão mantida em Auto.',
    );
  }

  /// Aplica a qualidade de recepção de um tile REMOTO conforme o papel
  /// (spotlight→high, grid→medium, miniatura→low). Ignora o participante
  /// local (qualidade local é da publicação) e dedupe chamadas repetidas
  /// para o mesmo par (id, qualidade). Qualidade é best-effort: falha de
  /// [RtcService.setQuality] é silenciosa e nunca vira [VoiceState.errorMessage].
  Future<void> applyTileQuality(
    String participantId,
    RtcVideoQuality quality,
  ) async {
    if (participantId == ref.read(rtcServiceProvider).localParticipantId) {
      return;
    }
    if (_lastQuality[participantId] == quality) return;
    _lastQuality[participantId] = quality;
    try {
      await ref.read(rtcServiceProvider).setQuality(participantId, quality);
    } catch (_) {
      // Best-effort: sem efeito na sessão.
    }
  }

  /// Aplica a qualidade de recepção da TELA remota (spotlight→high,
  /// grid→medium, miniatura→low). Espelho de [applyTileQuality] com dedupe
  /// e no-op próprios — a câmera do mesmo participante não é afetada.
  Future<void> applyTileScreenQuality(
    String participantId,
    RtcVideoQuality quality,
  ) async {
    if (participantId == ref.read(rtcServiceProvider).localParticipantId) {
      return;
    }
    if (_lastScreenQuality[participantId] == quality) return;
    _lastScreenQuality[participantId] = quality;
    try {
      await ref
          .read(rtcServiceProvider)
          .setScreenQuality(participantId, quality);
    } catch (_) {
      // Best-effort: sem efeito na sessão.
    }
  }

  /// `POST /join` → informações para conectar (token de 10m do backend).
  Future<VoiceJoinInfo> _freshJoinInfo() {
    return ref
        .read(serversRepositoryProvider)
        .joinVoice(arg.serverId, arg.channelId);
  }

  /// Conecta no RtcService com o token do [VoiceJoinInfo]; se o connect
  /// falhar, refaz o `/join` uma vez e reconecta com token fresco (janela
  /// POST→handshake pode estourar o token; o `tokenGenerator` do contrato
  /// cobre reconexões futuras do mesmo jeito).
  Future<void> _connect(VoiceJoinInfo info, int generation) async {
    final rtc = ref.read(rtcServiceProvider);
    final log = ref.read(appLoggerProvider);
    // Instância descartada (ou join cancelado por leave) não pode tocar o
    // serviço compartilhado: o connect aqui criaria uma sala órfã.
    if (_disposed || generation != _joinGeneration) return;
    // URL discada (sem token — nunca logar o JWT): sem esta linha, um
    // LiveKit inalcançável vira spinner eterno sem rastro em disco.
    log.d('voice connect iniciando (url=${info.livekitUrl})', tag: 'voice');
    try {
      // Sem timeout próprio: LiveKit filtrado/buraco-negro pendura o
      // `connect` para sempre (status `connecting`, zero logs). 20s cobre
      // handshake intercontinental sem falso-positivo no lab local.
      await rtc
          .connect(info.livekitUrl, info.token, tokenGenerator: _tokenGenerator)
          .timeout(const Duration(seconds: 20));
    } catch (e, st) {
      // Sem este log, falhas de `room.connect` (LiveKit fora, rede, token)
      // viravam a mensagem genérica da UI sem rastro em disco.
      log.e(
        'voice connect falhou (url=${info.livekitUrl}) — tentando com token fresco',
        error: e,
        stackTrace: st,
        tag: 'voice',
      );
      if (_disposed || generation != _joinGeneration) return;
      try {
        final fresh = await _freshJoinInfo();
        if (_disposed || generation != _joinGeneration) return;
        await rtc.connect(
          fresh.livekitUrl,
          fresh.token,
          tokenGenerator: _tokenGenerator,
        );
      } catch (e2, st2) {
        log.e(
          'voice connect falhou (token fresco)',
          error: e2,
          stackTrace: st2,
          tag: 'voice',
        );
        if (_disposed || generation != _joinGeneration) return;
        state = state.copyWith(
          status: VoiceSessionStatus.error,
          errorMessage: 'Não foi possível entrar no canal de voz.',
        );
        return;
      }
    }
    if (_disposed || generation != _joinGeneration) {
      // Conectou após o descarte/cancelamento: desfaz na hora para não
      // deixar uma sala órfã no LiveKit.
      await rtc.disconnect();
      return;
    }
    // O serviço já publicou o mic na preferência global restaurada antes do
    // connect; câmera continua OFF e só liga pelo respectivo botão.
    final controls = ref.read(voiceControlsProvider);
    state = state.copyWith(
      status: VoiceSessionStatus.connected,
      isMicrophoneEnabled: controls.isMicrophoneEnabled,
      isDeafened: controls.isDeafened,
    );
  }

  /// Token fresco para reconexões futuras (o LiveKit 2.11.0 não tem
  /// tokenGenerator nativo — o controller o usa em retries manuais).
  Future<String> _tokenGenerator() => _freshJoinInfo().then((i) => i.token);

  void _applyParticipants(List<RtcParticipant> list) {
    if (_disposed) return;
    final localId = ref.read(rtcServiceProvider).localParticipantId;
    final sorted = _sort(list, localId);

    // O grid é o estado padrão de uma chamada Discord-like. Começar um
    // compartilhamento não pode promover ninguém automaticamente e esconder
    // os demais sharers; o spotlight permanece uma escolha manual.
    _lastSharers
      ..clear()
      ..addAll(
        sorted
            .where((participant) => participant.isScreenSharing)
            .map((participant) => participant.id),
      );
    var next = state.copyWith(participants: sorted);

    // Revalida o destaque: tile sem vídeo não merece spotlight — quem saiu
    // da sala ou desligou a câmera (E não está compartilhando tela) volta o
    // painel para o grid. Sharer SEM câmera continua merecendo destaque (a
    // tela dele é o vídeo — critério ampliado). Também limpa do dedupe de
    // qualidade os ids que saíram (tile desmontado = OFF).
    final spotlightId = next.spotlightParticipantId;
    if (spotlightId != null) {
      final spotlightSource = next.spotlightSource;
      final sourceStillAvailable = sorted.any((participant) {
        if (participant.id != spotlightId) return false;
        return switch (spotlightSource) {
          VoiceSpotlightSource.camera => participant.isCameraEnabled,
          VoiceSpotlightSource.screen => participant.isScreenSharing,
          null => participant.isCameraEnabled || participant.isScreenSharing,
        };
      });
      if (!sourceStillAvailable) {
        next = next.copyWith(
          spotlightParticipantId: null,
          spotlightSource: null,
        );
      }
    }
    final ids = {for (final p in sorted) p.id};
    _lastQuality.removeWhere((id, _) => !ids.contains(id));
    _lastScreenQuality.removeWhere((id, _) => !ids.contains(id));
    // Purga o opt-in: quem saiu da sala ou desligou a fonte volta a
    // avatar+LIVE (sem banda reservada para publicação morta).
    final liveKeys = <String>{
      for (final participant in sorted) ...[
        if (participant.isCameraEnabled)
          watchKey(participant.id, VoiceSpotlightSource.camera),
        if (participant.isScreenSharing)
          watchKey(participant.id, VoiceSpotlightSource.screen),
      ],
    };
    final watched = next.watchedPublicationIds;
    if (!liveKeys.containsAll(watched)) {
      next = next.copyWith(
        watchedPublicationIds: watched.intersection(liveKeys),
      );
    }
    state = next;
  }

  void _applyEvent(RtcEvent event) {
    if (_disposed) return;
    switch (event) {
      case DisconnectedEvent():
        // Sala caiu sozinha (servidor/rede): o serviço já limpou o estado;
        // volta para idle para permitir nova entrada. Câmera/share locais
        // pararam junto e o destaque não faz mais sentido.
        _lastQuality.clear();
        _lastScreenQuality.clear();
        _lastSharers.clear();
        unawaited(
          ref.read(voiceControlsProvider.notifier).resetPushToTalkPress(),
        );
        state = state.copyWith(
          status: VoiceSessionStatus.idle,
          participants: const [],
          isMicrophoneEnabled: false,
          isCameraEnabled: false,
          isScreenSharing: false,
          screenShareQuality: RtcScreenShareQuality.auto,
          screenShareEffectiveQuality: null,
          isSystemAudioEnabled: false,
          isDeafened: false,
          isReconnecting: false,
          isAudioBlocked: false,
          latencyMs: null,
          autoSpotlightActive: false,
          savedSpotlightParticipantId: null,
          spotlightParticipantId: null,
          spotlightSource: null,
          watchedPublicationIds: const {},
          filmstripVisible: true,
          isFullscreen: false,
          selectedCameraId: null,
          errorMessage: null,
        );
      case AudioPlaybackBlockedEvent():
        // Autoplay policy do browser bloqueou o áudio remoto: liga o banner
        // tocável (o gesto chama [resumeAudio]). Só no web; desktop nunca.
        state = state.copyWith(isAudioBlocked: true);
      case AudioPlaybackResumedEvent():
        // startAudio bem-sucedido dentro do gesto: o banner pode sumir.
        state = state.copyWith(isAudioBlocked: false);
      case ConnectionLatencyChangedEvent(:final latencyMs):
        state = state.copyWith(latencyMs: latencyMs);
      case MicEnabledChangedEvent(
        :final participantId,
        :final isMicrophoneEnabled,
      ):
        final localId = ref.read(rtcServiceProvider).localParticipantId;
        if (participantId == localId &&
            state.isMicrophoneEnabled != isMicrophoneEnabled) {
          state = state.copyWith(isMicrophoneEnabled: isMicrophoneEnabled);
        }
      case CameraEnabledChangedEvent(
        :final participantId,
        :final isCameraEnabled,
      ):
        // Espelho exato do mic: só o evento do participante LOCAL toca o
        // botão; remotos aparecem via snapshot de participants.
        final localId = ref.read(rtcServiceProvider).localParticipantId;
        if (participantId == localId &&
            state.isCameraEnabled != isCameraEnabled) {
          state = state.copyWith(isCameraEnabled: isCameraEnabled);
        }
      case ScreenShareEnabledChangedEvent(
        :final participantId,
        :final isScreenSharing,
      ):
        // Espelho exato do mic/câmera: só o evento do participante LOCAL
        // toca o botão de share; remotos aparecem via snapshot.
        final localId = ref.read(rtcServiceProvider).localParticipantId;
        if (participantId == localId &&
            state.isScreenSharing != isScreenSharing) {
          state = state.copyWith(
            isScreenSharing: isScreenSharing,
            // Share parou fora do botão (ex.: fim pelo SO): sem efetiva.
            screenShareEffectiveQuality: isScreenSharing
                ? state.screenShareEffectiveQuality
                : null,
          );
        }
      case ScreenShareEffectiveQualityChangedEvent(:final effective):
        // Passo adaptativo do serviço: reflete a efetiva sem tocar no
        // objetivo. Igual ao objetivo = sem adaptação (null).
        if (state.isScreenSharing) {
          state = state.copyWith(
            screenShareEffectiveQuality: effective == state.screenShareQuality
                ? null
                : effective,
          );
        }
      case SystemAudioEnabledChangedEvent(
        :final participantId,
        :final isSystemAudioEnabled,
      ):
        // Espelho exato do share: só o evento do participante LOCAL toca o
        // estado; remotos aparecem via snapshot de participants.
        final localId = ref.read(rtcServiceProvider).localParticipantId;
        if (participantId == localId &&
            state.isSystemAudioEnabled != isSystemAudioEnabled) {
          state = state.copyWith(isSystemAudioEnabled: isSystemAudioEnabled);
        }
      case ReconnectingEvent():
        // Só o banner: a sessão continua connected — o serviço está tentando
        // restabelecer; NADA aqui pode derrubar para idle/error.
        state = state.copyWith(isReconnecting: true, latencyMs: null);
      case ReconnectedEvent():
        // Sala nova preserva mute/ensurdecer globais; câmera/share locais
        // recomeçam off. Reset também o rastreio de sharers do auto-spotlight.
        _lastQuality.clear();
        _lastScreenQuality.clear();
        _lastSharers.clear();
        final controls = ref.read(voiceControlsProvider);
        state = state.copyWith(
          isReconnecting: false,
          isMicrophoneEnabled: controls.isMicrophoneEnabled,
          isDeafened: controls.isDeafened,
          isCameraEnabled: false,
          isScreenSharing: false,
          screenShareQuality: RtcScreenShareQuality.auto,
          screenShareEffectiveQuality: null,
          isSystemAudioEnabled: false,
          isAudioBlocked: false,
          latencyMs: null,
          autoSpotlightActive: false,
          savedSpotlightParticipantId: null,
          spotlightParticipantId: null,
          spotlightSource: null,
          // Sala nova = ninguém assistido (opt-in recomeça do zero).
          watchedPublicationIds: const {},
        );
      case ParticipantJoinedEvent() ||
          ParticipantLeftEvent() ||
          SpeakingChangedEvent():
        break; // Sem estado derivado: o snapshot de participants cobre.
    }
  }

  /// Participantes ordenados: local primeiro (identidade visual no painel),
  /// depois por nome — ordem estável independente da ordem dos eventos.
  /// Se o local ainda não chegou no snapshot (corrida pós-connect), ordena
  /// só os demais — o próximo snapshot com o local corrige a posição.
  List<RtcParticipant> _sort(List<RtcParticipant> list, String? localId) {
    if (list.length < 2) return list;
    final local = localId == null
        ? const <RtcParticipant>[]
        : list.where((p) => p.id == localId).toList();
    final others = [
      for (final p in list)
        if (p.id != localId) p,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...local, ...others];
  }
}

/// Sessão de voz do canal — `autoDispose.family`: ao trocar de canal (ou
/// sair da view), o provider é descartado e o controller desconecta.
final voiceControllerProvider =
    AutoDisposeNotifierProvider.family<
      VoiceController,
      VoiceState,
      ({String serverId, String channelId})
    >(VoiceController.new);
