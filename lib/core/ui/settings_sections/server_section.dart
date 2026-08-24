import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/servers/servers_providers.dart';
import '../section_header.dart';

/// Seção Servidor do modal (UI shell): nome + região (mock "Brasil") +
/// botão "Copiar convite" que apenas sinaliza "em breve" (NUNCA copia
/// placeholder — risco documentado na SPEC 3).
class ServerSection extends ConsumerWidget {
  const ServerSection({super.key, this.serverId});

  final String? serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverId = this.serverId;
    if (serverId == null) {
      return const SectionHeader('SERVIDOR');
    }
    final server = ref.watch(serverDetailProvider(serverId)).valueOrNull?.server;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('SERVIDOR'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Nome',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Text(
                server?.name ?? '—',
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Região',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Text('Brasil', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            // Sem endpoint de convite nesta visão: feedback honesto, sem
            // copiar valor mock para a área de transferência.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copiar convite em breve')),
            );
          },
          icon: const Icon(Icons.link, size: 16),
          label: const Text('Copiar convite'),
        ),
      ],
    );
  }
}
