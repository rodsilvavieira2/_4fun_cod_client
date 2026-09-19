import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';
import '../../core/rtc/rtc_video_view.dart';
import '../../core/telemetry/telemetry_service.dart';
import '../../core/ui/ui.dart';
import 'go_live_modal.dart';
import 'theater/theater_screen.dart';
import 'voice_fullscreen_window.dart';
import 'voice_providers.dart';
import 'voice_video_tile.dart';

/// Canal de voz: painel de participantes (nome, mute, active speaker) +
/// barra de controles (entrar/sair, mute/unmute).
///
/// Embarcada no [ServerShellScreen] no lugar do placeholder da Fase 4 —
/// nenhuma rota nova (a view mora no shell, como o chat).
class VoiceScreen extends ConsumerWidget {
  const VoiceScreen({
    super.key,
    required this.serverId,
    required this.channelId,
  });

  final String serverId;
  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arg = (serverId: serverId, channelId: channelId);
    final state = ref.watch(voiceControllerProvider(arg));
    final notifier = ref.read(voiceControllerProvider(arg).notifier);

    // Erros de toggle DENTRO da sessão (mic/câmera) aparecem via SnackBar —
    // o `errorMessage` do painel só renderiza no ramo `error` do status.
    ref.listen(voiceControllerProvider(arg), (prev, next) {
      final message = next.errorMessage;
      if (message != null &&
          message != prev?.errorMessage &&
          next.status == VoiceSessionStatus.connected) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });

    final connected = state.status == VoiceSessionStatus.connected;
    if (!connected) {
      final controls = _Controls(
        state: state,
        isSpotlight: false,
        onJoin: notifier.join,
        onLeave: notifier.leave,
        onToggleCamera: notifier.toggleCamera,
        onToggleScreenShare: () => _toggleScreenShare(context, ref),
        onToggleFilmstrip: notifier.toggleFilmstrip,
      );
      return Stack(
        children: [
          Column(
            children: [
              // Banner de reconexão automática: a sessão continua `connected`.
              if (state.isReconnecting && connected)
                const _ReconnectingBanner(),
              // Áudio remoto bloqueado pelo browser (autoplay policy no web).
              if (state.isAudioBlocked && connected)
                _AudioBlockedBanner(onTap: notifier.resumeAudio),
              Expanded(
                child: _ParticipantsPanel(
                  state: state,
                  notifier: notifier,
                  arg: arg,
                  transmitQuality: null,
                  onToggleFullscreen: null,
                ),
              ),
            ],
          ),
          Align(alignment: Alignment.bottomCenter, child: controls),
        ],
      );
    }

    // Conectado: palco imersivo com auto-hide (hover revela, parado esconde).
    return _ConnectedStage(
      state: state,
      notifier: notifier,
      arg: arg,
      onToggleScreenShare: () => _toggleScreenShare(context, ref),
      onToggleFullscreen: () => _toggleFullscreen(context, ref, arg),
      onLeave: () => _leave(ref, arg),
    );
  }

  /// Sai do canal de voz e volta para `idle`, garantindo que a janela
  /// abandone o fullscreen (best-effort: falha nunca bloqueia o leave).
  Future<void> _leave(
    WidgetRef ref,
    ({String serverId, String channelId}) arg,
  ) async {
    try {
      await exitVoiceFullscreenWindow(session: null);
    } catch (error, stack) {
      // Sem janela (testes): o estado cobre a UI.
      debugPrint('[fullscreen] exit failed: $error');
      ref
          .read(telemetryServiceProvider)
          .reportError('voice fullscreen exit', error, stack);
    }
    ref.read(voiceControllerProvider(arg).notifier).setFullscreen(false);
    await ref.read(voiceControllerProvider(arg).notifier).leave();
  }

  /// Fullscreen completo: janela do SO em fullscreen + takeover imersivo da
  /// área streamada ocupando o app todo. O pop (botão sair, voltar do
  /// sistema) cai no `finally`, que devolve a janela e limpa o flag.
  /// Falha de janela nunca derruba a sessão — o takeover in-app cobre.
  Future<void> _toggleFullscreen(
    BuildContext context,
    WidgetRef ref,
    ({String serverId, String channelId}) arg,
  ) async {
    final notifier = ref.read(voiceControllerProvider(arg).notifier);
    final navigator = Navigator.of(context);
    final telemetry = ref.read(telemetryServiceProvider);
    VoiceFullscreenWindowSession? fullscreenSession;
    notifier.setFullscreen(true);
    try {
      fullscreenSession = await enterVoiceFullscreenWindow();
      debugPrint(
        '[fullscreen] enter: wasMaximized=${fullscreenSession.wasMaximized} '
        'isFullScreen=${fullscreenSession.confirmedFullScreen}',
      );
      if (!fullscreenSession.confirmedFullScreen) {
        telemetry.reportError(
          'voice fullscreen enter',
          'setFullScreen(true) no-op '
              '(isFullScreen=false, wasMaximized=${fullscreenSession.wasMaximized})',
        );
      }
    } catch (error, stack) {
      // Sem janela (testes): segue só com o takeover in-app.
      debugPrint('[fullscreen] enter failed: $error');
      telemetry.reportError('voice fullscreen enter', error, stack);
    }
    try {
      await navigator.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _FullscreenTakeover(
            arg: arg,
            onToggleScreenShare: () => _toggleScreenShare(context, ref),
            onLeave: () {
              navigator.pop();
              _leave(ref, arg);
            },
          ),
        ),
      );
    } finally {
      try {
        final isFullScreen = await exitVoiceFullscreenWindow(
          session: fullscreenSession,
        );
        debugPrint('[fullscreen] exit: isFullScreen=$isFullScreen');
      } catch (error, stack) {
        // Janela já fechada/indisponível: nada a devolver.
        debugPrint('[fullscreen] exit failed: $error');
        telemetry.reportError('voice fullscreen exit', error, stack);
      }
      notifier.setFullscreen(false);
    }
  }

  /// Fluxo do botão de compartilhar tela: ativo → encerra; inativo → delega a
  /// escolha ao navegador no Web, ao portal no Linux ou ao seletor de fontes
  /// do desktopCapturer no Windows.
  Future<void> _toggleScreenShare(BuildContext context, WidgetRef ref) async {
    final arg = (serverId: serverId, channelId: channelId);
    final notifier = ref.read(voiceControllerProvider(arg).notifier);
    final current = ref.read(voiceControllerProvider(arg));
    if (current.isScreenSharing) {
      await notifier.stopScreenShare();
      return;
    }
    // Modal Go Live (áudio + qualidade) → seletor de fonte → start. Cancelar em
    // qualquer etapa retorna null e nada inicia.
    final goLive = await showGoLiveModal(
      context,
      backend: ref.read(nativeMediaServicesProvider).screenShare,
      pendingQuality: ref.read(rtcServiceProvider).screenShareQuality,
    );
    if (goLive == null) return;
    await notifier.startScreenShare(
      goLive.sourceId,
      includeSystemAudio: goLive.includeAudio,
      quality: goLiveQualityFor(goLive.quality),
      kind: goLive.kind,
    );
  }
}

/// Palco conectado: sem dock global (controles moram na toolbar de cada
/// tile de transmissão). O auto-hide de 2.5s permanece só para o fullscreen
/// imersivo (hover revela badges/overlays, parado esconde — fica só o vídeo).
/// Fora do fullscreen os overlays seguem sempre visíveis e cada toolbar tem
/// seu próprio fade por hover no tile.
/// O estado mora aqui (não no controller): é puro chrome de UI.
class _ConnectedStage extends ConsumerStatefulWidget {
  const _ConnectedStage({
    required this.state,
    required this.notifier,
    required this.arg,
    required this.onToggleScreenShare,
    required this.onToggleFullscreen,
    required this.onLeave,
  });

  final VoiceState state;
  final VoiceController notifier;
  final ({String serverId, String channelId}) arg;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onLeave;

  @override
  ConsumerState<_ConnectedStage> createState() => _ConnectedStageState();
}

class _ConnectedStageState extends ConsumerState<_ConnectedStage> {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _reveal() {
    _scheduleHide();
    if (!_controlsVisible && mounted) setState(() => _controlsVisible = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final notifier = widget.notifier;
    // Fullscreen imersivo: badges/overlays somem (fica só o vídeo); fora do
    // fullscreen continuam sempre visíveis (Discord). O cursor some junto —
    // hover revela tudo de novo. As toolbars dos tiles têm fade próprio.
    final overlayVisible = !state.isFullscreen || _controlsVisible;
    return MouseRegion(
      cursor: overlayVisible
          ? SystemMouseCursors.basic
          : SystemMouseCursors.none,
      onEnter: (_) => _reveal(),
      onHover: (_) => _reveal(),
      child: Stack(
        children: [
          Column(
            children: [
              if (state.isReconnecting) const _ReconnectingBanner(),
              if (state.isAudioBlocked)
                _AudioBlockedBanner(onTap: notifier.resumeAudio),
              Expanded(
                child: _ParticipantsPanel(
                  state: state,
                  notifier: notifier,
                  arg: widget.arg,
                  transmitQuality: _transmitQualityLabel(state),
                  onToggleFullscreen: widget.onToggleFullscreen,
                  overlayVisible: overlayVisible,
                ),
              ),
            ],
          ),
          Positioned(
            top: 8,
            right: 12,
            child: _TheaterEntryButton(arg: widget.arg),
          ),
        ],
      ),
    );
  }
}

/// Entrada flutuante do Modo Teatro (ADR 0003, decisão 8): fica no palco,
/// abre o takeover sem reconectar (mesmo `voiceControllerProvider(arg)`).
class _TheaterEntryButton extends StatelessWidget {
  const _TheaterEntryButton({required this.arg});

  final ({String serverId, String channelId}) arg;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Entrar no Modo Teatro',
      child: FilledButton.tonalIcon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => TheaterScreen(
                serverId: arg.serverId,
                channelId: arg.channelId,
              ),
            ),
          );
        },
        icon: const Icon(Icons.theater_comedy, size: 16),
        label: const Text('Modo Teatro'),
      ),
    );
  }
}

/// Takeover imersivo da área streamada: ocupa a janela toda do app (NÃO é
/// fullscreen do SO — a janela do usuário fica intacta). Reusa o
/// [_ConnectedStage] inteiro (auto-hide, dock, filmstrip oculta via
/// [VoiceState.isFullscreen]); aqui o botão fullscreen vira "sair" (pop) e
/// sair do canal fecha o takeover antes do leave.
class _FullscreenTakeover extends ConsumerWidget {
  const _FullscreenTakeover({
    required this.arg,
    required this.onToggleScreenShare,
    required this.onLeave,
  });

  final ({String serverId, String channelId}) arg;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceControllerProvider(arg));
    final notifier = ref.read(voiceControllerProvider(arg).notifier);
    // Reset externo do flag (leave/disconnect com takeover aberto):
    // fecha a rota para não largar janela em fullscreen órfã.
    if (!state.isFullscreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: _ConnectedStage(
        state: state,
        notifier: notifier,
        arg: arg,
        onToggleScreenShare: onToggleScreenShare,
        onToggleFullscreen: () => Navigator.of(context).pop(),
        onLeave: onLeave,
      ),
    );
  }
}

/// Banner de reconexão automática do serviço: aparece com o
/// [ReconnectingEvent] e some no [ReconnectedEvent]. A sessão continua
/// `connected` — nenhum ramo de erro/idle é acionado; o banner é o ÚNICO
/// efeito visível durante a reconexão.
class _ReconnectingBanner extends StatelessWidget {
  const _ReconnectingBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Reconectando…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner de áudio BLOQUEADO pelo browser (autoplay policy no web): o
/// playback remoto não toca até um gesto do usuário. O toque no banner
/// chama [VoiceController.resumeAudio] (que pede ao serviço `startAudio`).
/// Só aparece no web; desktop nunca emite [AudioPlaybackBlockedEvent].
class _AudioBlockedBanner extends StatelessWidget {
  const _AudioBlockedBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.errorContainer,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.volume_off,
                size: 18,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Áudio bloqueado pelo navegador — toque para ativar',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantsPanel extends StatelessWidget {
  const _ParticipantsPanel({
    required this.state,
    required this.notifier,
    required this.arg,
    required this.transmitQuality,
    required this.onToggleFullscreen,
    this.overlayVisible = true,
  });

  final VoiceState state;
  final VoiceController notifier;
  final ({String serverId, String channelId}) arg;

  /// Qualidade do Go Live local (nulo quando o local não transmite ou é
  /// desconhecida). Cada tile de tela exibe só se for do local.
  final String? transmitQuality;

  /// Expansão do tile em destaque (takeover fullscreen). Nulo fora do palco.
  final VoidCallback? onToggleFullscreen;

  /// Fullscreen imersivo: false esconde os badges dos tiles junto com o dock.
  final bool overlayVisible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (state.status) {
      case VoiceSessionStatus.connecting:
        return const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        );
      case VoiceSessionStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  state.errorMessage ?? 'Falha ao conectar.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        );
      case VoiceSessionStatus.idle:
        return Center(
          child: Text(
            'Você ainda não está neste canal de voz.\n'
            'Use o botão abaixo para entrar.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
        );
      case VoiceSessionStatus.connected:
        if (state.spotlightParticipantId == null) {
          return ColoredBox(
            color: Colors.black,
            child: _VideoGrid(
              state: state,
              notifier: notifier,
              arg: arg,
              transmitQuality: transmitQuality,
              overlayVisible: overlayVisible,
            ),
          );
        }
        return ColoredBox(
          color: Colors.black,
          child: _SpotlightLayout(
            state: state,
            notifier: notifier,
            arg: arg,
            transmitQuality: transmitQuality,
            onToggleFullscreen: onToggleFullscreen,
            overlayVisible: overlayVisible,
          ),
        );
    }
  }
}

/// Resultado puro do cálculo do grid, exposto para validar diferentes
/// tamanhos de janela sem precisar abrir uma sessão RTC.
class VoiceGridGeometry {
  const VoiceGridGeometry({
    required this.columns,
    required this.rows,
    required this.tileSize,
    required this.gridSize,
  });

  final int columns;
  final int rows;
  final Size tileSize;
  final Size gridSize;
}

/// Escolhe a combinação de linhas/colunas que produz o maior tile 16:9
/// possível no espaço disponível. O mesmo cálculo atende câmeras, avatares e
/// compartilhamentos — não existe um layout especial que esconda os shares.
VoiceGridGeometry calculateVoiceGridGeometry({
  required Size viewport,
  required int tileCount,
  double gap = 10,
  double aspectRatio = 16 / 9,
  int maxColumns = 5,
}) {
  assert(tileCount > 0);
  final width = math.max(1.0, viewport.width);
  final height = math.max(1.0, viewport.height);
  VoiceGridGeometry? best;
  var bestArea = -1.0;
  var bestEmptySlots = tileCount;

  for (var columns = 1; columns <= math.min(tileCount, maxColumns); columns++) {
    final rows = (tileCount / columns).ceil();
    final widthPerTile = (width - gap * (columns - 1)) / columns;
    final heightPerTile = (height - gap * (rows - 1)) / rows;
    if (widthPerTile <= 0 || heightPerTile <= 0) continue;

    final maxTileWidth = tileCount == 1 ? 960.0 : 720.0;
    final tileWidth = math.min(
      maxTileWidth,
      math.min(widthPerTile, heightPerTile * aspectRatio),
    );
    final tileHeight = tileWidth / aspectRatio;
    final area = tileWidth * tileHeight;
    final emptySlots = rows * columns - tileCount;
    final isBetter =
        area > bestArea + 0.5 ||
        ((area - bestArea).abs() <= 0.5 && emptySlots < bestEmptySlots);
    if (!isBetter) continue;

    bestArea = area;
    bestEmptySlots = emptySlots;
    best = VoiceGridGeometry(
      columns: columns,
      rows: rows,
      tileSize: Size(tileWidth, tileHeight),
      gridSize: Size(
        columns * tileWidth + (columns - 1) * gap,
        rows * tileHeight + (rows - 1) * gap,
      ),
    );
  }

  return best ??
      VoiceGridGeometry(
        columns: 1,
        rows: tileCount,
        tileSize: const Size(1, 1),
        gridSize: Size(1, tileCount.toDouble()),
      );
}

class _VoiceMediaItem {
  const _VoiceMediaItem({required this.participant, required this.source});

  final RtcParticipant participant;
  final VoiceVideoSource source;

  String get key => '${participant.id}:${source.name}';
}

List<_VoiceMediaItem> _mediaItems(List<RtcParticipant> participants) {
  final shares = <_VoiceMediaItem>[];
  final people = <_VoiceMediaItem>[];
  for (final participant in participants) {
    if (participant.isScreenSharing) {
      shares.add(
        _VoiceMediaItem(
          participant: participant,
          source: VoiceVideoSource.screen,
        ),
      );
    }
    if (participant.isCameraEnabled) {
      people.add(
        _VoiceMediaItem(
          participant: participant,
          source: VoiceVideoSource.camera,
        ),
      );
    } else if (!participant.isScreenSharing) {
      people.add(
        _VoiceMediaItem(
          participant: participant,
          source: VoiceVideoSource.avatar,
        ),
      );
    }
  }
  // Compartilhamentos ficam visíveis primeiro, porém usam exatamente o
  // mesmo tamanho e componente das câmeras.
  return [...shares, ...people];
}

/// Rótulo curto da qualidade transmitida (ex.: `1080p60`, `Auto`).
/// Nulo quando não há share de tela ativo — da câmera não temos perfil
/// conhecido, então é mais honesto omitir do que chutar.
///
/// Com adaptação ativa (efetiva < objetivo), mostra `objetivo · adaptado
/// em efetivo` (ex.: `Auto · adaptado em 720p15`); iguais = só o objetivo.
String? _transmitQualityLabel(VoiceState state) {
  if (!state.isScreenSharing) return null;
  final target = _screenShareQualityShortLabel(state.screenShareQuality);
  final effective = state.screenShareEffectiveQuality;
  if (effective == null || effective == state.screenShareQuality) return target;
  return '$target · adaptado em ${_screenShareQualityShortLabel(effective)}';
}

/// Rótulo curto de um perfil de screen share (ex.: `1080p60`, `Auto`).
String _screenShareQualityShortLabel(RtcScreenShareQuality quality) {
  return switch (quality) {
    RtcScreenShareQuality.q1080p60 => '1080p60',
    RtcScreenShareQuality.q720p60 => '720p60',
    RtcScreenShareQuality.q1080p30 => '1080p30',
    RtcScreenShareQuality.q1080p15 => '1080p15',
    RtcScreenShareQuality.q720p15 => '720p15',
    RtcScreenShareQuality.q480p30 => '480p30',
    RtcScreenShareQuality.q360p3 => '360p3',
    RtcScreenShareQuality.auto => 'Auto',
  };
}

VoiceSpotlightSource _spotlightSource(VoiceVideoSource source) {
  return source == VoiceVideoSource.screen
      ? VoiceSpotlightSource.screen
      : VoiceSpotlightSource.camera;
}

/// Opt-in de vídeo: o tile mostra vídeo quando local ou assistido.
/// Avatar (sem publicação) sempre `true` — o tile decide o placeholder.
bool _isWatching(VoiceController notifier, _VoiceMediaItem item) {
  if (item.source == VoiceVideoSource.avatar) return true;
  return notifier.isWatching(
    item.participant.id,
    _spotlightSource(item.source),
  );
}

/// Toque no tile do grid: SEMPRE foca/destaque (spotlight) — nunca assiste.
/// Transmissão: assistir/parar vive só na toolbar do tile. Câmera remota
/// mantém o opt-in por toque (sem toolbar própria). Avatar sem vídeo não é
/// tocável. Spotlight/filmstrip mantêm o toque atual (troca/dispensa destaque).
VoidCallback? _gridOnTap(VoiceController notifier, _VoiceMediaItem item) {
  if (item.source == VoiceVideoSource.avatar) return null;
  final id = item.participant.id;
  final source = _spotlightSource(item.source);
  if (item.source == VoiceVideoSource.screen) {
    return () => notifier.toggleSpotlight(id, source: source);
  }
  if (notifier.isLocalParticipant(id)) {
    return () => notifier.toggleSpotlight(id, source: source);
  }
  return () => notifier.toggleWatch(id, source);
}

/// Assistir/parar da toolbar do tile de transmissão (remoto). Nulo para
/// local (sempre visível), câmera e avatar (fora do escopo da toolbar).
VoidCallback? _screenToggleWatch(
  VoiceController notifier,
  _VoiceMediaItem item,
) {
  if (item.source != VoiceVideoSource.screen) return null;
  if (notifier.isLocalParticipant(item.participant.id)) return null;
  return () =>
      notifier.toggleWatch(item.participant.id, _spotlightSource(item.source));
}

/// Parar o share da toolbar do tile local. Nulo para remoto e não-screen.
VoidCallback? _screenStopShare(VoiceController notifier, _VoiceMediaItem item) {
  if (item.source != VoiceVideoSource.screen) return null;
  if (!notifier.isLocalParticipant(item.participant.id)) return null;
  return notifier.stopScreenShare;
}

/// Palco em grade: uma pessoa pode contribuir com dois tiles irmãos (tela e
/// câmera); participantes sem vídeo continuam presentes através do avatar.
class _VideoGrid extends StatelessWidget {
  const _VideoGrid({
    required this.state,
    required this.notifier,
    required this.arg,
    required this.transmitQuality,
    this.overlayVisible = true,
  });

  final VoiceState state;
  final VoiceController notifier;
  final ({String serverId, String channelId}) arg;

  /// Qualidade do Go Live local (cada tile de tela exibe só se for local).
  final String? transmitQuality;

  /// Fullscreen imersivo: false esconde os badges dos tiles junto com o dock.
  final bool overlayVisible;

  @override
  Widget build(BuildContext context) {
    final items = _mediaItems(state.participants);
    if (items.isEmpty) {
      return const _EmptyVoiceStage();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        const horizontalPadding = 20.0;
        const topPadding = 14.0;
        // Dock flutuante sobre o palco (auto-hide): reserva mínima só para
        // não colar o grid na borda inferior.
        const bottomControlsInset = 16.0;
        final availableSize = Size(
          math.max(1.0, constraints.maxWidth - horizontalPadding * 2),
          math.max(
            1.0,
            constraints.maxHeight - topPadding - bottomControlsInset,
          ),
        );
        final geometry = calculateVoiceGridGeometry(
          viewport: availableSize,
          tileCount: items.length,
          gap: gap,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomControlsInset,
          ),
          child: Center(
            child: SizedBox(
              width: geometry.gridSize.width,
              height: geometry.gridSize.height,
              child: Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in items)
                    SizedBox(
                      key: ValueKey(item.key),
                      width: geometry.tileSize.width,
                      height: geometry.tileSize.height,
                      child: VoiceVideoTile(
                        arg: arg,
                        participant: item.participant,
                        source: item.source,
                        role: VoiceVideoTileRole.grid,
                        isWatching: _isWatching(notifier, item),
                        onTap: _gridOnTap(notifier, item),
                        // Toolbar da transmissão: assistir/parar (remoto) ou
                        // parar o share (local). Click no tile só foca.
                        onToggleWatch: _screenToggleWatch(notifier, item),
                        onStopShare: _screenStopShare(notifier, item),
                        // Overlay de transmissão: cada tile de tela tem o
                        // seu (LIVE + qualidade local); expandir = destacar.
                        qualityLabel: item.source == VoiceVideoSource.screen
                            ? transmitQuality
                            : null,
                        onExpand: item.source == VoiceVideoSource.screen
                            ? () => notifier.toggleSpotlight(
                                item.participant.id,
                                source: VoiceSpotlightSource.screen,
                              )
                            : null,
                        isFullscreen: state.isFullscreen,
                        overlayVisible: overlayVisible,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyVoiceStage extends StatelessWidget {
  const _EmptyVoiceStage();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              size: 30,
              color: colors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              'Nenhuma transmissão disponível',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Quando uma câmera ou tela for compartilhada, a prévia aparecerá aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                height: 1.35,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Destaque opcional com filmstrip colapsável de miniaturas maiores
/// (192x120, Discord-like). Câmera e tela da mesma pessoa continuam sendo
/// itens distintos. Fullscreen esconde a filmstrip (palco imersivo).
class _SpotlightLayout extends StatelessWidget {
  const _SpotlightLayout({
    required this.state,
    required this.notifier,
    required this.arg,
    required this.transmitQuality,
    required this.onToggleFullscreen,
    this.overlayVisible = true,
  });

  final VoiceState state;
  final VoiceController notifier;
  final ({String serverId, String channelId}) arg;

  /// Qualidade do Go Live local (o tile de tela exibe só se for local).
  final String? transmitQuality;

  /// Expansão do tile em destaque (takeover fullscreen).
  final VoidCallback? onToggleFullscreen;

  /// Fullscreen imersivo: false esconde os badges do tile junto com o dock.
  final bool overlayVisible;

  /// Altura da faixa de miniaturas (wireframe B).
  static const double filmstripHeight = 132;

  /// Tamanho do thumb da filmstrip, com altura extra para overlays compactos.
  static const double miniatureWidth = 192;
  static const double miniatureHeight = 120;

  @override
  Widget build(BuildContext context) {
    final items = _mediaItems(state.participants);
    final spotlightId = state.spotlightParticipantId;
    final spotlightSource = state.spotlightSource;
    _VoiceMediaItem? focused;
    for (final item in items) {
      final sourceMatches = switch (spotlightSource) {
        VoiceSpotlightSource.camera => item.source == VoiceVideoSource.camera,
        VoiceSpotlightSource.screen => item.source == VoiceVideoSource.screen,
        null => item.source != VoiceVideoSource.avatar,
      };
      if (item.participant.id == spotlightId && sourceMatches) {
        focused = item;
        break;
      }
    }
    if (focused == null) {
      return _VideoGrid(
        state: state,
        notifier: notifier,
        arg: arg,
        transmitQuality: transmitQuality,
        overlayVisible: overlayVisible,
      );
    }
    final selected = focused;
    final others = [
      for (final item in items)
        if (item.key != selected.key) item,
    ];
    // Fullscreen = palco imersivo, sem filmstrip (o dock/header já têm
    // auto-hide; o toggle de fullscreen mora neles).
    final showStrip =
        state.filmstripVisible && !state.isFullscreen && others.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: state.isFullscreen
                ? EdgeInsets.zero
                : const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: VoiceVideoTile(
              arg: arg,
              participant: selected.participant,
              source: selected.source,
              role: VoiceVideoTileRole.spotlight,
              isWatching: _isWatching(notifier, selected),
              onTap: () => notifier.toggleSpotlight(
                selected.participant.id,
                source: _spotlightSource(selected.source),
              ),
              // Toolbar da transmissão no destaque (mesma do grid).
              onToggleWatch: _screenToggleWatch(notifier, selected),
              onStopShare: _screenStopShare(notifier, selected),
              // Destaque de tela: overlay com LIVE + qualidade local;
              // expandir abre o takeover fullscreen.
              qualityLabel: selected.source == VoiceVideoSource.screen
                  ? transmitQuality
                  : null,
              onExpand: selected.source == VoiceVideoSource.screen
                  ? onToggleFullscreen
                  : null,
              isFullscreen: state.isFullscreen,
              overlayVisible: overlayVisible,
            ),
          ),
        ),
        if (showStrip) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  others.length == 1
                      ? '1 participante'
                      : '${others.length} participantes',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.appColors.textMuted,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: notifier.toggleFilmstrip,
                  tooltip: 'Ocultar miniaturas',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(32),
                    foregroundColor: context.appColors.textSecondary,
                  ),
                  icon: const Icon(Icons.visibility_off, size: 18),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: filmstripHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: others.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = others[index];
                return Center(
                  child: SizedBox(
                    width: miniatureWidth,
                    height: miniatureHeight,
                    child: VoiceVideoTile(
                      arg: arg,
                      participant: item.participant,
                      source: item.source,
                      role: VoiceVideoTileRole.miniature,
                      isWatching: _isWatching(notifier, item),
                      onTap: item.source == VoiceVideoSource.avatar
                          ? null
                          : () => notifier.toggleSpotlight(
                              item.participant.id,
                              source: _spotlightSource(item.source),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ] else if (!state.isFullscreen && others.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              child: TextButton.icon(
                onPressed: notifier.toggleFilmstrip,
                icon: const Icon(Icons.visibility, size: 16),
                label: Text('Mostrar miniaturas (${others.length})'),
              ),
            ),
          )
        else
          const SizedBox(height: 8),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.isSpotlight,
    required this.onJoin,
    required this.onLeave,
    required this.onToggleCamera,
    required this.onToggleScreenShare,
    required this.onToggleFilmstrip,
  });

  final VoiceState state;

  /// Se o painel está em spotlight: mostra o toggle da filmstrip.
  final bool isSpotlight;
  final VoidCallback onJoin;
  final VoidCallback onLeave;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleScreenShare;
  final VoidCallback onToggleFilmstrip;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final connected = state.status == VoiceSessionStatus.connected;
    final connecting = state.status == VoiceSessionStatus.connecting;
    if (!connected) {
      if (!connecting && state.status == VoiceSessionStatus.idle) {
        return const SizedBox.shrink();
      }
      return FilledButton.icon(
        onPressed: connecting ? null : onJoin,
        icon: connecting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.headset),
        label: Text(connecting ? 'Conectando…' : 'Tentar novamente'),
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.surfaceGlass,
          borderRadius: AppRadius.brFull,
          border: Border.all(color: colors.borderSubtle),
          boxShadow: AppShadows.popover,
        ),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            _mediaToggleButton(
              colors: colors,
              icon: state.isCameraEnabled ? Icons.videocam : Icons.videocam_off,
              active: state.isCameraEnabled,
              activeColor: AppTokens.accentDanger,
              tooltip: state.isCameraEnabled
                  ? 'Desativar câmera'
                  : 'Ativar câmera',
              onPressed: onToggleCamera,
            ),
            _mediaToggleButton(
              colors: colors,
              icon: Icons.present_to_all,
              active: state.isScreenSharing,
              activeColor: AppTokens.accentDanger,
              tooltip: state.isScreenSharing
                  ? 'Parar compartilhamento'
                  : 'Compartilhar tela',
              onPressed: state.isReconnecting ? null : onToggleScreenShare,
            ),
            if (isSpotlight)
              _mediaToggleButton(
                colors: colors,
                icon: state.filmstripVisible
                    ? Icons.visibility_off
                    : Icons.visibility,
                active: false,
                activeColor: AppTokens.accentDanger,
                tooltip: state.filmstripVisible
                    ? 'Ocultar miniaturas'
                    : 'Mostrar miniaturas',
                onPressed: onToggleFilmstrip,
              ),
            IconButton(
              onPressed: onLeave,
              tooltip: 'Sair do canal de voz',
              style: IconButton.styleFrom(
                minimumSize: const Size.square(40),
                backgroundColor: AppTokens.accentDanger,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.call_end),
            ),
          ],
        ),
      ),
    );
  }

  /// Botão circular de mídia: o dock usa o mesmo controle compacto (40px) em
  /// qualquer largura, quebrando linhas só quando a janela fica estreita.
  Widget _mediaToggleButton({
    required AppThemePalette colors,
    required IconData icon,
    required bool active,
    required Color activeColor,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        backgroundColor: active ? activeColor : null,
        foregroundColor: colors.textPrimary,
      ),
      icon: Icon(icon),
    );
  }
}

/// Superfície compartilhável do preview, exposta para manter o estado de
/// loading verificável sem precisar abrir uma sessão LiveKit em widget tests.
class CameraPreviewSurface extends StatelessWidget {
  const CameraPreviewSurface({
    super.key,
    required this.trackRef,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final RtcVideoTrackRef? trackRef;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (trackRef != null) RtcVideoView(trackRef: trackRef),
          if (!loading && trackRef == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.videocam_off,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                  if (onRetry != null) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ],
              ),
            ),
          if (loading)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
