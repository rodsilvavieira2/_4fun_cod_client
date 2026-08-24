import 'package:flutter/material.dart';

/// Cabeçalho de seção caps (12/600 via `labelSmall`) — usado em listas
/// com agrupamento (canais, membros, conversas DM).
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.label, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 6),
  });

  final String label;

  /// Espaçamento ao redor (default: 16/12/16/6).
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
