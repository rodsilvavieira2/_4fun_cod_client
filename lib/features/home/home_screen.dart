import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/servers.dart';
import '../../core/ui/settings_modal.dart';
import '../servers/server_rail.dart';
import '../servers/servers_providers.dart';

/// Home (Fase 2): rail de servidores à esquerda; sem servidores, mostra o
/// empty state com criação.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('4fun Cod'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            tooltip: 'Perfil',
            onPressed: () => showSettingsModal(context),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ServerRail(),
          const VerticalDivider(width: 1),
          Expanded(child: _homeContent(context, ref, servers)),
        ],
      ),
    );
  }

  Widget _homeContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Server>> servers,
  ) {
    return servers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Não foi possível carregar seus servidores.'),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => ref.invalidate(serversProvider),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
      data: (list) => list.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.dns_outlined, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'Crie seu primeiro servidor',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => context.push('/create-server'),
                    icon: const Icon(Icons.add),
                    label: const Text('Criar servidor'),
                  ),
                ],
              ),
            )
          : Center(
              child: Text(
                'Selecione um servidor',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
    );
  }
}
