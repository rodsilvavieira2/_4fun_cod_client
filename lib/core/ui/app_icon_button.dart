import 'package:flutter/material.dart';

import 'ds_tokens.dart';

/// Ícone de ação compacto estilo macOS com tooltip e feedback suave
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.iconSize = 16,
    this.minSize = 28,
    this.color,
    this.activeColor,
    this.isActive = false,
    this.visualDensity = VisualDensity.compact,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double iconSize;
  final double minSize;
  final Color? color;
  final Color? activeColor;
  final bool isActive;
  final VisualDensity visualDensity;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.isActive
        ? (widget.activeColor ?? AppTokens.accentVercel)
        : (_hovered ? AppTokens.textPrimary : (widget.color ?? AppTokens.textSecondary));

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.onPressed == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: widget.minSize,
            height: widget.minSize,
            decoration: BoxDecoration(
              color: widget.isActive
                  ? AppTokens.activeOverlay
                  : (_hovered ? AppTokens.hoverOverlay : Colors.transparent),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: widget.iconSize,
              color: effectiveColor,
            ),
          ),
        ),
      ),
    );
  }
}
