import 'package:flutter/material.dart';

import '../section_header.dart';

/// Seção Notificações do modal (UI shell): switches VISUAIS com estado
/// local (StatefulBuilder) — nada persiste; resetam ao reabrir o modal.
class NotificationsSection extends StatefulWidget {
  const NotificationsSection({super.key});

  @override
  State<NotificationsSection> createState() => _NotificationsSectionState();
}

class _NotificationsSectionState extends State<NotificationsSection> {
  bool _mensagens = true;
  bool _mencoes = true;
  bool _sons = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('NOTIFICAÇÕES'),
        _SwitchRow(
          label: 'Mensagens diretas',
          value: _mensagens,
          onChanged: (value) => setState(() => _mensagens = value),
        ),
        _SwitchRow(
          label: 'Menções',
          value: _mencoes,
          onChanged: (value) => setState(() => _mencoes = value),
        ),
        _SwitchRow(
          label: 'Sons de notificação',
          value: _sons,
          onChanged: (value) => setState(() => _sons = value),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
