import 'package:flutter/material.dart';

/// Cores de status/presença (design system §2.4) — fora do [ColorScheme]
/// (papel semântico do produto, não role Material; mesma filosofia do Discord:
/// verde = status/toggle, nunca ação).
class AppStatusColors {
  static const online = Color(0xFF46A758);
  static const idle = Color(0xFFFFB224);
  static const dnd = Color(0xFFE5484D);
  static const offline = Color(0xFFA1A1A1);
}

/// Overlays de linha (hover/selected) — fora do ColorScheme, aplicados via
/// `MaterialStateProperty`/cores diretas (filosofia Discord).
class AppOverlayColors {
  static const hover = Color(0x4D4E5058); // rgba(78,80,88,0.3)
  static const selected = Color(0x99505258); // rgba(78,80,88,0.6)
}

/// Tema dark-only do 4fun_cod (design system Discord + Vercel dark/Geist).
///
/// NOTA: a família Geist Sans está registrada no pubspec como **'Geist'**
/// (nome interno do TTF v1.7.2 — conferido via fc-scan; "Geist Sans" é o
/// nome de marca e NÃO resolve no ThemeData, cairia no fallback silencioso).
final ThemeData theme4funCod = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  fontFamily: 'Geist',
  visualDensity: VisualDensity.standard,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF0070F3),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFF0A72EF),
    secondary: Color(0xFFA1A1A1),
    surface: Color(0xFF171717),
    surfaceContainerLowest: Color(0xFF0A0A0A), // rail / floating (mais escuro)
    surfaceContainer: Color(0xFF171717), // sidebar e chat
    surfaceContainerHighest: Color(0xFF0A0A0A), // rail de servidores (app já usa este role)
    onSurface: Color(0xFFEDEDED),
    outline: Color(0xFF292929),
    outlineVariant: Color(0xFF737373),
    error: Color(0xFFE5484D),
  ),
  textTheme: const TextTheme(
    displayMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: Color(0xFFEDEDED),
      letterSpacing: -0.5,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: Color(0xFFEDEDED),
      letterSpacing: -0.5,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: Color(0xFFEDEDED),
    ),
    titleLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Color(0xFFEDEDED),
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Color(0xFFEDEDED),
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: Color(0xFFEDEDED),
    ),
    bodyMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: Color(0xFFEDEDED),
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Color(0xFFFFFFFF),
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Color(0xFFA1A1A1),
      letterSpacing: 1.0,
    ),
    // Timestamps/metadados técnicos em Geist Mono + tabular-nums.
    bodySmall: TextStyle(
      fontFamily: 'Geist Mono',
      fontSize: 13,
      color: Color(0xFFA1A1A1),
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: const Color(0xFF0070F3),
      foregroundColor: const Color(0xFFFFFFFF),
      minimumSize: const Size(64, 38),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFF0A0A0A),
    hintStyle: const TextStyle(color: Color(0xFF737373)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: Color(0xFF292929)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: Color(0xFF292929)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: Color(0xFF0070F3), width: 1),
    ),
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF171717),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    elevation: 0,
    margin: EdgeInsets.zero,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: const Color(0xFF171717),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    elevation: 8,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: const Color(0xFF0A0A0A),
    contentTextStyle: const TextStyle(color: Color(0xFFEDEDED)),
    behavior: SnackBarBehavior.floating,
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0xFF292929),
    thickness: 1,
    space: 1,
  ),
  chipTheme: ChipThemeData(
    backgroundColor: const Color(0xFF0A0A0A),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
  ),
);
