import 'dart:ui';
import 'package:flutter/material.dart';

import '../../theme/appearance_theme.dart';
import '../ds_tokens.dart';

/// Painel translúcido estilo Frosted Glass do macOS
class AppGlassPanel extends StatelessWidget {
  const AppGlassPanel({
    super.key,
    required this.child,
    this.blur = 16.0,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.padding,
    this.margin,
    this.width,
    this.height,
  });

  final Widget child;
  final double blur;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(AppRadius.lg);
    final effectiveBackground = backgroundColor ?? colors.surfaceGlass;
    final effectiveBorder = borderColor ?? colors.borderHairline;

    return Container(
      width: width,
      height: height,
      margin: margin,
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: effectiveBackground,
              borderRadius: effectiveRadius,
              border: Border.all(color: effectiveBorder, width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Card de superfície estilo Vercel Dark com bordas sutis
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(AppRadius.lg);

    final cardWidget = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surface2,
        borderRadius: effectiveRadius,
        border: Border.all(
          color: borderColor ?? colors.borderHairline,
          width: 1,
        ),
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: effectiveRadius,
        child: cardWidget,
      );
    }

    return cardWidget;
  }
}
