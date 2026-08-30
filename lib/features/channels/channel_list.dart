import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/ui.dart';
import '../../shared/models/servers.dart';
import '../servers/servers_providers.dart';
import 'channels_providers.dart';
import 'create_channel_dialog.dart';

/// Lista de canais de um servidor estilo macOS Sidebar:
/// Header com nome do servidor + botão criar canal, seções em Geist Mono e rows ~32px.
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    serverName ?? 'Servidor',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTokens.textPrimary,
                    ),
                  ),
                ),
                if (isOwner)
                  AppIconButton(
                    icon: Icons.add,
                    tooltip: 'Criar canal',
                    onPressed: () =>
                        showCreateChannelDialog(context, serverId: serverId),
                  ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: AppTokens.borderHairline),
        Expanded(
          child: channels.when(
            loading: () => const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (error, _) => Center(
              child: IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Tentar novamente',
                onPressed: () =>
                    ref.invalidate(channelsControllerProvider(serverId)),
              ),
            ),
            data: (list) => list.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum canal ainda.',
                      style: TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        color: AppTokens.textMuted,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (textChannels.isNotEmpty) ...[
                        const SectionHeader(
                          'CANAIS DE TEXTO',
                          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                        ),
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
                        const SectionHeader(
                          'CANAIS DE VOZ',
                          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                        ),
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
    final confirmed = await showMacModalWindow<bool>(
      context: context,
      title: 'Excluir canal',
      maxWidth: 360,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tem certeza de que deseja excluir o canal #${channel.name}? Esta ação não pode ser desfeita.',
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 13.5,
                color: AppTokens.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AppButton(
                  label: 'Cancelar',
                  variant: AppButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                const SizedBox(width: 8),
                AppButton(
                  label: 'Excluir',
                  variant: AppButtonVariant.danger,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await ref.read(channelsControllerProvider(serverId).notifier).delete(channel.id);
  }
}

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
    final selected = widget.selected;
    final icon = widget.channel.type == ChannelType.text
        ? Icons.tag
        : Icons.volume_up_outlined;
    final baseColor = selected
        ? AppTokens.textPrimary
        : (_hovered ? AppTokens.textPrimary : AppTokens.textSecondary);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTokens.surface3
                : (_hovered ? AppTokens.hoverOverlay : Colors.transparent),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? AppTokens.borderSubtle : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: baseColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.channel.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13.5,
                    color: baseColor,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: widget.isOwner && _hovered ? 1 : 0,
                child: AppIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Excluir canal',
                  minSize: 22,
                  iconSize: 14,
                  onPressed: widget.onDelete,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
