import 'package:flutter/material.dart';

import '../section_header.dart';

/// Seção Aparência do modal (UI shell): tema único (dark) — sem toggle
/// funcional (não há persistência de preferência no client).
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('APARÊNCIA'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Tema',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Text('Escuro (fixo)', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}
