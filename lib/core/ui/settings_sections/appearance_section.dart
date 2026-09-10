import 'package:flutter/material.dart';

import '../settings_section_layout.dart';
import '../ui.dart';

/// Seção Aparência do modal (UI shell): tema único (dark) — sem toggle
/// funcional (não há persistência de preferência no client).
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsStack(
      children: [
        SettingsGroup(
          title: 'Interface',
          children: [
            SettingsRow(
              icon: Icons.dark_mode_outlined,
              title: 'Tema',
              subtitle: 'Escuro',
              trailing: AppBadge(label: 'Fixo'),
            ),
          ],
        ),
      ],
    );
  }
}
