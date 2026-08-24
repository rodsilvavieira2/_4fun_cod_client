import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui/section_header.dart';
import '../../shared/models/servers.dart';
import '../servers/servers_providers.dart';
import 'channels_providers.dart';
import 'create_channel_dialog.dart';

/// Lista de canais de um servidor (wireframe v3 §4.2): header com o NOME do
/// servidor, seções caps CANAIS DE TEXTO/CANAIS DE VOZ agrupadas por
/// `channel.type`, rows custom ~32px com ícone derivado do type, criação
/// (OWNER) e exclusão com confirmação (OWNER, visível só no hover).
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
    final serverName =
        ref.watch(serverDetailProvider(serverId)).valueOrNull?.server.name;
    final textChannels = <ServerChannel>[];
    final voiceChannels = <ServerChannel>[];
    for (final channel in channels.valueOrNull ?? const <ServerChannel>[]) {
      (channel.type == ChannelType.text ? textChannels : voiceChannels)
          .add(channel);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  serverName ?? 'Servidor',
                  overflow: TextOverflow.ellipsis,
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
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Divider(height: 1),
        ),
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
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (textChannels.isNotEmpty) ...[
                        const SectionHeader('CANAIS DE TEXTO'),
                        for (final channel in textChannels)
                          _ChannelRow(
                            channel: channel,
                            selected: channel.id == selectedChannelId,
                            isOwner: isOwner,
                            onTap: () =>
                                onChannelSelected?.call(channel.id),
                            onDelete: () => _confirmDelete(
                              context,
                              ref,
                              channel,
                            ),
                          ),
                      ],
                      if (voiceChannels.isNotEmpty) ...[
                        const SectionHeader('CANAIS DE VOZ'),
                        for (final channel in voiceChannels)
                          _ChannelRow(
                            channel: channel,
                            selected: channel.id == selectedChannelId,
                            isOwner: isOwner,
                            onTap: () =>
                                onChannelSelected?.call(channel.id),
                            onDelete: () => _confirmDelete(
                              context,
                              ref,
                              channel,
                            ),
                          ),
                      ],
                    ],
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

/// Row de canal custom (~32px): ícone por type + nome, hover branco 5%,
/// ativo 9% + texto branco + pill 2px azul à esquerda; delete só no hover
/// (OWNER). Ícone Material derivado de `channel.type` (contrato do model
/// `ServerChannel.icon` intocado).
class _ChannelRow extends StatefulWidget {
  const _ChannelRow({
    required this.channel,
    required this.selected,
    required this.isOwner,
    required this.onTap,
    required this.onDelete,
  });

  final ServerChannel channel;
  final bool selected;
  final bool isOwner;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_ChannelRow> createState() => _ChannelRowState();
}

class _ChannelRowState extends State<_ChannelRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = widget.selected;
    final icon = widget.channel.type == ChannelType.text
        ? Icons.tag
        : Icons.volume_up_outlined;
    final baseColor = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.secondary;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppOverlayColors.selected
                : (_hovered ? AppOverlayColors.hover : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              // Pill azul 2px do canal ativo.
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 2,
                height: 20,
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Icon(icon, size: 16, color: baseColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.channel.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: baseColor,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              // Delete visível só no hover (OWNER).
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: widget.isOwner && _hovered ? 1 : 0,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  tooltip: 'Excluir canal',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: widget.onDelete,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
