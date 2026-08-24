import 'package:flutter/material.dart';

/// Ícone de ação compacto com tooltip e alvo tocável — usado em headers,
/// user panel e ações de linha. Default 44px (acessibilidade do wireframe
/// v3); painéis densos podem reduzir via [minSize].
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.iconSize = 18,
    this.minSize = 44,
    this.visualDensity = VisualDensity.compact,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;

  /// Lado mínimo do alvo tocável (default 44px).
  final double minSize;

  final VisualDensity visualDensity;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: iconSize),
      tooltip: tooltip,
      visualDensity: visualDensity,
      constraints: BoxConstraints(minWidth: minSize, minHeight: minSize),
      onPressed: onPressed,
    );
  }
}
