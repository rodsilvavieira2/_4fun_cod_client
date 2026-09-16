import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';
import '../../core/rtc/rtc_video_view.dart';
import '../../core/theme/appearance_theme.dart';
import '../../core/ui/ds_tokens.dart';
import '../../core/ui/overlay_icon_button.dart';
import '../../core/ui/participant_volume_popover.dart';
import '../../core/ui/transmit_tile_toolbar.dart';
import 'voice_providers.dart';

/// Papel de um tile de vídeo no painel — define a qualidade de recepção
/// aplicada ao participante remoto (regra da Fase 5): spotlight → high,
/// grid → medium, miniatura → low.
enum VoiceVideoTileRole { spotlight, grid, miniature }

/// Cada publicação visual vira um tile próprio. Assim câmera e tela do mesmo
/// participante podem aparecer lado a lado no mesmo grid.
enum VoiceVideoSource { camera, screen, avatar }

const _miniatureShadows = <BoxShadow>[
  BoxShadow(
    color: Color(0x66000000),
    offset: Offset(0, 8),
    blurRadius: 18,
    spreadRadius: -8,
  ),
  BoxShadow(color: Color(0x33000000), offset: Offset(0, 1), blurRadius: 4),
];

const _goldenAngle = 137.50776405003785;

class _ParticipantVisualPalette {
  const _ParticipantVisualPalette({
    required this.base,
    required this.secondary,
    required this.highlight,
    required this.deep,
  });

  final Color base;
  final Color secondary;
  final Color highlight;
  final Color deep;
}

_ParticipantVisualPalette _paletteForParticipant(RtcParticipant participant) {
  final hash = _stableHash('${participant.id}|${participant.name}');
  final hue = ((hash % 1024) * _goldenAngle) % 360;
  final secondaryHue = (hue + 34 + ((hash >> 10) & 0x2F)) % 360;
  final highlightHue = (hue + 12 + ((hash >> 17) & 0x1F)) % 360;
  final deepHue = (hue + 334 + ((hash >> 24) & 0x19)) % 360;

  return _ParticipantVisualPalette(
    base: HSVColor.fromAHSV(1, hue, 0.44, 0.70).toColor(),
    secondary: HSVColor.fromAHSV(1, secondaryHue, 0.34, 0.60).toColor(),
    highlight: HSVColor.fromAHSV(1, highlightHue, 0.28, 0.82).toColor(),
    deep: HSVColor.fromAHSV(1, deepHue, 0.46, 0.20).toColor(),
  );
}

int _stableHash(String value) {
  const fnvPrime = 0x01000193;
  var hash = 0x811C9DC5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return hash;
}

/// Tile de vídeo de um participante (Fase 5 + Fase 6).
///
/// - Fonte do vídeo (Fase 6): no papel [VoiceVideoTileRole.spotlight], a
///   TELA tem prioridade sobre a câmera ([RtcService.screenTrackOf]); em
///   grid/miniatura a câmera vem primeiro ([RtcService.videoTrackOf]) e a
///   tela cobre só quem não tem câmera. Sem nenhuma → placeholder PRÓPRIO
///   da feature (avatar + nome) — nunca o placeholder interno do
///   [RtcVideoView] ([SizedBox.shrink]).
/// - Qualidade: ao assumir ([initState]) ou mudar de papel
///   ([didUpdateWidget]), agenda a qualidade do papel — câmera via
///   [VoiceController.applyTileQuality], tela via
///   [VoiceController.applyTileScreenQuality] (dedupes separados).
///   Tile desmontado (invisível) não chama nada: OFF por omissão (não existe
///   [RtcVideoQuality.off] no contrato — o adaptive stream corta a recepção).
class VoiceVideoTile extends ConsumerStatefulWidget {
  const VoiceVideoTile({
    super.key,
    required this.arg,
    required this.participant,
    required this.role,
    required this.source,
    this.onTap,
    this.onToggleWatch,
    this.onStopShare,
    this.qualityLabel,
    this.onExpand,
    this.isWatching = true,
    this.isFullscreen = false,
    this.overlayVisible = true,
  });

  /// Identificação do canal (chave do [voiceControllerProvider]).
  final ({String serverId, String channelId}) arg;

  final RtcParticipant participant;

  final VoiceVideoTileRole role;

  final VoiceVideoSource source;

  /// Ação de toque: grid/miniatura → destaque, destaque → grid. A screen
  /// decide quem pode (tile sem câmera não vira spotlight — toque ignorado).
  /// Toque NUNCA assiste/desassiste: assistir/parar vive só na toolbar
  /// ([onToggleWatch]) e no prompt central ([_WatchPrompt]).
  final VoidCallback? onTap;

  /// Assistir/parar a transmissão (remoto, exclusivo da toolbar + prompt).
  /// Nulo = sem botão de assistir na toolbar.
  final VoidCallback? onToggleWatch;

  /// Parar o compartilhamento local (toolbar do tile local). Nulo = sem botão.
  final VoidCallback? onStopShare;

  /// Rótulo da qualidade transmitida pelo LOCAL (ex.: `1080p60`); nulo
  /// quando desconhecido. Só renderiza no tile de tela do participante
  /// local — remoto exibe só o badge LIVE (fallback honesto, sem chutar).
  final String? qualityLabel;

  /// Ação de expandir do overlay de transmissão (top-right). Grid → vira
  /// spotlight; spotlight → takeover fullscreen. Nulo = sem botão.
  final VoidCallback? onExpand;

  /// Opt-in de vídeo (regra da sala): `true` renderiza o vídeo normalmente;
  /// `false` (remoto em live não assistido) mostra avatar + LIVE + "Assistir"
  /// SEM montar o [RtcVideoView] (sem banda). O local sempre chega `true`.
  final bool isWatching;

  /// Troca o ícone do botão expandir (fullscreen ↔ fullscreen_exit).
  final bool isFullscreen;

  /// Fullscreen imersivo: false esconde badges/overlays junto com o dock
  /// (fica só o vídeo) e oculta o cursor.
  final bool overlayVisible;

  @override
  ConsumerState<VoiceVideoTile> createState() => _VoiceVideoTileState();
}

class _VoiceVideoTileState extends ConsumerState<VoiceVideoTile> {
  /// Fade-out individual da toolbar (SPEC 2026-09-16): hover no tile revela,
  /// 2.5s parado esconde. Puro chrome de UI — mora no tile, não no controller.
  bool _toolbarVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleQuality();
    _scheduleToolbarHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleToolbarHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _toolbarVisible = false);
    });
  }

  void _revealToolbar() {
    _scheduleToolbarHide();
    if (!_toolbarVisible && mounted) setState(() => _toolbarVisible = true);
  }

  void _hideToolbarNow() {
    _hideTimer?.cancel();
    if (_toolbarVisible && mounted) setState(() => _toolbarVisible = false);
  }

  @override
  void didUpdateWidget(VoiceVideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mudou de papel (grid→spotlight/miniatura, etc.), de participante ou de
    // opt-in (começou/parou de assistir): papel e assistir disparam qualidade.
    if (oldWidget.role != widget.role ||
        oldWidget.participant.id != widget.participant.id ||
        oldWidget.source != widget.source ||
        oldWidget.isWatching != widget.isWatching) {
      _scheduleQuality();
    }
  }

  /// Aplica a qualidade conforme o papel. Pós-frame (sem efeito colateral
  /// durante o build); seguro mesmo se o tile desmontar antes — o controller
  /// dedupe chamadas repetidas e ignora o participante local. Câmera e tela
  /// usam dedupes separados: a tela em destaque não rebaixa a câmera irmã
  /// em miniatura e vice-versa. Tile não assistido não pede qualidade (sem
  /// view montada, o adaptive stream já corta a recepção).
  void _scheduleQuality() {
    if (widget.source == VoiceVideoSource.avatar) return;
    if (!widget.isWatching) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final quality = switch (widget.role) {
        VoiceVideoTileRole.spotlight => RtcVideoQuality.high,
        VoiceVideoTileRole.grid => RtcVideoQuality.medium,
        VoiceVideoTileRole.miniature => RtcVideoQuality.low,
      };
      final controller = ref.read(voiceControllerProvider(widget.arg).notifier);
      if (widget.source == VoiceVideoSource.screen) {
        controller.applyTileScreenQuality(widget.participant.id, quality);
      } else {
        controller.applyTileQuality(widget.participant.id, quality);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final rtc = ref.read(rtcServiceProvider);
    final participant = widget.participant;
    final isLocal = participant.id == rtc.localParticipantId;
    // Local sempre mostra o próprio vídeo; remoto só após opt-in — sem
    // RtcVideoView montada, o adaptive stream corta a recepção (sem banda).
    final showVideo = isLocal || widget.isWatching;
    final trackRef = !showVideo
        ? null
        : switch (widget.source) {
            VoiceVideoSource.camera => rtc.videoTrackOf(participant.id),
            VoiceVideoSource.screen => rtc.screenTrackOf(participant.id),
            VoiceVideoSource.avatar => null,
          };
    final hasVideo = trackRef != null;
    // Remoto em live que não estou assistindo: avatar + LIVE + "Assistir".
    final liveUnwatched =
        !showVideo && widget.source != VoiceVideoSource.avatar;
    final isMiniature = widget.role == VoiceVideoTileRole.miniature;
    final palette = _paletteForParticipant(participant);
    final tileRadius = BorderRadius.circular(AppRadius.lg);
    final frameColor = participant.isSpeaking
        ? palette.base
        : isMiniature
        ? colors.borderSubtle
        : colors.borderHairline;
    final frameWidth = participant.isSpeaking ? 2.0 : 1.0;

    final tile = GestureDetector(
      onTap: widget.onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: tileRadius,
          boxShadow: isMiniature ? _miniatureShadows : null,
        ),
        child: ClipRRect(
          borderRadius: tileRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasVideo)
                RtcVideoView(
                  trackRef: trackRef,
                  // Tela em destaque pede até 2x a densidade (960px → 1080p);
                  // demais casos seguem em auto para economizar banda.
                  highDensity:
                      widget.source == VoiceVideoSource.screen &&
                      widget.role == VoiceVideoTileRole.spotlight,
                )
              else
                _AvatarPlaceholder(
                  participant: participant,
                  compact: isMiniature,
                  speaking: participant.isSpeaking,
                  palette: palette,
                  liveUnwatched: liveUnwatched,
                ),
              // Opt-in: LIVE + "Assistir" sobre o avatar (grid/spotlight; na
              // miniatura o toque no tile já assiste — sem botão por espaço).
              // Assistir mora na toolbar: o prompt usa o mesmo callback (o
              // toque no tile só foca — nunca assiste).
              if (liveUnwatched && !isMiniature)
                _WatchPrompt(
                  source: widget.source,
                  onWatch: widget.onToggleWatch ?? widget.onTap,
                ),
              if (isMiniature) const _MiniatureBottomScrim(),
              if (isMiniature)
                _MiniatureOverlay(
                  participant: participant,
                  source: widget.source,
                  showAvatar: hasVideo,
                  palette: palette,
                )
              else
                _TileOverlay(
                  participant: participant,
                  source: widget.source,
                  isLocal: isLocal,
                  showAvatar: hasVideo,
                  palette: palette,
                  visible: widget.overlayVisible,
                ),
              // Transmissão de tela (grid/spotlight): badge LIVE + qualidade
              // no top-left e expandir no top-right — fora do fullscreen é
              // sempre visível (Discord); em fullscreen segue o auto-hide do
              // palco (some junto com o dock, fica só o vídeo).
              if (widget.source == VoiceVideoSource.screen && !isMiniature)
                _TransmitTopOverlay(
                  qualityLabel: isLocal ? widget.qualityLabel : null,
                  isFullscreen: widget.isFullscreen,
                  onExpand: widget.onExpand,
                  visible: widget.overlayVisible,
                ),
              // Toolbar individual da transmissão (grid/spotlight): mesma
              // aparência do dock global extinto, fade-out próprio por tile.
              if (widget.source == VoiceVideoSource.screen && !isMiniature)
                TransmitTileToolbar(
                  identity: participant.id,
                  displayName: participant.name,
                  isLocal: isLocal,
                  isWatching: widget.isWatching,
                  audioAvailable: participant.isSystemAudioEnabled,
                  onToggleWatch: widget.onToggleWatch,
                  onStopShare: widget.onStopShare,
                  visible: widget.overlayVisible && _toolbarVisible,
                ),
              // Moldura fixa para leitura sobre vídeo; fala ativa ganha primary.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: tileRadius,
                    border: Border.all(color: frameColor, width: frameWidth),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Estrutura IDÊNTICA com overlay visível ou oculto (só props mudam):
    // trocar o tipo do wrapper aqui desmontava a subárvore e recriava o
    // VideoTrackRenderer (textura nativa) — daí o "pisca" no hide/show.
    // O cursor none vai no MouseRegion MAIS interno: ele vence o `basic`
    // do FocusableActionDetector do menu de volume.
    final effectiveCursor = !widget.overlayVisible
        ? SystemMouseCursors.none
        : (widget.onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click);
    // Hover individual do tile: revela a toolbar e rearma o fade de 2.5s.
    final hasTileToolbar =
        widget.source == VoiceVideoSource.screen &&
        widget.role != VoiceVideoTileRole.miniature;
    final interactiveTile = MouseRegion(
      cursor: effectiveCursor,
      onEnter: hasTileToolbar ? (_) => _revealToolbar() : null,
      onHover: hasTileToolbar ? (_) => _revealToolbar() : null,
      onExit: hasTileToolbar ? (_) => _hideToolbarNow() : null,
      child: tile,
    );
    return isLocal
        ? interactiveTile
        : ParticipantVolumeMenuRegion(
            identity: participant.id,
            displayName: participant.name,
            // Escondido: sem menu de volume sobre o vídeo puro (só prop).
            enabled: widget.overlayVisible,
            child: interactiveTile,
          );
  }
}

class _MiniatureBottomScrim extends StatelessWidget {
  const _MiniatureBottomScrim();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0x12000000), Color(0xC4000000)],
            stops: [0.38, 0.64, 1],
          ),
        ),
      ),
    );
  }
}

String _initialFor(String name) => name.isEmpty ? '?' : name[0].toUpperCase();

/// Overlay completo (grid/spotlight): badge compacto com avatar + nome +
/// badge "Você" + volume individual, legível sobre o vídeo sem scrim cheia.
class _TileOverlay extends StatelessWidget {
  const _TileOverlay({
    required this.participant,
    required this.source,
    required this.isLocal,
    required this.showAvatar,
    required this.palette,
    this.visible = true,
  });

  final RtcParticipant participant;
  final VoiceVideoSource source;
  final bool isLocal;
  final _ParticipantVisualPalette palette;

  /// Exibe a inicial sobre o vídeo. Com placeholder (sem vídeo), o avatar
  /// grande já identifica — mostrar de novo duplicaria.
  final bool showAvatar;

  /// Fullscreen imersivo: false some com fade (fica só o vídeo).
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    return Positioned(
      left: 8,
      bottom: 8,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 240),
            padding: EdgeInsets.fromLTRB(showAvatar ? 3 : 10, 3, 8, 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showAvatar)
                  _NameAvatar(
                    name: participant.name,
                    radius: 14,
                    accent: palette.base,
                  ),
                if (showAvatar) const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    participant.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isLocal) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Você',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
                // Volume da fonte do tile: tela controla a transmissão, câmera
                // controla a voz — um nunca afeta o outro.
                if (!isLocal)
                  ParticipantVolumeButton(
                    identity: participant.id,
                    displayName: participant.name,
                    source: source == VoiceVideoSource.screen
                        ? RtcAudioSource.screenShareAudio
                        : RtcAudioSource.microphone,
                    // Sem track de áudio na transmissão, o controle mostra mutado.
                    audioAvailable: source == VoiceVideoSource.screen
                        ? participant.isSystemAudioEnabled
                        : null,
                    iconColor: colors.textPrimary,
                    iconSize: 15.4,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Overlay superior do tile de TRANSMISSÃO (só screen, grid/spotlight):
/// badge qualidade + LIVE no top-left, expandir no top-right. Fora do
/// fullscreen é sempre visível (Discord); em fullscreen segue o auto-hide.
class _TransmitTopOverlay extends StatelessWidget {
  const _TransmitTopOverlay({
    required this.qualityLabel,
    required this.isFullscreen,
    required this.onExpand,
    this.visible = true,
  });

  /// Qualidade conhecida do transmissor local; nulo no remoto (só LIVE).
  final String? qualityLabel;
  final bool isFullscreen;
  final VoidCallback? onExpand;

  /// Fullscreen imersivo: false some com fade (fica só o vídeo).
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    return Positioned(
      left: 8,
      right: 8,
      top: 8,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (qualityLabel != null) ...[
                        Text(
                          qualityLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTokens.accentDanger,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'LIVE',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (onExpand != null)
                OverlayIconButton(
                  icon: isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  tooltip: isFullscreen
                      ? 'Sair do fullscreen'
                      : 'Expandir transmissão',
                  onPressed: onExpand,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar circular com a inicial, cor cíclica por nome (tokens do app).
class _NameAvatar extends StatelessWidget {
  const _NameAvatar({
    required this.name,
    required this.radius,
    required this.accent,
  });

  final String name;
  final double radius;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: accent,
      child: Text(
        _initialFor(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.95,
          fontWeight: FontWeight.w700,
          fontFamily: 'Geist',
        ),
      ),
    );
  }
}

/// Overlay enxuto da miniatura: pill com avatar + nome (sem badge).
class _MiniatureOverlay extends StatelessWidget {
  const _MiniatureOverlay({
    required this.participant,
    required this.source,
    required this.showAvatar,
    required this.palette,
  });

  final RtcParticipant participant;
  final VoiceVideoSource source;
  final _ParticipantVisualPalette palette;

  /// Mesmo motivo do [_TileOverlay.showAvatar]: sem vídeo, o placeholder
  /// já mostra o avatar grande.
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    return Positioned(
      left: 8,
      bottom: 8,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 176),
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showAvatar)
              _NameAvatar(
                name: participant.name,
                radius: 10,
                accent: palette.base,
              ),
            if (showAvatar) const SizedBox(width: 6),
            Flexible(
              child: Text(
                participant.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Badge de share: ao lado do nome na miniatura.
            if (source == VoiceVideoSource.screen) ...[
              const SizedBox(width: 5),
              const Icon(Icons.present_to_all, size: 12, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlaceholderGradientWash extends StatelessWidget {
  const _PlaceholderGradientWash({
    required this.palette,
    required this.compact,
    required this.speaking,
  });

  final _ParticipantVisualPalette palette;
  final bool compact;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final boost = speaking ? 1.14 : 1.0;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.72, -0.86),
                radius: compact ? 0.86 : 0.72,
                colors: [
                  palette.highlight.withValues(
                    alpha: (compact ? 0.09 : 0.10) * boost,
                  ),
                  palette.base.withValues(alpha: compact ? 0.035 : 0.045),
                  Colors.transparent,
                ],
                stops: const [0, 0.46, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.82, 0.72),
                radius: compact ? 1.08 : 0.92,
                colors: [
                  palette.secondary.withValues(alpha: compact ? 0.055 : 0.07),
                  Colors.transparent,
                ],
                stops: const [0, 0.96],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.018),
                  Colors.transparent,
                  Colors.black.withValues(alpha: compact ? 0.28 : 0.34),
                ],
                stops: const [0, 0.52, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderAvatar extends StatelessWidget {
  const _PlaceholderAvatar({
    required this.name,
    required this.compact,
    required this.speaking,
    required this.palette,
  });

  final String name;
  final bool compact;
  final bool speaking;
  final _ParticipantVisualPalette palette;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = compact ? 30.0 : 42.0;
    final diameter = radius * 2;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              palette.highlight.withValues(alpha: 0.48),
              colors.surface3,
            ),
            Color.alphaBlend(
              palette.base.withValues(alpha: 0.62),
              colors.surface3,
            ),
            Color.alphaBlend(
              palette.deep.withValues(alpha: 0.52),
              colors.surface3,
            ),
          ],
          stops: const [0, 0.62, 1],
        ),
        border: Border.all(
          color: speaking
              ? palette.highlight.withValues(alpha: 0.72)
              : Colors.white.withValues(alpha: 0.07),
          width: speaking ? 1.25 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.base.withValues(
              alpha: speaking
                  ? compact
                        ? 0.28
                        : 0.34
                  : compact
                  ? 0.12
                  : 0.16,
            ),
            blurRadius: speaking
                ? compact
                      ? 22
                      : 30
                : compact
                ? 14
                : 22,
            spreadRadius: compact ? -3 : -6,
          ),
          const BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 10),
            blurRadius: 24,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Center(
        child: Text(
          _initialFor(name),
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: compact ? 28 : 36,
            fontWeight: FontWeight.w700,
            fontFamily: 'Geist',
          ),
        ),
      ),
    );
  }
}

/// Prompt de opt-in sobre o avatar de um remoto em live não assistido:
/// pill LIVE + botão "Assistir" (mesma ação do toque no tile). O fundo é o
/// avatar do placeholder — nunca um frame real (frame exigiria subscribe e
/// quebraria o opt-in).
class _WatchPrompt extends StatelessWidget {
  const _WatchPrompt({required this.source, required this.onWatch});

  final VoiceVideoSource source;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTokens.accentDanger,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'LIVE',
              style: theme.textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onWatch,
            icon: Icon(
              source == VoiceVideoSource.screen
                  ? Icons.present_to_all
                  : Icons.videocam,
              size: 18,
            ),
            label: const Text('Assistir'),
          ),
        ],
      ),
    );
  }
}

/// Placeholder de tile SEM vídeo: avatar central com profundidade e badge de
/// estado, preservando a identificação pelo overlay de nome.
class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({
    required this.participant,
    required this.compact,
    required this.speaking,
    required this.palette,
    this.liveUnwatched = false,
  });

  final RtcParticipant participant;
  final bool compact;
  final bool speaking;
  final _ParticipantVisualPalette palette;

  /// Remoto em live não assistido: esconde o badge "Sem vídeo" (há vídeo —
  /// só não estou assinando) e o prompt LIVE + "Assistir" assume o estado.
  final bool liveUnwatched;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final name = participant.name;
    return Container(
      key: const ValueKey('voice-video-placeholder'),
      decoration: BoxDecoration(
        color: colors.surface1,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              palette.base.withValues(alpha: compact ? 0.055 : 0.07),
              colors.surface2,
            ),
            Color.alphaBlend(
              palette.secondary.withValues(alpha: compact ? 0.035 : 0.045),
              colors.surface1,
            ),
            Color.alphaBlend(
              palette.deep.withValues(alpha: compact ? 0.12 : 0.16),
              colors.surfaceBase,
            ),
          ],
          stops: const [0, 0.58, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: _PlaceholderGradientWash(
              palette: palette,
              compact: compact,
              speaking: speaking,
            ),
          ),
          if (!compact && !liveUnwatched)
            Positioned(
              left: 12,
              top: 12,
              child: _NoVideoBadge(compact: compact),
            ),
          Center(
            child: Transform.translate(
              offset: const Offset(0, -8),
              child: SizedBox.square(
                dimension: compact ? 100 : 136,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _SpeakingAvatarPulse(
                      active: speaking,
                      palette: palette,
                      compact: compact,
                    ),
                    _PlaceholderAvatar(
                      name: name,
                      compact: compact,
                      speaking: speaking,
                      palette: palette,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeakingAvatarPulse extends StatefulWidget {
  const _SpeakingAvatarPulse({
    required this.active,
    required this.palette,
    required this.compact,
  });

  final bool active;
  final _ParticipantVisualPalette palette;
  final bool compact;

  @override
  State<_SpeakingAvatarPulse> createState() => _SpeakingAvatarPulseState();
}

class _SpeakingAvatarPulseState extends State<_SpeakingAvatarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_SpeakingAvatarPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();

    return RepaintBoundary(
      key: const ValueKey('voice-speaking-avatar-pulse'),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _SpeakingPulsePainter(
              progress: _controller.value,
              palette: widget.palette,
              compact: widget.compact,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

class _SpeakingPulsePainter extends CustomPainter {
  const _SpeakingPulsePainter({
    required this.progress,
    required this.palette,
    required this.compact,
  });

  final double progress;
  final _ParticipantVisualPalette palette;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final baseRadius = compact ? 30.0 : 42.0;
    final travel = compact ? 18.0 : 26.0;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [
          palette.highlight.withValues(alpha: 0.07),
          palette.base.withValues(alpha: 0.035),
          Colors.transparent,
        ],
        stops: const [0, 0.58, 1],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius + 12));
    canvas.drawCircle(center, baseRadius + 4, fill);

    for (final wave in [progress, (progress + 0.48) % 1]) {
      final eased = Curves.easeOutCubic.transform(wave);
      final radius = baseRadius + travel * eased;
      final opacity = (1 - eased) * 0.38;
      final strokeWidth = (compact ? 2.2 : 2.8) - eased;
      final ringRect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth.clamp(1.0, 3.0)
        ..shader = SweepGradient(
          colors: [
            palette.highlight.withValues(alpha: opacity.clamp(0.0, 0.38)),
            palette.base.withValues(alpha: (opacity * 0.74).clamp(0.0, 0.28)),
            palette.secondary.withValues(
              alpha: (opacity * 0.56).clamp(0.0, 0.22),
            ),
            palette.highlight.withValues(alpha: opacity.clamp(0.0, 0.38)),
          ],
          stops: const [0, 0.36, 0.74, 1],
        ).createShader(ringRect);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_SpeakingPulsePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.palette != palette ||
        oldDelegate.compact != compact;
  }
}

class _NoVideoBadge extends StatelessWidget {
  const _NoVideoBadge({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 7,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        borderRadius: AppRadius.brSm,
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.videocam_off_outlined,
            size: compact ? 12 : 13,
            color: colors.textSecondary,
          ),
          SizedBox(width: compact ? 4 : 5),
          Text(
            'Sem vídeo',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: compact ? 10 : 10.5,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
