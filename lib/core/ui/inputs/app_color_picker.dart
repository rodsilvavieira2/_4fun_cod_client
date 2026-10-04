import 'package:flutter/material.dart';

import '../../theme/appearance_theme.dart';

/// Amostras com seleção visível e edição HEX opcional, sem abrir um novo modal.
class AppColorPicker extends StatefulWidget {
  const AppColorPicker({
    super.key,
    required this.label,
    required this.value,
    required this.swatches,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> swatches;
  final ValueChanged<String> onChanged;

  @override
  State<AppColorPicker> createState() => _AppColorPickerState();
}

class _AppColorPickerState extends State<AppColorPicker> {
  late final TextEditingController _hex = TextEditingController(
    text: widget.value ?? '',
  );
  late bool _editing =
      widget.value != null &&
      !widget.swatches.any(
        (color) => color.toUpperCase() == widget.value!.toUpperCase(),
      );
  String? _error;

  @override
  void didUpdateWidget(covariant AppColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _hex.text = widget.value ?? '';
      _error = null;
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _applyHex() {
    final value = _hex.text.trim().toUpperCase();
    if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(value)) {
      setState(() => _error = 'Use o formato #RRGGBB.');
      return;
    }
    setState(() {
      _error = null;
      _editing = false;
    });
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final custom =
        widget.value != null &&
        RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(widget.value!) &&
        !widget.swatches.any(
          (color) => color.toUpperCase() == widget.value!.toUpperCase(),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final hex in widget.swatches)
                _swatch(
                  hex,
                  selected: widget.value?.toUpperCase() == hex.toUpperCase(),
                  onPressed: () => widget.onChanged(hex),
                ),
              if (custom)
                _swatch(
                  widget.value!,
                  selected: true,
                  onPressed: () => setState(() => _editing = true),
                ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _editing = !_editing;
                  _error = null;
                }),
                icon: Icon(
                  _editing ? Icons.close : Icons.colorize_outlined,
                  size: 16,
                ),
                label: Text(_editing ? 'Fechar' : 'Personalizar'),
              ),
              if (widget.value == null)
                Text(
                  'Padrão',
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
            ],
          ),
          if (_editing) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hex,
                      maxLength: 7,
                      decoration: const InputDecoration(
                        hintText: '#RRGGBB',
                        counterText: '',
                        isDense: true,
                      ),
                      style: const TextStyle(
                        fontFamily: 'Geist Mono',
                        fontSize: 12,
                      ),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      onSubmitted: (_) => _applyHex(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _applyHex,
                    child: const Text('Aplicar'),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _swatch(
    String hex, {
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final color = Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
    final colors = context.appColors;
    return IconButton(
      tooltip: 'Cor $hex',
      onPressed: onPressed,
      icon: selected
          ? Icon(
              Icons.check,
              size: 17,
              color: color.computeLuminance() > 0.45
                  ? Colors.black
                  : Colors.white,
            )
          : const SizedBox.shrink(),
      style: ButtonStyle(
        fixedSize: const WidgetStatePropertyAll(Size(34, 34)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(color),
        side: WidgetStatePropertyAll(
          BorderSide(
            color: selected ? colors.textPrimary : colors.borderSubtle,
            width: selected ? 2 : 1,
          ),
        ),
        shape: const WidgetStatePropertyAll(CircleBorder()),
      ),
    );
  }
}
