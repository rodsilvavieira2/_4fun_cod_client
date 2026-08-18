import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/servers.dart';
import 'servers_providers.dart';

/// Coluna esquerda estilo Discord: ícones dos servidores + botão de criar.
class ServerRail extends ConsumerWidget {
  const ServerRail({super.key, this.selectedServerId});

  /// Servidor em destaque (usado no shell); nulo na home.
  final String? selectedServerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serversProvider);
    return Container(
      width: 72,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: servers.when(
        loading: () => const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (error, _) => Center(
          child: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Tentar novamente',
            onPressed: () => ref.invalidate(serversProvider),
          ),
        ),
        data: (list) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            for (final server in list) _ServerRailItem(
              server: server,
              selected: server.id == selectedServerId,
            ),
            const SizedBox(height: 8),
            Center(
              child: IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Criar servidor',
                onPressed: () => context.push('/create-server'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerRailItem extends StatelessWidget {
  const _ServerRailItem({required this.server, required this.selected});

  final Server server;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: server.name,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.go('/servers/${server.id}'),
          child: Container(
            width: 48,
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected ? colorScheme.primary : colorScheme.surface,
              borderRadius: BorderRadius.circular(selected ? 16 : 12),
            ),
            alignment: Alignment.center,
            child: server.iconUrl != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(selected ? 16 : 12),
                    child: Image.network(
                      server.iconUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _initial(server, colorScheme),
                    ),
                  )
                : _initial(server, colorScheme),
          ),
        ),
      ),
    );
  }

  Widget _initial(Server server, ColorScheme colorScheme) {
    return Text(
      server.name.isEmpty ? '?' : server.name[0].toUpperCase(),
      style: TextStyle(
        color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
