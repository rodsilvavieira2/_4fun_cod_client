import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/websocket/socket_service.dart';
import '../../shared/models/servers.dart';
import '../channels/channel_list.dart';
import '../channels/channels_providers.dart';
import '../chat/chat_screen.dart';
import 'server_rail.dart';
import 'servers_providers.dart';

/// Visão principal de um servidor: rail + lista de canais + conteúdo do
/// canal selecionado (chat na Fase 3; voz chega na Fase 4).
///
/// Ao abrir, faz `server:join` no socket (e `server:leave` ao sair); ao
/// selecionar canal de TEXTO, `channel:join`/`channel:leave` — o join é
/// reemitido automaticamente pelo [SocketService] após reconexão.
class ServerShellScreen extends ConsumerStatefulWidget {
  const ServerShellScreen({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ServerShellScreen> createState() => _ServerShellScreenState();
}

class _ServerShellScreenState extends ConsumerState<ServerShellScreen> {
  String? _selectedChannelId;

  @override
  void initState() {
    super.initState();
    // Pós-frame: o socket pode ainda não ter conectado; o estado de join é
    // registrado e reemitido no 'connect'.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(socketServiceProvider).joinServer(widget.serverId);
    });
  }

  @override
  void dispose() {
    final socket = ref.read(socketServiceProvider);
    final channelId = _selectedChannelId;
    if (channelId != null) {
      socket.leaveChannel(channelId);
    }
    socket.leaveServer(widget.serverId);
    super.dispose();
  }

  void _onChannelSelected(String channelId, List<ServerChannel> channels) {
    if (_selectedChannelId == channelId) return;
    final previous = _selectedChannelId;
    final socket = ref.read(socketServiceProvider);
    if (previous != null) {
      socket.leaveChannel(previous);
    }
    setState(() => _selectedChannelId = channelId);
    final channel = channels.where((c) => c.id == channelId).firstOrNull;
    if (channel?.type == ChannelType.text) {
      socket.joinChannel(channelId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(serverDetailProvider(widget.serverId));
    final channels = ref.watch(channelsControllerProvider(widget.serverId));
    final isOwner = detail.valueOrNull?.isOwner ?? false;
    final channelList = channels.valueOrNull ?? const <ServerChannel>[];
    final selectedChannel = channelList
        .where((c) => c.id == _selectedChannelId)
        .firstOrNull;

    // Canal selecionado foi removido (owner deletou): sai do join e limpa a
    // seleção. O callback roda em pós-frame para não setState durante build.
    final removedId = _selectedChannelId;
    if (removedId != null && selectedChannel == null && channels.hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedChannelId != removedId) return;
        ref.read(socketServiceProvider).leaveChannel(removedId);
        setState(() => _selectedChannelId = null);
      });
    }

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
                    _onChannelSelected(id, channelList),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _channelContent(context, selectedChannel)),
        ],
      ),
    );
  }

  Widget _channelContent(
    BuildContext context,
    ServerChannel? selectedChannel,
  ) {
    final channel = selectedChannel;
    if (channel == null) {
      return Center(
        child: Text(
          'Selecione um canal',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    switch (channel.type) {
      case ChannelType.text:
        return ChatScreen(
          key: ValueKey(channel.id),
          serverId: widget.serverId,
          channelId: channel.id,
        );
      case ChannelType.voice:
        return Center(
          child: Text(
            'Voz chega na Fase 4',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        );
    }
  }
}
