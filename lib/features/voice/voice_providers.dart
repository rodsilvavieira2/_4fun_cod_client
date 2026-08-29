import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';
import '../../shared/models/voice.dart';
import '../servers/servers_providers.dart';

/// Estado da sessão de voz de um canal.
enum VoiceSessionStatus { idle, connecting, connected, error }

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
    this.includeSystemAudio = false,
    this.isSystemAudioEnabled = false,
    this.isReconnecting = false,
    this.isAudioBlocked = false,
    this.autoSpotlightActive = false,
    this.savedSpotlightParticipantId,
    this.spotlightParticipantId,
    this.cameraDevices = const [],
    this.selectedCameraId,
    this.screenShareQuality = RtcScreenShareQuality.auto,
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

  /// Preferência do PRÓXIMO compartilhamento: incluir o ÁUDIO DE SISTEMA
  /// (som de jogos/vídeos/música — track de screenShareAudio). Só é lida no
  /// START do share (toggle desabilitado com share ativo); por sessão,
  /// resetada no join (padrão de [screenShareQuality]).
  final bool includeSystemAudio;

  /// Se o áudio de sistema LOCAL está sendo transmitido agora (espelho do
  /// [SystemAudioEnabledChangedEvent] do participante local reconcilia).
  final bool isSystemAudioEnabled;

  /// Banner \"Reconectando…\": reconexão automática do serviço em andamento
  /// ([ReconnectingEvent] → [ReconnectedEvent]). A sessão continua
  /// `connected` — o banner é o ÚNICO efeito visível durante a reconexão.
  final bool isReconnecting;

  /// Playback de áudio remoto BLOQUEADO pelo browser (autoplay policy no
  /// web — [AudioPlaybackBlockedEvent]/[AudioPlaybackResumedEvent]). A UI
  /// mostra o banner tocável \"Áudio bloqueado — toque para ativar\" que
  /// chama [VoiceController.resumeAudio]. Desktop nunca liga.
  final bool isAudioBlocked;

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

  /// Cache da lista de câmeras do dispositivo (sheet de settings).
  final List<RtcVideoDevice> cameraDevices;

  /// Última seleção de câmera do sheet (persistida só no estado; o serviço
  /// não guarda deviceId pendente com a câmera desligada).
  final String? selectedCameraId;

  /// Perfil de qualidade de PUBLICAÇÃO do compartilhamento local (default
  /// `auto`). Persistido só na sessão — resetado a cada join.
  final RtcScreenShareQuality screenShareQuality;

  VoiceState copyWith({
    VoiceSessionStatus? status,
    Object? errorMessage = _unset,
    List<RtcParticipant>? participants,
    bool? isMicrophoneEnabled,
    bool? isCameraEnabled,
    bool? isScreenSharing,
    bool? includeSystemAudio,
    bool? isSystemAudioEnabled,
    bool? isReconnecting,
    bool? isAudioBlocked,
    bool? autoSpotlightActive,
    Object? savedSpotlightParticipantId = _unset,
    Object? spotlightParticipantId = _unset,
    List<RtcVideoDevice>? cameraDevices,
    Object? selectedCameraId = _unset,
    RtcScreenShareQuality? screenShareQuality,
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
      includeSystemAudio: includeSystemAudio ?? this.includeSystemAudio,
      isSystemAudioEnabled: isSystemAudioEnabled ?? this.isSystemAudioEnabled,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      isAudioBlocked: isAudioBlocked ?? this.isAudioBlocked,
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
      cameraDevices: cameraDevices ?? this.cameraDevices,
      selectedCameraId: identical(selectedCameraId, _unset)
          ? this.selectedCameraId
          : selectedCameraId as String?,
      screenShareQuality: screenShareQuality ?? this.screenShareQuality,
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

  /// Dedupe de qualidade por participante remoto: o tile reaplica a
  /// qualidade ao assumir/mudar de papel; o mapa evita chamadas repetidas
  /// de [RtcService.setQuality] para o mesmo par (id, qualidade).
  final Map<String, RtcVideoQuality> _lastQuality = {};

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
      // Preferência de áudio de sistema também é por sessão (padrão do
      // projeto: selectedCameraId idem).
      includeSystemAudio: false,
    );
    try {
      final info = await _freshJoinInfo();
      await _connect(info);
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
    await ref.read(rtcServiceProvider).disconnect();
    if (_disposed) return;
    state = state.copyWith(screenShareQuality: RtcScreenShareQuality.auto);
    if (_disposed) return;
    // A sala morreu: câmera/share pararam junto e o destaque não faz mais
    // sentido. `_lastQuality` e o rastreio de sharers também são resetados
    // (a sala acabou).
    _lastQuality.clear();
    _lastSharers.clear();
    state = state.copyWith(
      status: VoiceSessionStatus.idle,
      participants: const [],
      isMicrophoneEnabled: false,
      isCameraEnabled: false,
      isScreenSharing: false,
      includeSystemAudio: false,
      isSystemAudioEnabled: false,
      isReconnecting: false,
      isAudioBlocked: false,
      autoSpotlightActive: false,
      savedSpotlightParticipantId: null,
      spotlightParticipantId: null,
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

  /// Liga/desliga o microfone local (botão da barra de controles).
  Future<void> toggleMicrophone() async {
    final current = state;
    if (current.status != VoiceSessionStatus.connected) return;
    final rtc = ref.read(rtcServiceProvider);
    try {
      if (current.isMicrophoneEnabled) {
        await rtc.disableMicrophone();
      } else {
        await rtc.enableMicrophone();
      }
    } catch (_) {
      // Falha de hardware/permissão: não derruba a sessão; volta para o
      // estado anterior (sem otimismo) e avisa o usuário.
      if (_disposed) return;
      state = state.copyWith(
        status: VoiceSessionStatus.connected,
        isMicrophoneEnabled: current.isMicrophoneEnabled,
        errorMessage: 'Não foi possível alternar o microfone.',
      );
      return;
    }
    // Otimista para o botão; os eventos MicEnabledChangedEvent do
    // participante local reconciliam com o estado real do LiveKit.
    if (_disposed) return;
    state = state.copyWith(
      isMicrophoneEnabled: !current.isMicrophoneEnabled,
      errorMessage: null,
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
  /// Com [includeSystemAudio] true, pede o áudio de sistema junto. Falha do
  /// áudio (sem device monitor no SO) NÃO bloqueia o share: o vídeo já saiu
  /// e o [SystemAudioPublishException] só troca a mensagem — o
  /// [ScreenShareEnabledChangedEvent] confirma o share na sequência.
  Future<void> startScreenShare(
    String? sourceId, {
    bool includeSystemAudio = false,
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
      );
    } on SystemAudioPublishException {
      // O VÍDEO saiu; só o áudio de sistema falhou (sem device monitor no
      // SO, permissão negada...). Mensagem específica — a sessão fica
      // intacta e o evento de share reconcilia o estado.
      if (_disposed) return;
      state = state.copyWith(
        status: VoiceSessionStatus.connected,
        isScreenSharing: true,
        screenShareQuality: rtc.screenShareQuality,
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
    final effectiveQuality = rtc.screenShareQuality;
    state = state.copyWith(
      isScreenSharing: true,
      screenShareQuality: effectiveQuality,
      errorMessage: effectiveQuality == current.screenShareQuality
          ? null
          : 'Não foi possível aplicar a qualidade escolhida; transmissão mantida em Auto.',
    );
  }

  /// Alterna a preferência de incluir o ÁUDIO DE SISTEMA no PRÓXIMO
  /// compartilhamento (botão da barra de controles). No-op com share ativo:
  /// a decisão é lida apenas no start — mudar ao vivo exigiria
  /// despublicar/republicar (fora do escopo V1).
  void toggleIncludeSystemAudio() {
    if (state.status != VoiceSessionStatus.connected) return;
    if (state.isScreenSharing) return;
    state = state.copyWith(
      includeSystemAudio: !state.includeSystemAudio,
      errorMessage: null,
    );
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
    state = state.copyWith(isScreenSharing: false, errorMessage: null);
  }

  /// Alterna o destaque (spotlight) de um participante: toque repetido no
  /// mesmo tile volta ao grid. O snapshot de participantes revalida —
  /// destaque de quem saiu ou desligou a câmera é limpo em [_applyParticipants].
  void toggleSpotlight(String participantId) {
    if (state.autoSpotlightActive) {
      // QUALQUER seleção manual dispensa o destaque automático do share:
      // o usuário assumiu o controle. Tocar o próprio sharer volta ao grid;
      // tocar outro participante o destaca — em ambos os casos o auto é
      // desligado (senão o snapshot seguinte re-forçaria o sharer e o fim
      // do share restauraria um estado obsoleto, perdendo a seleção manual).
      state = state.copyWith(
        spotlightParticipantId: state.spotlightParticipantId == participantId
            ? null
            : participantId,
        autoSpotlightActive: false,
        savedSpotlightParticipantId: null,
      );
      return;
    }
    if (state.spotlightParticipantId == participantId) {
      state = state.copyWith(spotlightParticipantId: null);
    } else {
      state = state.copyWith(spotlightParticipantId: participantId);
    }
  }

  /// Atualiza o cache de câmeras do sheet de settings. Falha de enumeração
  /// é silenciosa: mantém a lista atual, sem derrubar nada.
  Future<void> refreshCameraDevices() async {
    final current = state;
    if (current.status != VoiceSessionStatus.connected) return;
    final rtc = ref.read(rtcServiceProvider);
    final List<RtcVideoDevice> devices;
    try {
      devices = await rtc.listCameraDevices();
    } catch (_) {
      // Hardware ausente/permissão pendente: mantém o cache anterior.
      return;
    }
    if (_disposed) return;
    // Seleção que saiu da lista nova é limpa (device não existe mais).
    final selectedId = current.selectedCameraId;
    final selectedStillValid =
        selectedId != null && devices.any((d) => d.id == selectedId);
    state = state.copyWith(
      cameraDevices: devices,
      selectedCameraId: selectedStillValid ? selectedId : null,
    );
  }

  /// Seleciona uma câmera no sheet. Com a câmera LIGADA aplica ao vivo via
  /// [RtcService.switchCamera]; com a câmera DESLIGADA apenas registra a
  /// seleção — o serviço não persiste deviceId pendente (o próximo
  /// [RtcService.enableCamera] usa o device default; fato do contrato).
  Future<void> selectCamera(String deviceId) async {
    final current = state;
    if (current.status != VoiceSessionStatus.connected) return;
    // Sucesso (com ou sem câmera ligada) limpa mensagem de erro anterior —
    // senão o SnackBar de uma falha antiga nunca mais reaparece (o listener
    // só dispara quando a mensagem muda).
    state = state.copyWith(selectedCameraId: deviceId, errorMessage: null);
    if (!current.isCameraEnabled) return;
    final rtc = ref.read(rtcServiceProvider);
    try {
      await rtc.switchCamera(deviceId);
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        status: VoiceSessionStatus.connected,
        errorMessage: 'Não foi possível trocar a câmera.',
      );
    }
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
    } catch (_) {
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
  Future<void> _connect(VoiceJoinInfo info) async {
    final rtc = ref.read(rtcServiceProvider);
    try {
      await rtc.connect(
        info.livekitUrl,
        info.token,
        tokenGenerator: _tokenGenerator,
      );
    } catch (_) {
      if (_disposed) return;
      try {
        final fresh = await _freshJoinInfo();
        await rtc.connect(
          fresh.livekitUrl,
          fresh.token,
          tokenGenerator: _tokenGenerator,
        );
      } catch (_) {
        if (_disposed) return;
        state = state.copyWith(
          status: VoiceSessionStatus.error,
          errorMessage: 'Não foi possível entrar no canal de voz.',
        );
        return;
      }
    }
    if (_disposed) return;
    // O mic entra publicado ATIVO por padrão (Fase 7 — "áudio por padrão";
    // a Fase 4 entrava mutado) e a câmera NUNCA é publicada no connect —
    // começa OFF (só via botão).
    state = state.copyWith(
      status: VoiceSessionStatus.connected,
      isMicrophoneEnabled: true,
    );
  }

  /// Token fresco para reconexões futuras (o LiveKit 2.11.0 não tem
  /// tokenGenerator nativo — o controller o usa em retries manuais).
  Future<String> _tokenGenerator() => _freshJoinInfo().then((i) => i.token);

  void _applyParticipants(List<RtcParticipant> list) {
    if (_disposed) return;
    final localId = ref.read(rtcServiceProvider).localParticipantId;
    final sorted = _sort(list, localId);

    // ── Spotlight automático do screen share (PRD §25) ────────────────────
    // Lógica por SNAPSHOT (robusto a ordem de eventos — evento e snapshot
    // chegam separados): o 1º sharer vira destaque com o estado anterior
    // salvo; o fim do share restaura; um 2º sharer assume o destaque.
    final sharerIds = {
      for (final p in sorted)
        if (p.isScreenSharing) p.id,
    };
    final firstShare = _lastSharers.isEmpty && sharerIds.isNotEmpty; // 0 → ≥1
    final shareEnded = _lastSharers.isNotEmpty && sharerIds.isEmpty; // ≥1 → 0
    _lastSharers
      ..clear()
      ..addAll(sharerIds);

    var next = state.copyWith(participants: sorted);

    if (firstShare) {
      // Salva o spotlight atual (id manual ou null = grid) para restaurar.
      next = next.copyWith(
        savedSpotlightParticipantId: next.spotlightParticipantId,
        autoSpotlightActive: true,
        spotlightParticipantId: sharerIds.first,
      );
    } else if (shareEnded && next.autoSpotlightActive) {
      // Ninguém mais compartilha E o auto ainda estava no controle: restaura
      // o estado anterior. Se o usuário dispensou o auto manualmente
      // (autoSpotlightActive false, saved limpo), a seleção manual DELE
      // permanece — restaurar aqui converteria o spotlight manual em grid.
      next = next.copyWith(
        spotlightParticipantId: next.savedSpotlightParticipantId,
        autoSpotlightActive: false,
        savedSpotlightParticipantId: null,
      );
    } else if (next.autoSpotlightActive &&
        sharerIds.isNotEmpty &&
        !sharerIds.contains(next.spotlightParticipantId)) {
      // Outro sharer assumiu (2º share, troca de sharer): o destaque segue.
      next = next.copyWith(spotlightParticipantId: sharerIds.first);
    }

    // Revalida o destaque: tile sem vídeo não merece spotlight — quem saiu
    // da sala ou desligou a câmera (E não está compartilhando tela) volta o
    // painel para o grid. Sharer SEM câmera continua merecendo destaque (a
    // tela dele é o vídeo — critério ampliado). Também limpa do dedupe de
    // qualidade os ids que saíram (tile desmontado = OFF).
    final spotlightId = next.spotlightParticipantId;
    if (spotlightId != null &&
        !sorted.any(
          (p) =>
              p.id == spotlightId && (p.isCameraEnabled || p.isScreenSharing),
        )) {
      next = next.copyWith(spotlightParticipantId: null);
    }
    final ids = {for (final p in sorted) p.id};
    _lastQuality.removeWhere((id, _) => !ids.contains(id));
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
        _lastSharers.clear();
        state = state.copyWith(
          status: VoiceSessionStatus.idle,
          participants: const [],
          isMicrophoneEnabled: false,
          isCameraEnabled: false,
          isScreenSharing: false,
          screenShareQuality: RtcScreenShareQuality.auto,
          includeSystemAudio: false,
          isSystemAudioEnabled: false,
          isReconnecting: false,
          isAudioBlocked: false,
          autoSpotlightActive: false,
          savedSpotlightParticipantId: null,
          spotlightParticipantId: null,
          errorMessage: null,
        );
      case AudioPlaybackBlockedEvent():
        // Autoplay policy do browser bloqueou o áudio remoto: liga o banner
        // tocável (o gesto chama [resumeAudio]). Só no web; desktop nunca.
        state = state.copyWith(isAudioBlocked: true);
      case AudioPlaybackResumedEvent():
        // startAudio bem-sucedido dentro do gesto: o banner pode sumir.
        state = state.copyWith(isAudioBlocked: false);
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
          state = state.copyWith(isScreenSharing: isScreenSharing);
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
        state = state.copyWith(isReconnecting: true);
      case ReconnectedEvent():
        // Sala NOVA: o serviço republicou o mic MUTADO (padrão do connect);
        // câmera/share locais recomeçam off (risco V1 documentado). Reset
        // também o rastreio de sharers do auto-spotlight.
        _lastSharers.clear();
        state = state.copyWith(
          isReconnecting: false,
          isMicrophoneEnabled: false,
          isCameraEnabled: false,
          isScreenSharing: false,
          screenShareQuality: RtcScreenShareQuality.auto,
          includeSystemAudio: false,
          isSystemAudioEnabled: false,
          isAudioBlocked: false,
          autoSpotlightActive: false,
          savedSpotlightParticipantId: null,
          spotlightParticipantId: null,
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
