import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/servers.dart';
import 'channels_providers.dart';
import 'create_channel_dialog.dart';

/// Lista de canais de um servidor com criação (OWNER) e exclusão com
/// confirmação (OWNER).
class ChannelList extends ConsumerWidget {
  const ChannelList({
    super.key,
    required this.serverId,
    required this.isOwner,
    this.selectedChannelId,
    this.onChannelSelected,
  });

  final String serverId;
  final bool isOwner;
  final String? selectedChannelId;
  final ValueChanged<String>? onChannelSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsControllerProvider(serverId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Canais',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              if (isOwner)
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Criar canal',
                  onPressed: () =>
                      showCreateChannelDialog(context, serverId: serverId),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: channels.when(
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
                onPressed: () =>
                    ref.invalidate(channelsControllerProvider(serverId)),
              ),
            ),
            data: (list) => list.isEmpty
                ? const Center(
                    child: Text('Nenhum canal ainda.'),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final channel = list[index];
                      return ListTile(
                        dense: true,
                        leading: Text(channel.icon),
                        title: Text('#${channel.name}'),
                        selected: channel.id == selectedChannelId,
                        onTap: () => onChannelSelected?.call(channel.id),
                        trailing: isOwner
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                tooltip: 'Excluir canal',
                                onPressed: () => _confirmDelete(
                                  context,
                                  ref,
                                  channel,
                                ),
                              )
                            : null,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ServerChannel channel,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir canal'),
        content: Text('Excluir o canal #${channel.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(channelsControllerProvider(serverId).notifier).delete(channel.id);
  }
}
