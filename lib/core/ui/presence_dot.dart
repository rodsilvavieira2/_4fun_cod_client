import 'package:flutter/material.dart';

import 'ds_tokens.dart';

enum PresenceStatus {
  online,
  idle,
  dnd,
  offline,
}

/// Indicador visual de presença estilo macOS / Discord refinado (com anel de borda)
class PresenceDot extends StatelessWidget {
  const PresenceDot({
    super.key,
    this.online,
    this.status,
    this.size = 10,
    this.withBorder = true,
  });

  /// Compatibilidade boolean
  final bool? online;
  final PresenceStatus? status;
  final double size;
  final bool withBorder;

  @override
  Widget build(BuildContext context) {
    final effectiveStatus = status ?? ((online ?? false) ? PresenceStatus.online : PresenceStatus.offline);

    final (color, label) = switch (effectiveStatus) {
      PresenceStatus.online => (AppTokens.accentGreen, 'Online'),
      PresenceStatus.idle => (AppTokens.accentAmber, 'Ausente'),
      PresenceStatus.dnd => (AppTokens.accentPurple, 'Não perturbe'),
      PresenceStatus.offline => (AppTokens.accentOffline, 'Offline'),
    };

    return Tooltip(
      message: label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: withBorder
              ? Border.all(color: AppTokens.surface1, width: size > 10 ? 2 : 1.5)
              : null,
        ),
      ),
    );
  }
}
