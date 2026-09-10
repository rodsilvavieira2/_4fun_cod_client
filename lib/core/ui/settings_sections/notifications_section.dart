import 'package:flutter/material.dart';

import '../settings_section_layout.dart';

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
        SettingsStack(
          children: [
            SettingsGroup(
              title: 'Conversas',
              children: [
                SettingsRow(
                  icon: Icons.chat_bubble_outline,
                  title: 'Mensagens diretas',
                  trailing: SettingsSwitch(
                    value: _mensagens,
                    onChanged: (value) => setState(() => _mensagens = value),
                  ),
                ),
                SettingsRow(
                  icon: Icons.alternate_email,
                  title: 'Menções',
                  trailing: SettingsSwitch(
                    value: _mencoes,
                    onChanged: (value) => setState(() => _mencoes = value),
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: 'Alertas',
              children: [
                SettingsRow(
                  icon: Icons.volume_up_outlined,
                  title: 'Sons de notificação',
                  trailing: SettingsSwitch(
                    value: _sons,
                    onChanged: (value) => setState(() => _sons = value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
