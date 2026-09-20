import 'package:flutter/material.dart';

import '../../../core/theme/appearance_theme.dart';
import '../../../core/ui/app_icon.dart';

/// Toggle pill "Modo Teatro" compartilhado entre o header do modo default
/// (OFF → entrar) e o header do Modo Teatro (ON → sair).
///
/// Mesmo visual nos dois modos: pill com borda do accent, ícone + texto e
/// `Switch.adaptive`. Extraído para que os dois headers nunca divirjam.
class TheaterModeToggle extends StatelessWidget {
  const TheaterModeToggle({
    super.key,
    required this.value,
    required this.onToggle,
  });

  /// `false` = modo default (entrar); `true` = theater (sair).
  final bool value;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Tooltip(
      message: value ? 'Sair do Modo Teatro' : 'Entrar no Modo Teatro',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: colors.accent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.theater,
              size: 14,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              'Modo Teatro',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(width: 2),
            SizedBox(
              height: 26,
              child: FittedBox(
                child: Switch.adaptive(
                  value: value,
                  activeThumbColor: colors.accent,
                  onChanged: (_) => onToggle(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
