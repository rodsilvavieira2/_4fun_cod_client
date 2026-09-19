import 'package:flutter/material.dart';

import '../../../core/rtc/rtc_service.dart';
import '../../../core/theme/appearance_theme.dart';
import '../../../core/ui/ds_tokens.dart';
import '../voice_video_tile.dart';

/// Tile reutilizável do Theater (câmera/tela, foco/secundário).
///
/// Mesma implementação para todas as posições — só mudam [isFocused],
/// [role] e o tamanho imposto pelo pai. Não duplica LiveKit/chat/áudio:
/// apenas emoldura o [VoiceVideoTile] existente com borda/clip do tema.
class TheaterStreamTile extends StatelessWidget {
  const TheaterStreamTile({
    super.key,
    required this.arg,
    required this.participant,
    required this.source,
    required this.role,
    required this.isFocused,
    required this.isWatching,
    this.onTap,
    this.onToggleWatch,
    this.onStopShare,
    this.onExpand,
    this.overlayVisible = true,
    this.qualityLabel,
  });

  final ({String serverId, String channelId}) arg;
  final RtcParticipant participant;
  final VoiceVideoSource source;
  final VoiceVideoTileRole role;
  final bool isFocused;
  final bool isWatching;
  final VoidCallback? onTap;
  final VoidCallback? onToggleWatch;
  final VoidCallback? onStopShare;
  final VoidCallback? onExpand;
  final bool overlayVisible;
  final String? qualityLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isFocused ? colors.accent : colors.borderSubtle,
          width: isFocused ? 1.5 : 1,
        ),
        color: colors.surface1,
      ),
      clipBehavior: Clip.antiAlias,
      child: VoiceVideoTile(
        arg: arg,
        participant: participant,
        source: source,
        role: role,
        isWatching: isWatching,
        onTap: onTap,
        onToggleWatch: onToggleWatch,
        onStopShare: onStopShare,
        onExpand: onExpand,
        overlayVisible: overlayVisible,
        qualityLabel: qualityLabel,
      ),
    );
  }
}
