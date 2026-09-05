import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';
import '../../core/rtc/rtc_video_view.dart';
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
///   ([didUpdateWidget]), agenda [VoiceController.applyTileQuality] com a
///   qualidade do papel — o controller dedupe e ignora o participante local.
///   Tile desmontado (invisível) não chama nada: OFF por omissão (não existe
///   [RtcVideoQuality.off] no contrato — o adaptive stream corta a recepção).
///   Para o sharer SEM câmera o `setQuality` do serviço é no-op silencioso
///   (qualidade só existe para a publicação de câmera — fato do contrato).
class VoiceVideoTile extends ConsumerStatefulWidget {
  const VoiceVideoTile({
    super.key,
    required this.arg,
    required this.participant,
    required this.role,
    required this.source,
    this.onTap,
  });

  /// Identificação do canal (chave do [voiceControllerProvider]).
  final ({String serverId, String channelId}) arg;

  final RtcParticipant participant;

  final VoiceVideoTileRole role;

  final VoiceVideoSource source;

  /// Ação de toque: grid/miniatura → destaque, destaque → grid. A screen
  /// decide quem pode (tile sem câmera não vira spotlight — toque ignorado).
  final VoidCallback? onTap;

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
  /// dedupe chamadas repetidas e ignora o participante local.
  void _scheduleQuality() {
    // O contrato de qualidade remota controla a publicação de câmera. Uma
    // tela em destaque não deve rebaixar a câmera irmã que está em miniatura.
    if (widget.source != VoiceVideoSource.camera) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final quality = switch (widget.role) {
        VoiceVideoTileRole.spotlight => RtcVideoQuality.high,
        VoiceVideoTileRole.grid => RtcVideoQuality.medium,
        VoiceVideoTileRole.miniature => RtcVideoQuality.low,
      };
      ref
          .read(voiceControllerProvider(widget.arg).notifier)
          .applyTileQuality(widget.participant.id, quality);
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

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasVideo)
              RtcVideoView(trackRef: trackRef)
            else
              _AvatarPlaceholder(participant: participant),
            if (isMiniature)
              _MiniatureOverlay(participant: participant, source: widget.source)
            else
              _TileOverlay(
                participant: participant,
                source: widget.source,
                isLocal: isLocal,
              ),
            // Active speaker: borda de 2px em primary (miniatura não tem).
            if (participant.isSpeaking && !isMiniature)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
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
  }
}

/// Overlay completo (grid/spotlight): nome + badge "Você" + ícone de mic,
/// com scrim leve para legibilidade sobre o vídeo.
class _TileOverlay extends StatelessWidget {
  const _TileOverlay({
    required this.participant,
    required this.source,
    required this.isLocal,
  });

  final RtcParticipant participant;
  final VoiceVideoSource source;
  final bool isLocal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black54],
          ),
        ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                source == VoiceVideoSource.screen
                    ? 'Tela de ${participant.name}'
                    : participant.name,
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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Você',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
            // Badge de share: ao lado do ícone de mic (antes dele).
            if (source == VoiceVideoSource.screen) ...[
              const SizedBox(width: 6),
              const Icon(Icons.present_to_all, size: 14, color: Colors.white),
            ],
            // Badge de áudio de sistema (Fase 6.1): quem transmite som de
            // jogos/vídeos/música junto com a tela.
            if (participant.isSystemAudioEnabled) ...[
              const SizedBox(width: 6),
              const Icon(Icons.volume_up, size: 14, color: Colors.white),
            ],
            const SizedBox(width: 6),
            Icon(
              participant.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
              size: 14,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

/// Overlay enxuto da miniatura: apenas o nome, com scrim leve (sem badge).
class _MiniatureOverlay extends StatelessWidget {
  const _MiniatureOverlay({required this.participant, required this.source});

  final RtcParticipant participant;
  final VoiceVideoSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black45],
          ),
        ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                source == VoiceVideoSource.screen
                    ? 'Tela de ${participant.name}'
                    : participant.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                ),
              ),
            ),
            // Badge de share: ao lado do nome na miniatura.
            if (source == VoiceVideoSource.screen) ...[
              const SizedBox(width: 6),
              const Icon(Icons.present_to_all, size: 14, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholder de tile SEM vídeo: avatar circular com a inicial + nome
/// (adaptação visual do `_ParticipantTile` da lista da Fase 4).
class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.participant});

  final RtcParticipant participant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = participant.name;
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
