import 'package:flutter/material.dart';

import '../theme/appearance_theme.dart';
import 'ds_tokens.dart';

/// Pill "voltar ao presente" estilo Discord: informa que o usuário está
/// vendo mensagens antigas e oferece retorno animado às mais novas.
///
/// Cores via [AppThemePalette] (`context.appColors`) para acompanhar o
/// tema dinâmico (presets + seed customizada). Uso: overlay topo-centro
/// (`Stack` + `Positioned`) sobre listas `reverse: true`, com visibilidade
/// controlada pelo pai via `AnimatedOpacity` + `IgnorePointer`.
class JumpToPresentPill extends StatelessWidget {
  const JumpToPresentPill({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Semantics(
        button: true,
        label: 'Voltar ao presente',
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: InkWell(
            onTap: onPressed,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surface2.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: colors.borderSubtle, width: 1),
                boxShadow: AppShadows.popover,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Você está vendo mensagens antigas',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Voltar ao presente',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
