# 4fun_cod Design System & Guia de Estilo
## Identidade Visual: macOS-like + Vercel Dark (Geist)

Este documento estabelece as diretrizes, tokens e padrões da biblioteca interna de componentes UI do **4fun_cod**, garantindo consistência visual em todas as telas e funcionalidades da aplicação.

---

## 1. Filosofia de Design

O Design System do 4fun_cod combina duas referências estéticas complementares:

1. **Vercel Dark Theme (Geist Design System)**:
   - **Monocromatismo de Alto Contraste**: Fundo preto profundo (`#000000`) com camadas de cinza carvão/zinco (`#080808`, `#101010`, `#161616`, `#222222`).
   - **Botões Assinatura Vercel**: Ações primárias em fundo branco suave (`#EDEDED`) com tipografia preta pura (`#000000`), garantindo clareza hierárquica.
   - **Bordas Ultrafinas (*Hairlines*)**: Divisórias de 1px com transparências sutis (`rgba(255, 255, 255, 0.08)` a `0.14`).
   - **Tipografia Técnica e Precisa**: Família Geist para texto e Geist Mono com números tabulares para métricas, contadores e timestamps.

2. **Ergonomia e Fluidez macOS**:
   - **Superfícies Translúcidas (*Frosted Glass*)**: Uso de `BackdropFilter` (blur 16–20px) em barras de ferramentas, cabeçalhos e modais.
   - **Cantos Contínuos (*Squircles*)**: Raios harmônicos de `6px`, `8px`, `12px` e `14px`.
   - **Microinterações Rápidas**: Animações de transição elásticas e compactas (100–180ms `Curves.easeOutCubic`).
   - **Controles Nativos Modernos**: Sliders segmentados (*Pills*), tooltips flutuantes e suporte a atalhos de teclado (como ESC para fechamento).

---

## 2. Tokens de Design (`AppTokens`, `AppRadius`, `AppShadows`)

Disponíveis via `import 'core/ui/ui.dart';`:

### 2.1 Cores e Superfícies (`AppTokens`)

```dart
// Superfícies
AppTokens.background      // #000000 - Canvas principal (chat, feeds)
AppTokens.surfaceBase     // #080808 - Rail lateral extremo
AppTokens.surface1        // #101010 - Sidebars (Canais, DMs, Membros)
AppTokens.surface2        // #161616 - Cards, Inputs, Diálogos
AppTokens.surface3        // #222222 - Itens elevados, badges e hover states
AppTokens.surfaceGlass    // rgba(18, 18, 18, 0.8) - Translúcido para BackdropFilter

// Bordas
AppTokens.borderHairline  // rgba(255, 255, 255, 0.08) - Separadores e divisores
AppTokens.borderSubtle    // rgba(255, 255, 255, 0.14) - Contornos inativos de cards/inputs
AppTokens.borderStrong    // #2E2E2E - Separadores proeminentes
AppTokens.borderFocus     // #FFFFFF - Anel de foco ativo

// Tipografia
AppTokens.textPrimary     // #EDEDED - Branco suave (Contraste 17.8:1)
AppTokens.textSecondary   // #A1A1AA - Zinc-400 (rótulos secundários, 9.5:1)
AppTokens.textMuted       // #8E8E93 - Zinc-400 calibrado (metadados e placeholders legíveis)
AppTokens.textInverse     // #000000 - Preto puro (para botões primários)

// Acentos e Semântica
AppTokens.accentVercel    // #0070F3 - Azul elétrico (links e destaques)
AppTokens.accentGreen     // #46A758 - Online e sucesso
AppTokens.accentAmber     // #F5A623 - Ausente (Idle) e avisos
AppTokens.accentPurple    // #9333EA - DND, erros e tags especiais
AppTokens.accentOffline   // #71717A - Offline visível em fundos escuros
```

### 2.2 Raios de Curvatura (`AppRadius`)

* `AppRadius.xs` (`4.0px`): Badges pequenas, dots de presença.
* `AppRadius.sm` (`6.0px`): Linhas de canais, botões compactos, inputs.
* `AppRadius.md` (`8.0px`): Botões padrão, cards internos, avatares de canal.
* `AppRadius.lg` (`12.0px`): Cards principais, painéis flutuantes.
* `AppRadius.xl` (`14.0px`): Janelas de diálogo e modais macOS.
* `AppRadius.full` (`9999.0px`): Botões pílula, switches e indicadores circulares.

### 2.3 Sombras Ambientes (`AppShadows`)

* `AppShadows.popover`: Sombra suave para dropdowns e menus flutuantes.
* `AppShadows.modalWindow`: Sombra profunda de elevação para modais e janelas centrais.

---

## 3. Catálogo de Componentes da Biblioteca UI (`lib/core/ui/`)

### 3.1 `AppButton`
Botão interativo com animação de escala ao clique e suporte a estados de carregamento.

```dart
// Primário Vercel (Fundo Branco, Texto Preto)
AppButton(
  label: 'Salvar alterações',
  variant: AppButtonVariant.primary,
  onPressed: () => handleSave(),
)

// Secundário (#161616 com borda)
AppButton(
  label: 'Cancelar',
  variant: AppButtonVariant.secondary,
  onPressed: () => handleCancel(),
)

// Destrutivo / Danger (Violeta)
AppButton(
  label: 'Excluir canal',
  variant: AppButtonVariant.danger,
  onPressed: () => handleDelete(),
)

// Ghost (Transparente com hover)
AppButton(
  label: 'Voltar',
  variant: AppButtonVariant.ghost,
  onPressed: () => handleBack(),
)
```

### 3.2 `AppSegmentedControl`
Controle deslizante estilo macOS com indicador animado para seleção exclusiva.

```dart
AppSegmentedControl<ChannelType>(
  selectedValue: currentType,
  onChanged: (type) => setState(() => currentType = type),
  items: const [
    SegmentItem(
      value: ChannelType.text,
      label: 'Texto',
      icon: Icons.tag,
    ),
    SegmentItem(
      value: ChannelType.voice,
      label: 'Voz & Vídeo',
      icon: Icons.volume_up_outlined,
    ),
  ],
)
```

### 3.3 `AppTextField`
Campo de formulário com rótulo integrado, contorno de 1px e borda de foco de alto contraste.

```dart
AppTextField(
  controller: nameController,
  label: 'NOME DO SERVIDOR',
  hintText: 'ex: Comunidade Dev',
  validator: (v) => v!.isEmpty ? 'Informe o nome' : null,
  onFieldSubmitted: (_) => handleSubmit(),
)
```

### 3.4 `AppCard` e `AppGlassPanel`
Containers de superfície para estruturação visual de blocos.

```dart
// Card sólido estilo Vercel
AppCard(
  padding: const EdgeInsets.all(20),
  child: Column(...),
)

// Painel Translúcido Frosted Glass (macOS)
AppGlassPanel(
  blur: 16.0,
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  child: Row(...),
)
```

### 3.5 `AppBadge`
Rótulo compacto com tipografia mono para marcações técnicas, status e permissões.

```dart
AppBadge(
  label: 'OWNER',
  variant: AppBadgeVariant.accent,
)

AppBadge(
  label: 'PRO',
  variant: AppBadgeVariant.success,
)
```

### 3.6 `PresenceDot`
Indicador de presença com anel de borda vazada no padrão macOS / Discord.

```dart
PresenceDot(
  status: PresenceStatus.online, // online, idle, dnd, offline
  size: 10,
)
```

### 3.7 `AppIconButton`
Botão de ícone compacto com feedback suave de hover e suporte a estado ativo.

```dart
AppIconButton(
  icon: Icons.settings_outlined,
  tooltip: 'Configurações',
  minSize: 28,
  onPressed: () => openSettings(),
)
```

### 3.8 `showMacModalWindow`
Exibição de diálogos estilo janela nativa do macOS com escurecimento por blur, atalho `ESC` e animação elástica de escala.

```dart
await showMacModalWindow<bool>(
  context: context,
  title: 'Criar novo canal',
  maxWidth: 420,
  child: CreateChannelForm(),
);
```

---

## 4. Hierarquia de Superfícies & Layout

Para manter a percepção de profundidade sem sombras pesadas, a aplicação segue a seguinte ordem de camadas:

```
┌──────────────────────────────────────────────────────────┐
│  5. Modais & Popovers (AppTokens.surface2 + AppShadows)  │
│  ┌────────────────────────────────────────────────────┐  │
│  │  4. Cards & Inputs (AppTokens.surface2)            │  │
│  │  ┌──────────────────────────────────────────────┐  │  │
│  │  │  3. Sidebars & Listas (AppTokens.surface1)   │  │  │
│  │  │  ┌────────────────────────────────────────┐  │  │  │
│  │  │  │  2. Rail de Navegação (surfaceBase)   │  │  │  │
│  │  │  │  ┌──────────────────────────────────┐  │  │  │  │
│  │  │  │  │  1. Canvas Principal (background)│  │  │  │  │
│  │  │  │  └──────────────────────────────────┘  │  │  │  │
│  │  │  └────────────────────────────────────────┘  │  │  │
│  │  └──────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

---

## 5. Regras e Boas Práticas do Design System

1. **Regra "Zero Red" (Sem Vermelho Agressivo)**:
   - Erros de validação e estados críticos compartilham a tonalidade violeta/roxa (`AppTokens.accentPurple`). O verde (`AppTokens.accentGreen`) é reservado exclusivamente para status e sucesso.
2. **Tipografia Tabular para Dados**:
   - Timestamps, portas, latências e dados numéricos devem sempre utilizar a fonte `Geist Mono` ou a propriedade `fontFeatures: [FontFeature.tabularFigures()]` para alinhamento uniforme.
3. **Consistência de Ações**:
   - Em diálogos modais, o botão de confirmação/ação principal sempre fica posicionado à direita e no estilo `AppButtonVariant.primary` (Branco Vercel) ou `AppButtonVariant.danger`.
4. **Imports Centralizados**:
   - Importe os componentes de UI preferencialmente através de `import 'core/ui/ui.dart';`.
