import 'package:flutter/material.dart';

/// Design tokens centralizados do 4fun_cod (macOS-like + Vercel Dark).
abstract final class AppTokens {
  // --- Superfícies Neutras (Vercel Monocromático) ---
  /// Canvas mais profundo (chat/feed e área de trabalho).
  static const Color background = Color(0xFF000000);

  /// Barra lateral extrema / rail de navegação.
  static const Color surfaceBase = Color(0xFF080808);

  /// Sidebars (Canais / DMs / Painel de membros).
  static const Color surface1 = Color(0xFF101010);

  /// Cards, Inputs, Modais e containers elevados.
  static const Color surface2 = Color(0xFF161616);

  /// Hover states, badges elevadas e popovers.
  static const Color surface3 = Color(0xFF222222);

  /// Fundo translúcido para efeito Frosted Glass / BackdropBlur (macOS).
  static const Color surfaceGlass = Color(0xCC121212); // ~80% opaco

  // --- Bordas e Divisores ---
  /// Hairline translúcida para divisórias internas sutis (rgba(255, 255, 255, 0.08)).
  static const Color borderHairline = Color(0x14FFFFFF);

  /// Borda de 1px sutil para cards e inputs inativos (rgba(255, 255, 255, 0.14)).
  static const Color borderSubtle = Color(0x24FFFFFF);

  /// Borda forte / separadores proeminentes.
  static const Color borderStrong = Color(0xFF2E2E2E);

  /// Borda de foco ativo (branco Vercel ou azul elétrico).
  static const Color borderFocus = Color(0xFFFFFFFF);

  // --- Tipografia e Contrastes ---
  /// Texto primário: branco suave Vercel (evita fadiga ocular comparado ao #FFF puro).
  static const Color textPrimary = Color(0xFFEDEDED);

  /// Texto secundário (Zinc-400).
  static const Color textSecondary = Color(0xFFA1A1AA);

  /// Texto atenuado/muted (Zinc-500) para timestamps e dicas.
  static const Color textMuted = Color(0xFF71717A);

  /// Texto inverso para botões primários brancos (preto puro).
  static const Color textInverse = Color(0xFF000000);

  // --- Acentos e Semântica ---
  /// Azul Vercel para links, seleções ativas e badges interativas.
  static const Color accentVercel = Color(0xFF0070F3);

  /// Roxo/Violeta para estados DND, tags especiais e erros (paleta sem vermelho agressivo).
  static const Color accentPurple = Color(0xFF8B5CF6);

  /// Verde para online, microfone ativo e indicadores de sucesso.
  static const Color accentGreen = Color(0xFF46A758);

  /// Âmbar para ausente / idle e alertas.
  static const Color accentAmber = Color(0xFFF5A623);

  /// Cinza para offline / desconectado.
  static const Color accentOffline = Color(0xFF52525B);

  // --- Overlays de Interação ---
  /// Overlay de hover (5% branco).
  static const Color hoverOverlay = Color(0x0DFFFFFF);

  /// Overlay de seleção / clique (10% branco).
  static const Color activeOverlay = Color(0x1AFFFFFF);

  /// Hover de linha de chat (3% branco).
  static const Color chatRowHover = Color(0x08FFFFFF);

  // --- Cores cíclicas de autores de mensagens ---
  static const List<Color> authorColors = [
    Color(0xFF0070F3), // Azul
    Color(0xFF46A758), // Verde
    Color(0xFFF5A623), // Âmbar
    Color(0xFF8B5CF6), // Roxo
  ];
}

/// Raios de curvatura padrão macOS
abstract final class AppRadius {
  /// 4px - Badges pequenas, presence dots
  static const double xs = 4.0;
  static const Radius rXs = Radius.circular(4.0);
  static const BorderRadius brXs = BorderRadius.all(rXs);

  /// 6px - Linhas de canais, inputs compactos, botões compactos
  static const double sm = 6.0;
  static const Radius rSm = Radius.circular(6.0);
  static const BorderRadius brSm = BorderRadius.all(rSm);

  /// 8px - Inputs padrão, botões padrão, cards internos
  static const double md = 8.0;
  static const Radius rMd = Radius.circular(8.0);
  static const BorderRadius brMd = BorderRadius.all(rMd);

  /// 12px - Cards principais, previews de mídia, avatares
  static const double lg = 12.0;
  static const Radius rLg = Radius.circular(12.0);
  static const BorderRadius brLg = BorderRadius.all(rLg);

  /// 14px - Diálogos, janelas de modal macOS
  static const double xl = 14.0;
  static const Radius rXl = Radius.circular(14.0);
  static const BorderRadius brXl = BorderRadius.all(rXl);

  /// 9999px - Pills, botões redondos, switches
  static const double full = 9999.0;
  static const Radius rFull = Radius.circular(9999.0);
  static const BorderRadius brFull = BorderRadius.all(rFull);
}

/// Sombras ambientes refinadas (macOS style)
abstract final class AppShadows {
  /// Sombra sutil para cards elevados e popovers
  static const List<BoxShadow> popover = [
    BoxShadow(
      color: Color(0x66000000),
      offset: Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Color(0x33000000),
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
  ];

  /// Sombra para janelas de diálogo e modais (macOS window drop shadow)
  static const List<BoxShadow> modalWindow = [
    BoxShadow(
      color: Color(0x99000000),
      offset: Offset(0, 20),
      blurRadius: 48,
      spreadRadius: -8,
    ),
    BoxShadow(
      color: Color(0x44000000),
      offset: Offset(0, 4),
      blurRadius: 16,
    ),
  ];
}
