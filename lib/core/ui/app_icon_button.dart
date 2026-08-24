import 'package:flutter/material.dart';

/// Ícone de ação compacto com tooltip e alvo tocável ≥44px (acessibilidade
/// do wireframe v3) — usado em headers, user panel e ações de linha.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.iconSize = 18,
    this.visualDensity = VisualDensity.compact,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;
  final VisualDensity visualDensity;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: iconSize),
      tooltip: tooltip,
      visualDensity: visualDensity,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      onPressed: onPressed,
    );
  }
}
