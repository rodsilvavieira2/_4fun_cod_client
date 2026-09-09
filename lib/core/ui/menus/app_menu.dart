import 'package:flutter/material.dart';

import '../ds_tokens.dart';

/// Padrão compacto de menus popup do app (Discord-like, dark-only).
///
/// Todo menu (`channel_list`, `user_panel`, `voice_screen`, `members_screen`)
/// usa [AppMenuButton] + itens [AppMenuItem]/[AppMenuCheckedItem] com estas
/// medidas, em vez dos defaults espaçosos do Material (item 48px).
abstract final class AppMenu {
  /// Largura mínima do popup.
  static const double minWidth = 200;

  /// Largura máxima do popup (corta crescimento com labels longos).
  static const double maxWidth = 232;

  /// Altura de cada item (vs 48px do Material).
  static const double itemHeight = 32;

  /// Altura do cabeçalho de seção ([AppMenuHeader]).
  static const double headerHeight = 26;

  /// Altura do divisor ([AppMenuDivider] usa este default).
  static const double dividerHeight = 8;

  /// Respiro vertical do popup.
  static const EdgeInsets menuPadding = EdgeInsets.symmetric(vertical: 4);

  /// Padding horizontal dos itens (vs 16px do Material).
  static const EdgeInsets itemPadding = EdgeInsets.symmetric(horizontal: 12);

  /// Texto padrão dos itens.
  static const TextStyle itemTextStyle = TextStyle(
    fontFamily: 'Geist',
    fontSize: 13,
    color: AppTokens.textPrimary,
  );

  /// Título do cabeçalho de seção.
  static const TextStyle headerTextStyle = TextStyle(
    fontFamily: 'Geist',
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppTokens.textMuted,
  );
}

/// Botão de menu popup no padrão compacto do app.
///
/// Aplica superfície, borda, largura e respiro do [AppMenu]; os itens devem
/// ser [AppMenuItem]/[AppMenuCheckedItem]/[AppMenuHeader]/[AppMenuDivider]
/// para manter a altura compacta (o [PopupMenuButton] não propaga altura).
class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    this.tooltip,
    this.icon,
    this.child,
    this.initialValue,
    this.enabled = true,
    this.padding = const EdgeInsets.all(8),
    this.offset = Offset.zero,
    this.onOpened,
    this.onCanceled,
    this.minWidth = AppMenu.minWidth,
    this.maxWidth = AppMenu.maxWidth,
    this.color = AppTokens.surface2,
    this.elevation = 12,
  }) : assert(
         icon != null || child != null,
         'AppMenuButton exige icon ou child como âncora.',
       );

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T>? onSelected;
  final String? tooltip;
  final Widget? icon;
  final Widget? child;
  final T? initialValue;
  final bool enabled;
  final EdgeInsetsGeometry padding;
  final Offset offset;
  final VoidCallback? onOpened;
  final VoidCallback? onCanceled;
  final double minWidth;
  final double maxWidth;
  final Color color;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      padding: padding,
      icon: icon,
      initialValue: initialValue,
      enabled: enabled,
      offset: offset,
      onSelected: onSelected,
      onOpened: onOpened,
      onCanceled: onCanceled,
      menuPadding: AppMenu.menuPadding,
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
      color: color,
      elevation: elevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppTokens.borderSubtle, width: 1),
      ),
      itemBuilder: itemBuilder,
      child: child,
    );
  }
}

/// Item de menu compacto (32px) com filho arbitrário.
class AppMenuItem<T> extends PopupMenuItem<T> {
  const AppMenuItem({
    super.key,
    super.value,
    super.enabled = true,
    super.onTap,
    required super.child,
  }) : super(height: AppMenu.itemHeight, padding: AppMenu.itemPadding);

  /// Item com ícone + label no padrão do app.
  AppMenuItem.labeled({
    super.key,
    required T value,
    required String label,
    IconData? icon,
    super.enabled = true,
    super.onTap,
  }) : super(
         value: value,
         height: AppMenu.itemHeight,
         padding: AppMenu.itemPadding,
         child: _LabeledMenuChild(icon: icon, label: label),
       );
}

/// Item de menu compacto (32px) com seleção manual.
///
/// Estende [PopupMenuItem] puro (e NÃO [CheckedPopupMenuItem]): o checável
/// do Material embrulha o filho num [ListTile] interno de ~56px, ignorando
/// na prática qualquer [height] compacto. A seleção aparece no slot do
/// ícone, alinhada aos demais menus do app.
class AppMenuCheckedItem<T> extends PopupMenuItem<T> {
  const AppMenuCheckedItem({
    super.key,
    super.value,
    super.enabled = true,
    super.onTap,
    required super.child,
  }) : super(height: AppMenu.itemHeight, padding: AppMenu.itemPadding);

  /// Item checável a partir de um label de texto, com ícone opcional
  /// no mesmo padrão de [AppMenuItem.labeled].
  ///
  /// A seleção aparece **no slot do ícone** (check no lugar do ícone),
  /// sem a coluna extra de check do Material — assim os ícones ficam
  /// alinhados à esquerda como nos demais menus do app.
  AppMenuCheckedItem.labeled({
    super.key,
    required T value,
    bool checked = false,
    super.enabled = true,
    required String label,
    IconData? icon,
    IconData selectedIcon = Icons.check,
  }) : super(
         value: value,
         height: AppMenu.itemHeight,
         padding: AppMenu.itemPadding,
         child: _LabeledMenuChild(
           icon: checked ? selectedIcon : icon,
           label: label,
           selected: checked,
         ),
       );
}

/// Cabeçalho de seção desabilitado dentro do menu (ex: "Dispositivo de saída").
class AppMenuHeader<T> extends PopupMenuItem<T> {
  AppMenuHeader({super.key, required String title})
    : super(
        enabled: false,
        height: AppMenu.headerHeight,
        padding: AppMenu.itemPadding,
        child: Text(title, style: AppMenu.headerTextStyle),
      );
}

/// Divisor compacto entre grupos de itens.
class AppMenuDivider extends PopupMenuDivider {
  const AppMenuDivider({super.key}) : super(height: AppMenu.dividerHeight);
}

class _LabeledMenuChild extends StatelessWidget {
  const _LabeledMenuChild({
    required this.label,
    this.icon,
    this.selected = false,
  });

  final String label;
  final IconData? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    if (icon == null) {
      return Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: AppMenu.itemTextStyle,
      );
    }
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: selected ? AppTokens.textPrimary : AppTokens.textSecondary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppMenu.itemTextStyle,
          ),
        ),
      ],
    );
  }
}
