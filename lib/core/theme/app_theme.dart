import 'package:flutter/material.dart';

/// Cores de status/presença (wireframe v3 §3) — fora do [ColorScheme]
/// (papel semântico do produto, não role Material; mesma filosofia do
/// Discord: verde = status/toggle, nunca ação).
///
/// REGRA v3: a paleta NÃO tem vermelho — dnd e error compartilham o roxo
/// [#AppStatusColors.dnd] (error só aparece em validação de formulário,
/// nunca ao lado de presence dot).
class AppStatusColors {
  static const online = Color(0xFF46A758);
  static const idle = Color(0xFFF5A623);
  static const dnd = Color(0xFF8B5CF6);
  static const offline = Color(0xFF4B5563);
}

/// Overlays de linha (hover/selected) — fora do ColorScheme, aplicados via
/// `MaterialStateProperty`/cores diretas. v3: alphas BRANCOS translúcidos
/// (substituem os alphas rosados do v1).
class AppOverlayColors {
  static const hover = Color(0x0DFFFFFF); // rgba(255,255,255,0.05)
  static const selected = Color(0x17FFFFFF); // rgba(255,255,255,0.09)
}

/// Tokens de superfície do wireframe v3 (dark minimalista dev-tool) —
/// hierarquia por coluna: rail < card < canvas.
///
/// Exportado para as SPECs seguintes (chat/rail/modal usam direto, sem
/// reescrever o ColorScheme por coluna).
class AppThemeColors {
  AppThemeColors._();

  /// Fundo do chat / canvas principal (mais escuro da hierarquia).
  static const canvas = Color(0xFF000000);

  /// Cards/sidebar (superfícies elevadas sobre o canvas).
  static const card = Color(0xFF121212);

  /// Card alternativo / dialogs sobre o card (mais alto).
  static const cardRaised = Color(0xFF0A0A0A);

  /// Rail de navegação (mais escuro que card — fundo "atrás" de tudo).
  static const rail = Color(0xFF050505);

  /// Borda fina translúcida (hairline do wireframe: rgba(255,255,255,.08)).
  static const hairline = Color(0x14FFFFFF);

  /// Borda estrutural opaca (separadores fortes, outlines de input).
  static const border = Color(0xFF262626);

  /// Hover de linha de mensagem (rgba(255,255,255,.03)) — usado no chat.
  static const messageHover = Color(0x08FFFFFF);

  /// 4 tons de autor (mensagens) — índice por hash do `author.id` % 4.
  static const List<Color> authorColors = [
    Color(0xFF0070F3),
    Color(0xFF46A758),
    Color(0xFFF5A623),
    Color(0xFF8B5CF6),
  ];
}

/// Tema dark-only do 4fun_cod (wireframe v3 — dark minimalista dev-tool).
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
    // Mantido: usado em voice_screen (volume ring do participante).
    primaryContainer: Color(0xFF0A72EF),
    secondary: Color(0xFFA1A1AA),
    surface: Color(0xFF0A0A0A), // base/dialog/card alt (cardRaised)
    surfaceContainerLowest: Color(0xFF050505), // rail
    surfaceContainer: Color(0xFF121212), // cards/sidebar
    surfaceContainerHighest: Color(0xFF000000), // chat canvas
    onSurface: Color(0xFFFFFFFF),
    outline: Color(0xFF262626),
    outlineVariant: Color(0x14FFFFFF), // hairline
    error: Color(0xFF8B5CF6), // v3: error = roxo (paleta sem vermelho)
    onError: Color(0xFFFFFFFF),
  ),
  textTheme: const TextTheme(
    displayMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: Color(0xFFFFFFFF),
      letterSpacing: -0.5,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: Color(0xFFFFFFFF),
      letterSpacing: -0.5,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: Color(0xFFFFFFFF),
    ),
    titleLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Color(0xFFFFFFFF),
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: Color(0xFFFFFFFF),
    ),
    bodyLarge: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: Color(0xFFFFFFFF),
    ),
    bodyMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: Color(0xFFFFFFFF),
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Color(0xFFFFFFFF),
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Color(0xFFA1A1AA),
      letterSpacing: 1.0,
    ),
    // Timestamps/metadados técnicos em Geist Mono + tabular-nums.
    bodySmall: TextStyle(
      fontFamily: 'Geist Mono',
      fontSize: 13,
      color: Color(0xFFA1A1AA),
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
    fillColor: const Color(0xFF121212),
    hintStyle: const TextStyle(color: Color(0xFF6E7681)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFF262626)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFF262626)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Color(0xFF0070F3), width: 1),
    ),
  ),
  cardTheme: CardThemeData(
    color: const Color(0xFF121212),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    elevation: 0,
    margin: EdgeInsets.zero,
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: const Color(0xFF121212),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    elevation: 8,
  ),
  snackBarTheme: SnackBarThemeData(
    backgroundColor: const Color(0xFF0A0A0A),
    contentTextStyle: const TextStyle(color: Color(0xFFEDEDED)),
    behavior: SnackBarBehavior.floating,
  ),
  dividerTheme: const DividerThemeData(
    color: Color(0x14FFFFFF),
    thickness: 1,
    space: 1,
  ),
  chipTheme: ChipThemeData(
    backgroundColor: const Color(0xFF0A0A0A),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9999)),
  ),
);
