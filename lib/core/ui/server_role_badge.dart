import 'package:flutter/material.dart';

import '../../shared/models/servers.dart';
import 'ds_tokens.dart';

/// Identificação visual única dos papéis de servidor, usada nas listas e na
/// administração de membros.
class ServerRoleBadge extends StatelessWidget {
  const ServerRoleBadge({super.key, required this.role, this.showLabel = true});

  final ServerRole role;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      ServerRole.owner => AppTokens.accentAmber,
      ServerRole.admin => AppTokens.accentPurple,
      ServerRole.member => AppTokens.textMuted,
    };
    final icon = switch (role) {
      ServerRole.owner => Icons.workspace_premium_outlined,
      ServerRole.admin => Icons.shield_outlined,
      ServerRole.member => Icons.person_outline,
    };
    return Tooltip(
      message: '${role.label}: ${role.description}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 7 : 4,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            if (showLabel) ...[
              const SizedBox(width: 4),
              Text(
                role.label,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
