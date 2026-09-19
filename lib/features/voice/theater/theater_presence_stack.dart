import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/appearance_theme.dart';
import '../voice_providers.dart';

/// Pilha compacta de presença do theater: até 3 avatares + `+N`.
///
/// A sobreposição usa [Stack]/[Positioned]: margem negativa em [Container]
/// quebra a assertion `margin.isNonNegative` do framework (regressão
/// capturada em 2026-09-19 — ver `theater_presence_stack_test.dart`).
class TheaterPresenceStack extends ConsumerWidget {
  const TheaterPresenceStack({super.key, required this.arg});

  final ({String serverId, String channelId}) arg;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceControllerProvider(arg));
    final total = voice.participants.length;
    if (total == 0) return const SizedBox.shrink();
    final shown = voice.participants.take(3).toList();
    final overflow = total - shown.length;
    final colors = context.appColors;
    final itemCount = shown.length + (overflow > 0 ? 1 : 0);
    return SizedBox(
      width: 24.0 + (itemCount - 1) * 18.0,
      height: 24,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 18.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface1, width: 2),
                ),
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: colors.activeOverlay,
                  child: Text(
                    shown[i].name.isEmpty
                        ? '?'
                        : shown[i].name.characters.first.toUpperCase(),
                    style: TextStyle(fontSize: 10, color: colors.textPrimary),
                  ),
                ),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: shown.length * 18.0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface1, width: 2),
                ),
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: colors.surface3,
                  child: Text(
                    '+$overflow',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
