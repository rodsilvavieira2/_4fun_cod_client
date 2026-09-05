import 'package:flutter/material.dart';

/// Design tokens centralizados do 4fun_cod (macOS-like + Vercel Dark com alto contraste).
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

  // --- Tipografia e Contrastes Calibrados (WCAG AAA/AA) ---
  /// Texto primário: branco suave Vercel (Contraste 17.8:1 em #000000).
  static const Color textPrimary = Color(0xFFEDEDED);

  /// Texto secundário (Zinc-300/400 calibrado para 9.5:1 em #101010).
  static const Color textSecondary = Color(0xFFA1A1AA);

  /// Texto atenuado/muted (Zinc-400 suave com contraste 5.8:1 para alta legibilidade).
  static const Color textMuted = Color(0xFF8E8E93);

  /// Texto inverso para botões primários brancos (preto puro).
  static const Color textInverse = Color(0xFF000000);

  // --- Acentos e Semântica ---
  /// Azul Vercel para links, seleções ativas e badges interativas.
  static const Color accentVercel = Color(0xFF0070F3);

  /// Roxo/Violeta para estados DND, tags especiais e erros.
  static const Color accentPurple = Color(0xFF9333EA);

  /// Vermelho para ações que interrompem mídia ou sinalizam estado bloqueado.
  static const Color accentDanger = Color(0xFFC62828);

  /// Verde para online, microfone ativo e indicadores de sucesso.
  static const Color accentGreen = Color(0xFF46A758);

  /// Âmbar para ausente / idle e alertas.
  static const Color accentAmber = Color(0xFFF5A623);

  /// Cinza visível para offline / desconectado.
  static const Color accentOffline = Color(0xFF71717A);

  // --- Overlays de Interação ---
  /// Overlay de hover (6% branco).
  static const Color hoverOverlay = Color(0x0FFFFFFF);

  /// Overlay de seleção / clique (12% branco).
  static const Color activeOverlay = Color(0x1FFFFFFF);

  /// Hover de linha de chat (4% branco).
  static const Color chatRowHover = Color(0x0AFFFFFF);

  // --- Cores cíclicas de autores de mensagens ---
  static const List<Color> authorColors = [
    Color(0xFF388BFD), // Azul claro acessível
    Color(0xFF46A758), // Verde
    Color(0xFFF5A623), // Âmbar
    Color(0xFFA78BFA), // Roxo suave acessível
  ];
}

/// Medidas estruturais compartilhadas pelo shell desktop/web.
///
/// A hierarquia segue o modelo de uma comunidade em tempo real: rail de
/// servidores, navegação contextual, conteúdo e painel auxiliar. Manter essas
/// medidas centralizadas evita pequenas diferenças entre servidores e DMs.
abstract final class AppLayout {
  static const double serverRailWidth = 72;
  static const double compactServerRailWidth = 56;
  static const double navigationWidth = 256;
  static const double memberPanelWidth = 240;
  static const double headerHeight = 52;
  static const double userPanelMinHeight = 56;

  /// Abaixo desta largura a navegação contextual vira uma etapa separada.
  static const double compactBreakpoint = 760;

  /// O painel auxiliar só fica fixo quando ainda sobra uma área de conteúdo
  /// confortável para chat ou vídeo.
  static const double auxiliaryPanelBreakpoint = 1180;
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
    BoxShadow(color: Color(0x33000000), offset: Offset(0, 2), blurRadius: 8),
  ];

  /// Sombra para janelas de diálogo e modais (macOS window drop shadow)
  static const List<BoxShadow> modalWindow = [
    BoxShadow(
      color: Color(0x99000000),
      offset: Offset(0, 20),
      blurRadius: 48,
      spreadRadius: -8,
    ),
    BoxShadow(color: Color(0x44000000), offset: Offset(0, 4), blurRadius: 16),
  ];
}
