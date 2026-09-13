import 'package:flutter/material.dart';

import 'appearance_theme.dart';
import '../ui/ds_tokens.dart';

export '../ui/ds_tokens.dart';
export 'appearance_theme.dart';

/// Cores de status/presença (compatibilidade v3/v4).
class AppStatusColors {
  static const online = AppTokens.accentGreen;
  static const idle = AppTokens.accentAmber;
  static const dnd = AppTokens.accentPurple;
  static const offline = AppTokens.accentOffline;
}

/// Overlays de linha e interação.
class AppOverlayColors {
  static const hover = AppTokens.hoverOverlay;
  static const selected = AppTokens.activeOverlay;
}

/// Tokens de superfície e bordas (compatibilidade v3/v4).
class AppThemeColors {
  AppThemeColors._();

  static const canvas = AppTokens.background;
  static const card = AppTokens.surface1;
  static const cardRaised = AppTokens.surface2;
  static const rail = AppTokens.surfaceBase;
  static const hairline = AppTokens.borderHairline;
  static const border = AppTokens.borderStrong;
  static const messageHover = AppTokens.chatRowHover;
  static const List<Color> authorColors = AppTokens.authorColors;
}

/// Cursor "mãozinha" em todo botão clicável no desktop: o padrão do Flutter
/// ([WidgetStateMouseCursor.adaptiveClickable]) mostra seta fora do web,
/// então o tema força [SystemMouseCursors.click] (seta só em desabilitado).
final WidgetStateProperty<MouseCursor?> clickableMouseCursor =
    WidgetStateProperty.resolveWith(
      (Set<WidgetState> states) => states.contains(WidgetState.disabled)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
    );

/// Tema dark macOS-like + Vercel Dark do 4fun_cod.
ThemeData build4funTheme([
  AppThemePalette palette = AppThemePalette.defaultPalette,
]) {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Geist',
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    extensions: [palette],
    colorScheme: ColorScheme.dark(
      primary: palette.accent,
      onPrimary: palette.onAccent,
      primaryContainer: palette.surface2,
      onPrimaryContainer: palette.textPrimary,
      secondary: palette.textSecondary,
      onSecondary: palette.textInverse,
      surface: palette.surface2,
      surfaceContainerLowest: palette.surfaceBase,
      surfaceContainerLow: palette.surface1,
      surfaceContainer: palette.surface2,
      surfaceContainerHigh: palette.surface3,
      surfaceContainerHighest: palette.background,
      onSurface: palette.textPrimary,
      onSurfaceVariant: palette.textSecondary,
      outline: palette.borderStrong,
      outlineVariant: palette.borderHairline,
      error: AppTokens.accentPurple,
      onError: palette.textPrimary,
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: palette.surface1,
      foregroundColor: palette.textPrimary,
      surfaceTintColor: Colors.transparent,
      toolbarHeight: AppLayout.headerHeight,
      titleTextStyle: TextStyle(
        fontFamily: 'Geist',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
        letterSpacing: 0,
      ),
      shape: Border(
        bottom: BorderSide(color: palette.borderHairline, width: 1),
      ),
    ),
    textTheme: TextTheme(
      displayMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
        letterSpacing: 0,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
        letterSpacing: 0,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
        letterSpacing: 0,
      ),
      titleLarge: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
        letterSpacing: 0,
      ),
      titleMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
        letterSpacing: 0,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: palette.textSecondary,
      ),
      bodyLarge: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w400,
        color: palette.textPrimary,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        color: palette.textPrimary,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: palette.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: palette.textSecondary,
      ),
      labelSmall: TextStyle(
        fontFamily: 'Geist Mono',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: palette.textSecondary,
        letterSpacing: 0,
      ),
      bodySmall: TextStyle(
        fontFamily: 'Geist Mono',
        fontSize: 11.5,
        color: palette.textMuted,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(mouseCursor: clickableMouseCursor),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        minimumSize: const Size(64, 34),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        textStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        elevation: 0,
      ).copyWith(mouseCursor: clickableMouseCursor),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.textSecondary,
        textStyle: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ).copyWith(mouseCursor: clickableMouseCursor),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surface2,
      hintStyle: TextStyle(color: palette.textMuted, fontSize: 13.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: palette.borderStrong, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: palette.borderStrong, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: palette.borderFocus, width: 1.2),
      ),
    ),
    cardTheme: CardThemeData(
      color: palette.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: palette.borderHairline, width: 1),
      ),
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: palette.borderSubtle, width: 1),
      ),
      elevation: 16,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surface2,
      contentTextStyle: TextStyle(color: palette.textPrimary, fontSize: 13.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: palette.borderSubtle, width: 1),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: DividerThemeData(
      color: palette.borderHairline,
      thickness: 1,
      space: 1,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(AppRadius.full),
      thumbVisibility: const WidgetStatePropertyAll(false),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? palette.surface3
            : palette.surface2,
      ),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppTokens.textPrimary,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.popover,
      ),
      textStyle: TextStyle(
        fontFamily: 'Geist',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: palette.textInverse,
      ),
      waitDuration: const Duration(milliseconds: 450),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: palette.borderSubtle),
      ),
      textStyle: TextStyle(
        fontFamily: 'Geist',
        fontSize: 13,
        color: palette.textPrimary,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface1,
      modalBackgroundColor: palette.surface1,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: palette.borderStrong,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.surface2,
      labelStyle: TextStyle(fontSize: 12, color: palette.textSecondary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.full),
        side: BorderSide(color: palette.borderHairline),
      ),
    ),
  );
}

final ThemeData theme4funCod = build4funTheme();
