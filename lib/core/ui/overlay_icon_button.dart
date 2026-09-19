import 'package:flutter/material.dart';

import '../theme/appearance_theme.dart';
import 'app_icon.dart';

/// Botão circular translúcido sobre vídeo (pill preta + borda sutil).
///
/// Extraído do header do palco de voz para reuso no overlay dos tiles de
/// transmissão — um só estilo de botão sobre vídeo no app.
class OverlayIconButton extends StatelessWidget {
  const OverlayIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 32,
  });

  final List<List<dynamic>> icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Diâmetro do botão (header usa 40, tile usa 32).
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: Size.square(size),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.black.withValues(alpha: 0.72),
        foregroundColor: colors.textPrimary,
        side: BorderSide(color: colors.borderSubtle),
      ),
      icon: AppIcon(icon, size: size * 0.5),
    );
  }
}
