import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../channels/channel_list.dart';
import '../channels/channels_providers.dart';
import 'server_rail.dart';
import 'servers_providers.dart';

/// Visão principal de um servidor: rail + lista de canais + conteúdo do
/// canal selecionado (placeholder na Fase 2).
class ServerShellScreen extends ConsumerStatefulWidget {
  const ServerShellScreen({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ServerShellScreen> createState() => _ServerShellScreenState();
}

class _ServerShellScreenState extends ConsumerState<ServerShellScreen> {
  String? _selectedChannelId;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(serverDetailProvider(widget.serverId));
    final channels = ref.watch(channelsControllerProvider(widget.serverId));
    final isOwner = detail.valueOrNull?.isOwner ?? false;
    final selectedChannel = channels.valueOrNull
        ?.where((c) => c.id == _selectedChannelId)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail.valueOrNull?.server.name ?? 'Servidor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Membros',
            onPressed: () => context.push('/servers/${widget.serverId}/members'),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Convites',
            onPressed: () => context.push('/servers/${widget.serverId}/invites'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configurações',
            onPressed: () => context.push('/servers/${widget.serverId}/settings'),
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ServerRail(selectedServerId: widget.serverId),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 240,
            child: detail.when(
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
                      ref.invalidate(serverDetailProvider(widget.serverId)),
                ),
              ),
              data: (_) => ChannelList(
                serverId: widget.serverId,
                isOwner: isOwner,
                selectedChannelId: _selectedChannelId,
                onChannelSelected: (id) =>
                    setState(() => _selectedChannelId = id),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selectedChannel == null
                ? Center(
                    child: Text(
                      'Selecione um canal',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : Center(
                    child: Text(
                      'Selecionado: ${selectedChannel.icon}${selectedChannel.name}',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
