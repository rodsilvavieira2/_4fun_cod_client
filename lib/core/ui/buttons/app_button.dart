import 'package:flutter/material.dart';

import '../../theme/appearance_theme.dart';
import '../ds_tokens.dart';

enum AppButtonVariant {
  /// Assinatura Vercel: Fundo Branco (#EDEDED) com texto preto (#000000)
  primary,

  /// Secundário: Fundo #161616 com borda sutil e texto branco suave
  secondary,

  /// Acento: Azul elétrico Vercel (#0070F3) com texto branco
  accent,

  /// Ghost: Fundo transparente com hover sutil
  ghost,

  /// Destrutivo: Roxo/Violeta ou tom sutil de perigo
  danger,
}

enum AppButtonSize {
  /// Altura 28px - Barras de ferramentas, cabeçalhos compactos
  sm,

  /// Altura 34px - Padrão para formulários, ações de diálogo
  md,

  /// Altura 40px - Telas de login e ações de destaque
  lg,
}

/// Botão de alto padrão visual (macOS-like + Vercel)
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool expanded;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final disabled = widget.onPressed == null || widget.loading;

    // Dimensões por tamanho
    final (
      height,
      fontSize,
      iconSize,
      hPadding,
      radius,
    ) = switch (widget.size) {
      AppButtonSize.sm => (28.0, 12.0, 14.0, 10.0, AppRadius.sm),
      AppButtonSize.md => (34.0, 13.0, 16.0, 14.0, AppRadius.sm),
      AppButtonSize.lg => (40.0, 14.5, 18.0, 18.0, AppRadius.md),
    };

    // Cores por variante
    final (bgColor, fgColor, borderColor) = switch (widget.variant) {
      AppButtonVariant.primary => (
        disabled
            ? colors.surface3
            : (_pressed
                  ? colors.accent.withValues(alpha: 0.82)
                  : (_hovered
                        ? colors.accent.withValues(alpha: 0.92)
                        : colors.accent)),
        disabled ? colors.textMuted : colors.onAccent,
        Colors.transparent,
      ),
      AppButtonVariant.secondary => (
        disabled
            ? colors.surface1
            : (_pressed
                  ? colors.surface3
                  : (_hovered ? colors.hoverOverlay : colors.surface2)),
        disabled ? colors.textMuted : colors.textPrimary,
        colors.borderStrong,
      ),
      AppButtonVariant.accent => (
        disabled
            ? colors.surface3
            : (_pressed
                  ? colors.accent.withValues(alpha: 0.82)
                  : (_hovered
                        ? colors.accent.withValues(alpha: 0.92)
                        : colors.accent)),
        disabled ? colors.textMuted : colors.onAccent,
        Colors.transparent,
      ),
      AppButtonVariant.ghost => (
        disabled
            ? Colors.transparent
            : (_pressed
                  ? colors.activeOverlay
                  : (_hovered ? colors.hoverOverlay : Colors.transparent)),
        disabled ? colors.textMuted : colors.textPrimary,
        Colors.transparent,
      ),
      AppButtonVariant.danger => (
        disabled
            ? colors.surface1
            : (_pressed
                  ? const Color(0xFF6D28D9)
                  : (_hovered
                        ? const Color(0xFF9333EA)
                        : AppTokens.accentPurple)),
        disabled ? colors.textMuted : Colors.white,
        Colors.transparent,
      ),
    };

    Widget content = Row(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading) ...[
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fgColor),
            ),
          ),
          const SizedBox(width: 8),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: iconSize, color: fgColor),
          const SizedBox(width: 6),
        ],
        Text(
          widget.label,
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: fgColor,
            letterSpacing: -0.1,
          ),
        ),
        if (widget.trailingIcon != null && !widget.loading) ...[
          const SizedBox(width: 6),
          Icon(widget.trailingIcon, size: iconSize, color: fgColor),
        ],
      ],
    );

    return MouseRegion(
      cursor: disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
        onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
        onTapCancel: disabled ? null : () => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed && !disabled ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: height,
            padding: EdgeInsets.symmetric(horizontal: hPadding),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: borderColor, width: 1),
            ),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }
}
