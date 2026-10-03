import 'package:flutter/material.dart';

import '../../theme/appearance_theme.dart';

/// Slider do design system com inset horizontal determinístico.
///
/// O [Slider] do Material, quando `padding` é nulo, reserva nas laterais
/// `max(thumb, overlay)` para a trilha (ex.: 14px com thumb 8 / overlay 14).
/// Esse inset invisível se somava ao `SizedBox` vizinho e criava o gap
/// fantasma entre ícone e trilha. Aqui o padding é explícito (8px), então o
/// espaço entre o conteúdo vizinho e a trilha é exatamente o padding.
class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.trackHeight = 4,
    this.thumbRadius = 8,
    this.overlayRadius = 14,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.thumbColor,
    this.overlayColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final double trackHeight;
  final double thumbRadius;
  final double overlayRadius;
  final Color? activeTrackColor;
  final Color? inactiveTrackColor;
  final Color? thumbColor;
  final Color? overlayColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.appColors;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: trackHeight,
        activeTrackColor: activeTrackColor ?? palette.accent,
        inactiveTrackColor: inactiveTrackColor ?? palette.borderStrong,
        thumbColor: thumbColor ?? palette.textPrimary,
        overlayColor:
            overlayColor ?? palette.accent.withValues(alpha: 0.16),
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: thumbRadius,
          disabledThumbRadius: thumbRadius,
        ),
        overlayShape: RoundSliderOverlayShape(
          overlayRadius: overlayRadius,
        ),
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        padding: padding,
        onChanged: onChanged,
      ),
    );
  }
}
