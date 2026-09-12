import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';
import '../../core/rtc/rtc_video_view.dart';
import '../../core/ui/ds_tokens.dart';
import '../../core/ui/overlay_icon_button.dart';
import '../../core/ui/participant_volume_popover.dart';
import 'voice_providers.dart';

/// Papel de um tile de vídeo no painel — define a qualidade de recepção
/// aplicada ao participante remoto (regra da Fase 5): spotlight → high,
/// grid → medium, miniatura → low.
enum VoiceVideoTileRole { spotlight, grid, miniature }

/// Cada publicação visual vira um tile próprio. Assim câmera e tela do mesmo
/// participante podem aparecer lado a lado no mesmo grid.
enum VoiceVideoSource { camera, screen, avatar }

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
    this.qualityLabel,
    this.onExpand,
    this.isFullscreen = false,
  });

  /// Identificação do canal (chave do [voiceControllerProvider]).
  final ({String serverId, String channelId}) arg;

  final RtcParticipant participant;

  final VoiceVideoTileRole role;

  final VoiceVideoSource source;

  /// Ação de toque: grid/miniatura → destaque, destaque → grid. A screen
  /// decide quem pode (tile sem câmera não vira spotlight — toque ignorado).
  final VoidCallback? onTap;

  /// Rótulo da qualidade transmitida pelo LOCAL (ex.: `1080p60`); nulo
  /// quando desconhecido. Só renderiza no tile de tela do participante
  /// local — remoto exibe só o badge LIVE (fallback honesto, sem chutar).
  final String? qualityLabel;

  /// Ação de expandir do overlay de transmissão (top-right). Grid → vira
  /// spotlight; spotlight → takeover fullscreen. Nulo = sem botão.
  final VoidCallback? onExpand;

  /// Troca o ícone do botão expandir (fullscreen ↔ fullscreen_exit).
  final bool isFullscreen;

  @override
  ConsumerState<VoiceVideoTile> createState() => _VoiceVideoTileState();
}

class _VoiceVideoTileState extends ConsumerState<VoiceVideoTile> {
  @override
  void initState() {
    super.initState();
    _scheduleQuality();
  }

  @override
  void didUpdateWidget(VoiceVideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Mudou de papel (grid→spotlight/miniatura, etc.) ou de participante:
    // a transição de papel é o que dispara a mudança de qualidade.
    if (oldWidget.role != widget.role ||
        oldWidget.participant.id != widget.participant.id ||
        oldWidget.source != widget.source) {
      _scheduleQuality();
    }
  }

  /// Aplica a qualidade conforme o papel. Pós-frame (sem efeito colateral
  /// durante o build); seguro mesmo se o tile desmontar antes — o controller
  /// dedupe chamadas repetidas e ignora o participante local. Câmera e tela
  /// usam dedupes separados: a tela em destaque não rebaixa a câmera irmã
  /// em miniatura e vice-versa.
  void _scheduleQuality() {
    if (widget.source == VoiceVideoSource.avatar) return;
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
    final theme = Theme.of(context);
    final rtc = ref.read(rtcServiceProvider);
    final participant = widget.participant;
    final isLocal = participant.id == rtc.localParticipantId;
    final trackRef = switch (widget.source) {
      VoiceVideoSource.camera => rtc.videoTrackOf(participant.id),
      VoiceVideoSource.screen => rtc.screenTrackOf(participant.id),
      VoiceVideoSource.avatar => null,
    };
    final hasVideo = trackRef != null;
    final isMiniature = widget.role == VoiceVideoTileRole.miniature;

    final tile = GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
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
              _AvatarPlaceholder(participant: participant),
            if (isMiniature)
              _MiniatureOverlay(
                participant: participant,
                source: widget.source,
                showAvatar: hasVideo,
              )
            else
              _TileOverlay(
                participant: participant,
                source: widget.source,
                isLocal: isLocal,
                showAvatar: hasVideo,
              ),
            // Transmissão de tela (grid/spotlight): badge LIVE + qualidade
            // no top-left e expandir no top-right — sempre visível, como no
            // Discord. Nome do transmissor continua no badge inferior.
            if (widget.source == VoiceVideoSource.screen && !isMiniature)
              _TransmitTopOverlay(
                qualityLabel: isLocal ? widget.qualityLabel : null,
                isFullscreen: widget.isFullscreen,
                onExpand: widget.onExpand,
              ),
            // Active speaker: borda de 2px em primary (miniatura não tem).
            if (participant.isSpeaking && !isMiniature)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: isLocal
          ? tile
          : ParticipantVolumeMenuRegion(
              identity: participant.id,
              displayName: participant.name,
              child: tile,
            ),
    );
  }
}

/// Overlay completo (grid/spotlight): badge compacto com avatar + nome +
/// badge "Você" + volume individual, legível sobre o vídeo sem scrim cheia.
class _TileOverlay extends StatelessWidget {
  const _TileOverlay({
    required this.participant,
    required this.source,
    required this.isLocal,
    required this.showAvatar,
  });

  final RtcParticipant participant;
  final VoiceVideoSource source;
  final bool isLocal;

  /// Exibe a inicial sobre o vídeo. Com placeholder (sem vídeo), o avatar
  /// grande já identifica — mostrar de novo duplicaria.
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 8,
      bottom: 8,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTokens.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showAvatar) _NameAvatar(name: participant.name, radius: 14),
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
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                iconColor: AppTokens.textPrimary,
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
    );
  }
}

/// Overlay superior do tile de TRANSMISSÃO (só screen, grid/spotlight):
/// badge qualidade + LIVE no top-left, expandir no top-right. Sempre
/// visível (fora do auto-hide do palco) — espelha o Discord.
class _TransmitTopOverlay extends StatelessWidget {
  const _TransmitTopOverlay({
    required this.qualityLabel,
    required this.isFullscreen,
    required this.onExpand,
  });

  /// Qualidade conhecida do transmissor local; nulo no remoto (só LIVE).
  final String? qualityLabel;
  final bool isFullscreen;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 8,
      right: 8,
      top: 8,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTokens.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (qualityLabel != null) ...[
                    Text(
                      qualityLabel!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTokens.textSecondary,
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
    );
  }
}

/// Avatar circular com a inicial, cor cíclica por nome (tokens do app).
class _NameAvatar extends StatelessWidget {
  const _NameAvatar({required this.name, required this.radius});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = AppTokens.authorColors;
    final index = name.isEmpty
        ? 0
        : name.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
              colors.length;
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors[index],
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
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
  });

  final RtcParticipant participant;
  final VoiceVideoSource source;

  /// Mesmo motivo do [_TileOverlay.showAvatar]: sem vídeo, o placeholder
  /// já mostra o avatar grande.
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 6,
      bottom: 6,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 176),
        padding: const EdgeInsets.fromLTRB(3, 3, 7, 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTokens.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showAvatar) _NameAvatar(name: participant.name, radius: 9),
            if (showAvatar) const SizedBox(width: 5),
            Flexible(
              child: Text(
                participant.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
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

/// Placeholder de tile SEM vídeo: apenas o avatar circular com a inicial —
/// o estado "sem vídeo" já é sinalizado pelo badge superior e pelo overlay
/// com o nome (adaptação visual do `_ParticipantTile` da lista da Fase 4).
class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.participant});

  final RtcParticipant participant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = participant.name;
    return Container(
      key: const ValueKey('voice-video-placeholder'),
      decoration: BoxDecoration(
        color: AppTokens.surface1,
        border: Border.all(color: AppTokens.borderHairline),
      ),
      child: Stack(
        children: [
          const Positioned(left: 12, top: 12, child: _NoVideoBadge()),
          Center(
            child: CircleAvatar(
              radius: 32,
              backgroundColor: AppTokens.surface3,
              child: Text(
                name.isEmpty ? '?' : name[0].toUpperCase(),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: AppTokens.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoVideoBadge extends StatelessWidget {
  const _NoVideoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: AppTokens.surface2,
        borderRadius: AppRadius.brSm,
        border: Border.all(color: AppTokens.borderSubtle),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.videocam_off_outlined,
            size: 13,
            color: AppTokens.textSecondary,
          ),
          SizedBox(width: 5),
          Text(
            'Sem vídeo',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: AppTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
