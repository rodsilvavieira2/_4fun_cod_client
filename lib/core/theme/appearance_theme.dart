import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/ds_tokens.dart';

const appearanceThemeModeKey = 'appearance.colorTheme.mode';
const appearanceThemePresetIdKey = 'appearance.colorTheme.presetId';
const appearanceThemeCustomSeedArgbKey = 'appearance.colorTheme.customSeedArgb';

enum AppearanceThemeMode { preset, custom }

class AppThemePalette extends ThemeExtension<AppThemePalette> {
  const AppThemePalette({
    required this.background,
    required this.surfaceBase,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.surfaceGlass,
    required this.borderHairline,
    required this.borderSubtle,
    required this.borderStrong,
    required this.borderFocus,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textInverse,
    required this.accent,
    required this.onAccent,
    required this.hoverOverlay,
    required this.activeOverlay,
    required this.chatRowHover,
    required this.authorColors,
  });

  static const defaultPalette = AppThemePalette(
    background: AppTokens.background,
    surfaceBase: AppTokens.surfaceBase,
    surface1: AppTokens.surface1,
    surface2: AppTokens.surface2,
    surface3: AppTokens.surface3,
    surfaceGlass: AppTokens.surfaceGlass,
    borderHairline: AppTokens.borderHairline,
    borderSubtle: AppTokens.borderSubtle,
    borderStrong: AppTokens.borderStrong,
    borderFocus: AppTokens.borderFocus,
    textPrimary: AppTokens.textPrimary,
    textSecondary: AppTokens.textSecondary,
    textMuted: AppTokens.textMuted,
    textInverse: AppTokens.textInverse,
    accent: AppTokens.accentVercel,
    onAccent: Colors.white,
    hoverOverlay: AppTokens.hoverOverlay,
    activeOverlay: AppTokens.activeOverlay,
    chatRowHover: AppTokens.chatRowHover,
    authorColors: AppTokens.authorColors,
  );

  final Color background;
  final Color surfaceBase;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color surfaceGlass;
  final Color borderHairline;
  final Color borderSubtle;
  final Color borderStrong;
  final Color borderFocus;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textInverse;
  final Color accent;
  final Color onAccent;
  final Color hoverOverlay;
  final Color activeOverlay;
  final Color chatRowHover;
  final List<Color> authorColors;

  static AppThemePalette fromSeed(Color seed) {
    final accent = _vivid(seed);
    final hue = HSVColor.fromColor(accent).hue;
    final background = HSVColor.fromAHSV(1, hue, 0.50, 0.075).toColor();
    final surfaceBase = HSVColor.fromAHSV(1, hue, 0.48, 0.105).toColor();
    final surface1 = HSVColor.fromAHSV(1, hue, 0.43, 0.145).toColor();
    final surface2 = HSVColor.fromAHSV(1, hue, 0.40, 0.185).toColor();
    final surface3 = HSVColor.fromAHSV(1, hue, 0.34, 0.270).toColor();
    final borderStrong = HSVColor.fromAHSV(1, hue, 0.25, 0.360).toColor();
    final focus = HSVColor.fromColor(
      accent,
    ).withSaturation(0.74).withValue(1.0).toColor();

    return AppThemePalette(
      background: background,
      surfaceBase: surfaceBase,
      surface1: surface1,
      surface2: surface2,
      surface3: surface3,
      surfaceGlass: surface2.withValues(alpha: 0.86),
      borderHairline: Colors.white.withValues(alpha: 0.08),
      borderSubtle: Color.alphaBlend(
        accent.withValues(alpha: 0.20),
        Colors.white.withValues(alpha: 0.08),
      ),
      borderStrong: borderStrong,
      borderFocus: focus,
      textPrimary: AppTokens.textPrimary,
      textSecondary: AppTokens.textSecondary,
      textMuted: AppTokens.textMuted,
      textInverse: AppTokens.textInverse,
      accent: accent,
      onAccent: accent.computeLuminance() > 0.46 ? Colors.black : Colors.white,
      hoverOverlay: accent.withValues(alpha: 0.12),
      activeOverlay: accent.withValues(alpha: 0.20),
      chatRowHover: accent.withValues(alpha: 0.08),
      authorColors: [
        HSVColor.fromAHSV(1, hue, 0.72, 0.95).toColor(),
        HSVColor.fromAHSV(1, (hue + 92) % 360, 0.56, 0.82).toColor(),
        HSVColor.fromAHSV(1, (hue + 42) % 360, 0.70, 0.93).toColor(),
        HSVColor.fromAHSV(1, (hue + 285) % 360, 0.52, 0.92).toColor(),
      ],
    );
  }

  static Color _vivid(Color seed) {
    final hsv = HSVColor.fromColor(seed);
    return HSVColor.fromAHSV(
      1,
      hsv.hue,
      math.max(0.58, hsv.saturation),
      math.max(0.68, hsv.value),
    ).toColor();
  }

  @override
  AppThemePalette copyWith({
    Color? background,
    Color? surfaceBase,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? surfaceGlass,
    Color? borderHairline,
    Color? borderSubtle,
    Color? borderStrong,
    Color? borderFocus,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textInverse,
    Color? accent,
    Color? onAccent,
    Color? hoverOverlay,
    Color? activeOverlay,
    Color? chatRowHover,
    List<Color>? authorColors,
  }) {
    return AppThemePalette(
      background: background ?? this.background,
      surfaceBase: surfaceBase ?? this.surfaceBase,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      surfaceGlass: surfaceGlass ?? this.surfaceGlass,
      borderHairline: borderHairline ?? this.borderHairline,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      borderFocus: borderFocus ?? this.borderFocus,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textInverse: textInverse ?? this.textInverse,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      hoverOverlay: hoverOverlay ?? this.hoverOverlay,
      activeOverlay: activeOverlay ?? this.activeOverlay,
      chatRowHover: chatRowHover ?? this.chatRowHover,
      authorColors: authorColors ?? this.authorColors,
    );
  }

  @override
  AppThemePalette lerp(ThemeExtension<AppThemePalette>? other, double t) {
    if (other is! AppThemePalette) return this;
    return AppThemePalette(
      background: Color.lerp(background, other.background, t)!,
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      surfaceGlass: Color.lerp(surfaceGlass, other.surfaceGlass, t)!,
      borderHairline: Color.lerp(borderHairline, other.borderHairline, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      hoverOverlay: Color.lerp(hoverOverlay, other.hoverOverlay, t)!,
      activeOverlay: Color.lerp(activeOverlay, other.activeOverlay, t)!,
      chatRowHover: Color.lerp(chatRowHover, other.chatRowHover, t)!,
      authorColors: [
        for (var i = 0; i < authorColors.length; i++)
          Color.lerp(
            authorColors[i],
            other.authorColors[i % other.authorColors.length],
            t,
          )!,
      ],
    );
  }
}

extension AppThemeContext on BuildContext {
  AppThemePalette get appColors =>
      Theme.of(this).extension<AppThemePalette>() ??
      AppThemePalette.defaultPalette;
}

class AppThemePreset {
  const AppThemePreset({
    required this.id,
    required this.label,
    required this.seed,
  });

  final String id;
  final String label;
  final Color seed;

  AppThemePalette get palette => id == 'default'
      ? AppThemePalette.defaultPalette
      : AppThemePalette.fromSeed(seed);
}

const appThemePresets = [
  AppThemePreset(id: 'default', label: 'Padrão', seed: AppTokens.accentVercel),
  AppThemePreset(id: 'blurple', label: 'Blurple', seed: Color(0xFF5865F2)),
  AppThemePreset(id: 'orange', label: 'Laranja', seed: Color(0xFFFF7100)),
  AppThemePreset(id: 'mint', label: 'Menta', seed: Color(0xFF9FE7C2)),
  AppThemePreset(id: 'peach', label: 'Pêssego', seed: Color(0xFFFFB284)),
  AppThemePreset(id: 'sky', label: 'Céu', seed: Color(0xFF85C7FF)),
  AppThemePreset(id: 'lavender', label: 'Lavanda', seed: Color(0xFFA78BFA)),
  AppThemePreset(id: 'rose', label: 'Rosa', seed: Color(0xFFFF5EA8)),
  AppThemePreset(id: 'crimson', label: 'Crimson', seed: Color(0xFFDA2F45)),
  AppThemePreset(id: 'gold', label: 'Dourado', seed: Color(0xFFE0A11B)),
  AppThemePreset(id: 'teal', label: 'Teal', seed: Color(0xFF00B8A9)),
  AppThemePreset(id: 'forest', label: 'Forest', seed: Color(0xFF3A8F5D)),
  AppThemePreset(id: 'slate', label: 'Slate', seed: Color(0xFF708090)),
  AppThemePreset(id: 'indigo', label: 'Indigo', seed: Color(0xFF3844C7)),
];

AppThemePreset appThemePresetById(String? id) {
  return appThemePresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => appThemePresets.first,
  );
}

class AppearanceThemePreferences {
  const AppearanceThemePreferences({
    required this.mode,
    required this.presetId,
    required this.customSeedArgb,
  });

  static const defaults = AppearanceThemePreferences(
    mode: AppearanceThemeMode.preset,
    presetId: 'default',
    customSeedArgb: 0xFF5865F2,
  );

  final AppearanceThemeMode mode;
  final String presetId;
  final int customSeedArgb;

  Color get customSeed => Color(customSeedArgb);

  AppThemePreset get preset => appThemePresetById(presetId);

  AppThemePalette get palette => switch (mode) {
    AppearanceThemeMode.preset => preset.palette,
    AppearanceThemeMode.custom => AppThemePalette.fromSeed(customSeed),
  };

  AppearanceThemePreferences copyWith({
    AppearanceThemeMode? mode,
    String? presetId,
    int? customSeedArgb,
  }) {
    return AppearanceThemePreferences(
      mode: mode ?? this.mode,
      presetId: presetId ?? this.presetId,
      customSeedArgb: customSeedArgb ?? this.customSeedArgb,
    );
  }
}

class AppearanceThemeController
    extends AsyncNotifier<AppearanceThemePreferences> {
  SharedPreferences? _preferences;

  @override
  Future<AppearanceThemePreferences> build() async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    final storedMode = preferences.getString(appearanceThemeModeKey);
    final mode = AppearanceThemeMode.values.firstWhere(
      (value) => value.name == storedMode,
      orElse: () => AppearanceThemePreferences.defaults.mode,
    );
    final presetId =
        preferences.getString(appearanceThemePresetIdKey) ??
        AppearanceThemePreferences.defaults.presetId;
    final customSeedArgb =
        preferences.getInt(appearanceThemeCustomSeedArgbKey) ??
        AppearanceThemePreferences.defaults.customSeedArgb;

    return AppearanceThemePreferences(
      mode: mode,
      presetId: appThemePresetById(presetId).id,
      customSeedArgb: _normalizeArgb(customSeedArgb),
    );
  }

  Future<void> selectPreset(String presetId) {
    final preset = appThemePresetById(presetId);
    return _save(
      (current) => current.copyWith(
        mode: AppearanceThemeMode.preset,
        presetId: preset.id,
      ),
    );
  }

  Future<void> setCustomSeed(Color color) {
    return _save(
      (current) => current.copyWith(
        mode: AppearanceThemeMode.custom,
        customSeedArgb: color.toARGB32(),
      ),
    );
  }

  Future<void> _save(
    AppearanceThemePreferences Function(AppearanceThemePreferences current)
    update,
  ) async {
    final current = state.valueOrNull ?? await future;
    final next = update(current);
    state = AsyncData(next);
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(appearanceThemeModeKey, next.mode.name),
      preferences.setString(appearanceThemePresetIdKey, next.presetId),
      preferences.setInt(
        appearanceThemeCustomSeedArgbKey,
        next.customSeed.toARGB32(),
      ),
    ]);
  }

  static int _normalizeArgb(int value) {
    if (value < 0 || value > 0xFFFFFFFF) {
      return AppearanceThemePreferences.defaults.customSeedArgb;
    }
    return value | 0xFF000000;
  }
}

final appearanceThemeProvider =
    AsyncNotifierProvider<
      AppearanceThemeController,
      AppearanceThemePreferences
    >(AppearanceThemeController.new);

String colorToHex(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color? parseHexColor(String value) {
  final normalized = value.trim().replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return null;
  return Color(0xFF000000 | int.parse(normalized, radix: 16));
}
