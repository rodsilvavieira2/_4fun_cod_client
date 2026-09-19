import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings_section_layout.dart';
import '../ui.dart';

/// Aparência dark-only com cores Discord-like: presets prontos e cor custom
/// local ao desktop.
class AppearanceSection extends ConsumerStatefulWidget {
  const AppearanceSection({super.key});

  @override
  ConsumerState<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends ConsumerState<AppearanceSection> {
  late final TextEditingController _hexController = TextEditingController();
  Color? _editingColor;
  String? _hexError;

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncPreferences = ref.watch(appearanceThemeProvider);
    final preferences =
        asyncPreferences.valueOrNull ?? AppearanceThemePreferences.defaults;
    final controller = ref.read(appearanceThemeProvider.notifier);
    final selectedSeed = preferences.mode == AppearanceThemeMode.custom
        ? preferences.customSeed
        : preferences.preset.seed;

    _syncEditingColor(preferences.customSeed);

    return SettingsStack(
      children: [
        SettingsGroup(
          title: 'Interface',
          children: [
            SettingsRow(
              icon: AppIcons.moon,
              title: 'Tema',
              subtitle: 'Escuro',
              trailing: AppBadge(
                label: preferences.mode == AppearanceThemeMode.custom
                    ? 'Custom'
                    : preferences.preset.label,
                variant: AppBadgeVariant.accent,
              ),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Cores',
          trailing: SettingsValueText(
            colorToHex(selectedSeed),
            monospace: true,
          ),
          children: [
            _PresetGrid(
              preferences: preferences,
              enabled: !asyncPreferences.isLoading,
              onSelected: (preset) =>
                  unawaited(controller.selectPreset(preset.id)),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Personalizado',
          children: [
            _CustomColorEditor(
              color: _editingColor ?? preferences.customSeed,
              enabled: !asyncPreferences.isLoading,
              errorText: _hexError,
              hexController: _hexController,
              onColorChanged: (color) {
                setState(() {
                  _editingColor = color;
                  _hexError = null;
                  _hexController.text = colorToHex(color);
                });
                unawaited(controller.setCustomSeed(color));
              },
              onHexChanged: (value) {
                final color = parseHexColor(value);
                if (color == null) {
                  setState(() => _hexError = 'Use #RRGGBB.');
                  return;
                }
                setState(() {
                  _editingColor = color;
                  _hexError = null;
                });
                unawaited(controller.setCustomSeed(color));
              },
            ),
          ],
        ),
        const SettingsNotice(
          message:
              'A cor fica salva neste desktop e é aplicada instantaneamente no app.',
          icon: AppIcons.palette,
        ),
      ],
    );
  }

  void _syncEditingColor(Color customSeed) {
    final current = _editingColor;
    if (current != null && current.toARGB32() == customSeed.toARGB32()) return;
    _editingColor = customSeed;
    final nextHex = colorToHex(customSeed);
    if (_hexController.text != nextHex) _hexController.text = nextHex;
  }
}

class _PresetGrid extends StatelessWidget {
  const _PresetGrid({
    required this.preferences,
    required this.enabled,
    required this.onSelected,
  });

  final AppearanceThemePreferences preferences;
  final bool enabled;
  final ValueChanged<AppThemePreset> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.appColors;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final preset in appThemePresets)
            _PresetSwatch(
              preset: preset,
              selected:
                  preferences.mode == AppearanceThemeMode.preset &&
                  preferences.presetId == preset.id,
              enabled: enabled,
              borderColor: palette.borderSubtle,
              onTap: () => onSelected(preset),
            ),
        ],
      ),
    );
  }
}

class _PresetSwatch extends StatefulWidget {
  const _PresetSwatch({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.borderColor,
    required this.onTap,
  });

  final AppThemePreset preset;
  final bool selected;
  final bool enabled;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  State<_PresetSwatch> createState() => _PresetSwatchState();
}

class _PresetSwatchState extends State<_PresetSwatch> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.preset.palette;
    final selected = widget.selected;
    final outline = selected ? colors.accent : widget.borderColor;
    return Tooltip(
      message: widget.preset.label,
      child: MouseRegion(
        cursor: widget.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.accent, colors.surface3, colors.surface1],
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: outline,
                width: selected ? 3 : (_hovered ? 2 : 1),
              ),
            ),
            child: selected
                ? Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      width: 18,
                      height: 18,
                      margin: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.onAccent, width: 1),
                      ),
                      child: AppIcon(
                        AppIcons.check,
                        size: 12,
                        color: colors.onAccent,
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _CustomColorEditor extends StatelessWidget {
  const _CustomColorEditor({
    required this.color,
    required this.enabled,
    required this.errorText,
    required this.hexController,
    required this.onColorChanged,
    required this.onHexChanged,
  });

  final Color color;
  final bool enabled;
  final String? errorText;
  final TextEditingController hexController;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<String> onHexChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appColors;
    final hsv = HSVColor.fromColor(color);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: palette.borderSubtle, width: 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: hexController,
                  enabled: enabled,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
                    LengthLimitingTextInputFormatter(7),
                    _UppercaseHexFormatter(),
                  ],
                  style: TextStyle(
                    fontFamily: 'Geist Mono',
                    fontSize: 12.5,
                    color: palette.textPrimary,
                    letterSpacing: 0,
                  ),
                  decoration: InputDecoration(
                    hintText: '#5865F2',
                    errorText: errorText,
                    prefixIcon: AppIcon(
                      AppIcons.channelText,
                      size: 15,
                      color: palette.textSecondary,
                    ),
                  ),
                  onChanged: onHexChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SaturationValuePicker(
            color: hsv,
            enabled: enabled,
            onChanged: (next) => onColorChanged(next.toColor()),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              AppIcon(AppIcons.palette, size: 16, color: palette.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: palette.accent,
                    inactiveTrackColor: palette.borderStrong,
                    thumbColor: palette.textPrimary,
                    overlayColor: palette.accent.withValues(alpha: 0.16),
                  ),
                  child: Slider(
                    min: 0,
                    max: 360,
                    value: hsv.hue,
                    onChanged: enabled
                        ? (value) => onColorChanged(
                            hsv.withHue(value == 360 ? 0 : value).toColor(),
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaturationValuePicker extends StatelessWidget {
  const _SaturationValuePicker({
    required this.color,
    required this.enabled,
    required this.onChanged,
  });

  final HSVColor color;
  final bool enabled;
  final ValueChanged<HSVColor> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appColors;
    return GestureDetector(
      onPanDown: enabled
          ? (details) => _pick(context, details.localPosition)
          : null,
      onPanUpdate: enabled
          ? (details) => _pick(context, details.localPosition)
          : null,
      child: CustomPaint(
        painter: _SaturationValuePainter(color.hue, palette.borderSubtle),
        child: AspectRatio(
          aspectRatio: 4.2,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final x = color.saturation * constraints.maxWidth;
              final y = (1 - color.value) * constraints.maxHeight;
              return Stack(
                children: [
                  Positioned(
                    left: (x - 8).clamp(0, constraints.maxWidth - 16),
                    top: (y - 8).clamp(0, constraints.maxHeight - 16),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x88000000),
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _pick(BuildContext context, Offset position) {
    final box = context.findRenderObject() as RenderBox;
    final width = math.max(1, box.size.width);
    final height = math.max(1, box.size.height);
    final saturation = (position.dx / width).clamp(0.0, 1.0);
    final value = (1 - position.dy / height).clamp(0.0, 1.0);
    onChanged(color.withSaturation(saturation).withValue(value));
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter(this.hue, this.borderColor);

  final double hue;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white, hueColor],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(AppRadius.md)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(AppRadius.md)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(AppRadius.md)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );
  }

  @override
  bool shouldRepaint(covariant _SaturationValuePainter oldDelegate) {
    return oldDelegate.hue != hue || oldDelegate.borderColor != borderColor;
  }
}

class _UppercaseHexFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll('#', '').toUpperCase();
    final text = raw.isEmpty ? '' : '#$raw';
    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
