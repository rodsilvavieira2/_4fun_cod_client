import 'package:flutter/material.dart';

import '../../theme/appearance_theme.dart';
import '../app_icon.dart';
import '../ds_tokens.dart';

enum AppBadgeVariant { neutral, accent, success, warning, danger }

/// Badge compacta com tipografia mono estilo Vercel / Dev-Tool
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.variant = AppBadgeVariant.neutral,
    this.icon,
  });

  final String label;
  final AppBadgeVariant variant;
  final List<List<dynamic>>? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (bgColor, fgColor, borderColor) = switch (variant) {
      AppBadgeVariant.neutral => (
        colors.surface3,
        colors.textSecondary,
        colors.borderHairline,
      ),
      AppBadgeVariant.accent => (
        colors.accent.withValues(alpha: 0.14),
        colors.accent,
        colors.accent.withValues(alpha: 0.30),
      ),
      AppBadgeVariant.success => (
        const Color(0x1F46A758),
        AppTokens.accentGreen,
        const Color(0x4D46A758),
      ),
      AppBadgeVariant.warning => (
        const Color(0x1FF5A623),
        AppTokens.accentAmber,
        const Color(0x4DF5A623),
      ),
      AppBadgeVariant.danger => (
        const Color(0x1F8B5CF6),
        AppTokens.accentPurple,
        const Color(0x4D8B5CF6),
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: 10, color: fgColor),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: 'Geist Mono',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: fgColor,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
