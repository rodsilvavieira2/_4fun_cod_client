import 'package:flutter/material.dart';

import '../ui/ds_tokens.dart';

export '../ui/ds_tokens.dart';

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
final ThemeData theme4funCod = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: 'Geist',
  visualDensity: VisualDensity.standard,
  scaffoldBackgroundColor: AppTokens.background,
  canvasColor: AppTokens.background,
  colorScheme: const ColorScheme.dark(
    primary: AppTokens.textPrimary, // Botões e ações em alto contraste Vercel
    onPrimary: AppTokens.textInverse,
    primaryContainer: AppTokens.surface2,
    onPrimaryContainer: AppTokens.textPrimary,
    secondary: AppTokens.textSecondary,
    onSecondary: AppTokens.textInverse,
    surface: AppTokens.surface2,
    surfaceContainerLowest: AppTokens.surfaceBase,
    surfaceContainerLow: AppTokens.surface1,
    surfaceContainer: AppTokens.surface2,
    surfaceContainerHigh: AppTokens.surface3,
    surfaceContainerHighest: AppTokens.background,
    onSurface: AppTokens.textPrimary,
    onSurfaceVariant: AppTokens.textSecondary,
    outline: AppTokens.borderStrong,
    outlineVariant: AppTokens.borderHairline,
    error: AppTokens.accentPurple,
    onError: AppTokens.textPrimary,
  ),
  appBarTheme: const AppBarTheme(
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    backgroundColor: AppTokens.surface1,
    foregroundColor: AppTokens.textPrimary,
    surfaceTintColor: Colors.transparent,
    toolbarHeight: AppLayout.headerHeight,
    titleTextStyle: TextStyle(
      fontFamily: 'Geist',
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppTokens.textPrimary,
      letterSpacing: -0.2,
    ),
    shape: Border(
      bottom: BorderSide(color: AppTokens.borderHairline, width: 1),
    ),
  ),
  textTheme: const TextTheme(
    displayMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: AppTokens.textPrimary,
      letterSpacing: -0.6,
    ),
    headlineMedium: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: AppTokens.textPrimary,
      letterSpacing: -0.5,
    ),
    headlineSmall: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: AppTokens.textPrimary,
      letterSpacing: -0.4,
    ),
    titleLarge: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: AppTokens.textPrimary,
      letterSpacing: -0.3,
    ),
    titleMedium: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: AppTokens.textPrimary,
      letterSpacing: -0.2,
    ),
    titleSmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppTokens.textSecondary,
    ),
    bodyLarge: TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w400,
      color: AppTokens.textPrimary,
      height: 1.45,
    ),
    bodyMedium: TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w400,
      color: AppTokens.textPrimary,
      height: 1.4,
    ),
    labelLarge: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: AppTokens.textPrimary,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: AppTokens.textSecondary,
    ),
    labelSmall: TextStyle(
      fontFamily: 'Geist Mono',
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppTokens.textSecondary,
      letterSpacing: 0.8,
    ),
    bodySmall: TextStyle(
      fontFamily: 'Geist Mono',
      fontSize: 11.5,
      color: AppTokens.textMuted,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: ButtonStyle(mouseCursor: clickableMouseCursor),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppTokens.textPrimary, // Vercel Signature: White on Dark
      foregroundColor: AppTokens.textInverse, // Black text
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
      foregroundColor: AppTokens.textSecondary,
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
    fillColor: AppTokens.surface2,
    hintStyle: const TextStyle(color: AppTokens.textMuted, fontSize: 13.5),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: const BorderSide(color: AppTokens.borderStrong, width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: const BorderSide(color: AppTokens.borderStrong, width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: const BorderSide(color: AppTokens.borderFocus, width: 1.2),
    ),
  ),
  cardTheme: CardThemeData(
    color: AppTokens.surface2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: const BorderSide(color: AppTokens.borderHairline, width: 1),
    ),
    elevation: 0,
    margin: EdgeInsets.zero,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: AppTokens.surface2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      side: const BorderSide(color: AppTokens.borderSubtle, width: 1),
    ),
    elevation: 16,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: AppTokens.surface2,
    contentTextStyle: const TextStyle(
      color: AppTokens.textPrimary,
      fontSize: 13.5,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: const BorderSide(color: AppTokens.borderSubtle, width: 1),
    ),
    behavior: SnackBarBehavior.floating,
  ),
  dividerTheme: const DividerThemeData(
    color: AppTokens.borderHairline,
    thickness: 1,
    space: 1,
  ),
  scrollbarTheme: ScrollbarThemeData(
    thickness: const WidgetStatePropertyAll(8),
    radius: const Radius.circular(AppRadius.full),
    thumbVisibility: const WidgetStatePropertyAll(false),
    thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.hovered)
          ? AppTokens.surface3
          : AppTokens.surface2,
    ),
    trackColor: const WidgetStatePropertyAll(Colors.transparent),
  ),
  tooltipTheme: TooltipThemeData(
    decoration: BoxDecoration(
      color: AppTokens.textPrimary,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      boxShadow: AppShadows.popover,
    ),
    textStyle: const TextStyle(
      fontFamily: 'Geist',
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppTokens.textInverse,
    ),
    waitDuration: const Duration(milliseconds: 450),
  ),
  popupMenuTheme: PopupMenuThemeData(
    color: AppTokens.surface2,
    surfaceTintColor: Colors.transparent,
    elevation: 16,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: const BorderSide(color: AppTokens.borderSubtle),
    ),
    textStyle: const TextStyle(
      fontFamily: 'Geist',
      fontSize: 13,
      color: AppTokens.textPrimary,
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: AppTokens.surface1,
    modalBackgroundColor: AppTokens.surface1,
    surfaceTintColor: Colors.transparent,
    showDragHandle: true,
    dragHandleColor: AppTokens.borderStrong,
  ),
  chipTheme: ChipThemeData(
    backgroundColor: AppTokens.surface2,
    labelStyle: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.full),
      side: const BorderSide(color: AppTokens.borderHairline),
    ),
  ),
);
