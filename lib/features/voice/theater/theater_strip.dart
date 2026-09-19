import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/rtc/rtc_service.dart';
import '../../../core/theme/appearance_theme.dart';
import '../../../core/ui/app_icon.dart';
import '../voice_providers.dart';
import 'theater_stage.dart' show kTheaterRailGap;
import 'theater_ui_provider.dart';

/// Faixa de participantes sem stream (avatar compacto). Respeita o toggle
/// `Mostrar participantes` do menu `⋯`; escondida quando `hideOverlays`.
class TheaterStrip extends ConsumerWidget {
  const TheaterStrip({super.key, required this.arg});

  final ({String serverId, String channelId}) arg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider(arg));
    final ui = ref.watch(theaterUiControllerProvider(arg));
    if (!ui.showParticipants || ui.hideOverlays) {
      return const SizedBox.shrink();
    }
    final idle = [
      for (final p in voice.participants)
        if (!p.isScreenSharing && !p.isCameraEnabled) p,
    ];
    if (idle.isEmpty) return const SizedBox.shrink();
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.only(top: kTheaterRailGap),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: idle.length,
          separatorBuilder: (_, _) => const SizedBox(width: kTheaterRailGap),
          itemBuilder: (context, index) {
            final p = idle[index];
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surfaceGlass,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Avatar(participant: p),
                  const SizedBox(width: 6),
                  Text(
                    p.name,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  if (p.isSpeaking) ...[
                    const SizedBox(width: 4),
                    AppIcon(AppIcons.wave, size: 12, color: colors.accent),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.participant});

  final RtcParticipant participant;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final initial = participant.name.isEmpty
        ? '?'
        : participant.name.characters.first.toUpperCase();
    return CircleAvatar(
      radius: 10,
      backgroundColor: colors.activeOverlay,
      child: Text(
        initial,
        style: TextStyle(fontSize: 10, color: colors.textPrimary),
      ),
    );
  }
}
