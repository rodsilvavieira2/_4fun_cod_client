import 'package:flutter/material.dart';

import '../../theme/appearance_theme.dart';
import '../ds_tokens.dart';

class AppSelectOption<T> {
  const AppSelectOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// Select compacto com rótulo estável e menu que acompanha a largura do campo.
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder = 'Selecione',
  });

  final String? label;
  final T? value;
  final List<AppSelectOption<T>> options;
  final ValueChanged<T>? onChanged;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selected = options
        .where((option) => option.value == value)
        .firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final menuWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 240.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null) ...[
              Text(
                label!,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontFamily: 'Geist',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
            ],
            PopupMenuButton<T>(
              enabled: onChanged != null && options.isNotEmpty,
              tooltip: label == null ? 'Selecionar opção' : 'Selecionar $label',
              onSelected: onChanged,
              color: colors.surface3,
              surfaceTintColor: Colors.transparent,
              elevation: 12,
              offset: const Offset(0, 4),
              constraints: BoxConstraints(
                minWidth: menuWidth,
                maxWidth: menuWidth,
                maxHeight: 280,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                side: BorderSide(color: colors.borderSubtle),
              ),
              itemBuilder: (context) => [
                for (final option in options)
                  PopupMenuItem<T>(
                    value: option.value,
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontFamily: 'Geist',
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (option.value == value) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check, size: 16, color: colors.accent),
                        ],
                      ],
                    ),
                  ),
              ],
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    border: Border.all(color: colors.borderSubtle),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            selected?.label ?? placeholder,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Geist',
                              fontSize: 13,
                              color: selected == null
                                  ? colors.textSecondary
                                  : colors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
