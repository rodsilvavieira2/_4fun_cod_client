import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'ds_tokens.dart';

/// Badge `SPOILER` estilo Discord: pill escura, texto 10-11px bold.
class SpoilerBadge extends StatelessWidget {
  const SpoilerBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppTokens.borderSubtle, width: 1),
      ),
      child: Text(
        'SPOILER',
        style: TextStyle(
          fontFamily: 'Geist',
          fontSize: compact ? 9 : 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: AppTokens.textPrimary,
        ),
      ),
    );
  }
}

/// Cobertura de spoiler: borra o filho e exibe badge + hint.
///
/// Usado no preview do composer (sempre borrado quando `isSpoiler`) e na
/// mensagem recebida (borrado até `revealed`). O `onReveal` é nulo no
/// composer — lá o olho da toolbar alterna o flag em vez de revelar por tap.
class SpoilerCover extends StatelessWidget {
  const SpoilerCover({
    super.key,
    required this.child,
    this.onReveal,
    this.revealHint = 'Clique para revelar',
    this.sigma = 14,
  });

  final Widget child;
  final VoidCallback? onReveal;
  final String revealHint;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: child,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SpoilerBadge(),
              const SizedBox(height: 6),
              AppIcon(
                AppIcons.view,
                size: 18,
                color: AppTokens.textPrimary,
              ),
              const SizedBox(height: 4),
              Text(
                revealHint,
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (onReveal != null)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onReveal,
                hoverColor: Colors.white.withValues(alpha: 0.04),
                child: Semantics(
                  button: true,
                  label: 'Imagem com spoiler, toque para revelar',
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
