import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_service.dart';
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
    required this.canManageServer,
    this.canLeaveServer = false,
    this.selectedChannelId,
    this.activeVoiceChannelId,
    this.activeVoiceParticipants = const [],
    this.onChannelSelected,
    this.onOpenInvites,
    this.onOpenMembers,
    this.onOpenSettings,
    this.onLeaveServer,
    this.listBottomPadding = 8,
  });

  final String serverId;
  final bool canManageServer;
  final bool canLeaveServer;
  final String? selectedChannelId;

  /// Fonte local e imediata para a sala ativa: evita depender do atraso do
  /// espelho LiveKit → webhook → Socket.IO para mostrar quem acabou de entrar.
  final String? activeVoiceChannelId;
  final List<RtcParticipant> activeVoiceParticipants;
  final ValueChanged<String>? onChannelSelected;
  final VoidCallback? onOpenInvites;
  final VoidCallback? onOpenMembers;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onLeaveServer;

  /// Espaço extra no fim da rolagem — usado quando um controller flutuante
  /// sobrepõe a base da lista, para o último canal não ficar escondido.
  final double listBottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(channelsControllerProvider(serverId));
    final serverName = ref
        .watch(serverDetailProvider(serverId))
        .valueOrNull
        ?.server
        .name;
    final members =
        ref.watch(serverDetailProvider(serverId)).valueOrNull?.members ??
        const <ServerMember>[];
    final membersById = {for (final member in members) member.userId: member};
    final voiceOccupants = ref.watch(voicePresenceProvider(serverId));
    final textChannels = <ServerChannel>[];
    final voiceChannels = <ServerChannel>[];
    for (final channel in channels.valueOrNull ?? const <ServerChannel>[]) {
      (channel.type == ChannelType.text ? textChannels : voiceChannels).add(
        channel,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: SizedBox(
            height: AppLayout.headerHeight,
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
                PopupMenuButton<String>(
                  tooltip: 'Menu do servidor',
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppTokens.textSecondary,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'invite':
                        onOpenInvites?.call();
                        break;
                      case 'create':
                        showCreateChannelDialog(context, serverId: serverId);
                        break;
                      case 'members':
                        onOpenMembers?.call();
                        break;
                      case 'settings':
                        if (canManageServer) onOpenSettings?.call();
                        break;
                      case 'leave':
                        if (canLeaveServer) onLeaveServer?.call();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (canManageServer) ...[
                      const PopupMenuItem(
                        value: 'invite',
                        child: _ServerMenuEntry(
                          icon: Icons.person_add_alt_1_outlined,
                          label: 'Convidar pessoas',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'create',
                        child: _ServerMenuEntry(
                          icon: Icons.add_circle_outline,
                          label: 'Criar canal',
                        ),
                      ),
                    ],
                    const PopupMenuItem(
                      value: 'members',
                      child: _ServerMenuEntry(
                        icon: Icons.group_outlined,
                        label: 'Membros e cargos',
                      ),
                    ),
                    if (canManageServer) ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'settings',
                        child: _ServerMenuEntry(
                          icon: Icons.settings_outlined,
                          label: 'Configurações do servidor',
                        ),
                      ),
                    ],
                    if (canLeaveServer) ...[
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'leave',
                        child: _ServerMenuEntry(
                          icon: Icons.logout,
                          label: 'Sair do servidor',
                        ),
                      ),
                    ],
                  ],
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
                    padding: EdgeInsets.fromLTRB(0, 8, 0, listBottomPadding),
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
                            connected: false,
                            canManageServer: canManageServer,
                            onTap: () => onChannelSelected?.call(channel.id),
                            onDelete: () =>
                                _confirmDelete(context, ref, channel),
                          ),
                      ],
                      if (voiceChannels.isNotEmpty) ...[
                        const SectionHeader(
                          'CANAIS DE VOZ',
                          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                        ),
                        for (final channel in voiceChannels)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ChannelRow(
                                channel: channel,
                                selected: channel.id == selectedChannelId,
                                connected: channel.id == activeVoiceChannelId,
                                canManageServer: canManageServer,
                                onTap: () =>
                                    onChannelSelected?.call(channel.id),
                                onDelete: () =>
                                    _confirmDelete(context, ref, channel),
                              ),
                              for (final occupant in _occupantsFor(
                                channelId: channel.id,
                                mirroredIds:
                                    voiceOccupants[channel.id] ??
                                    const <String>{},
                                membersById: membersById,
                              ))
                                _VoiceOccupantRow(occupant: occupant),
                            ],
                          ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  List<_VoiceOccupant> _occupantsFor({
    required String channelId,
    required Set<String> mirroredIds,
    required Map<String, ServerMember> membersById,
  }) {
    final rtcByUserId = <String, RtcParticipant>{};
    if (channelId == activeVoiceChannelId) {
      for (final participant in activeVoiceParticipants) {
        final userId = _userIdFromIdentity(participant.id);
        if (userId != null) rtcByUserId[userId] = participant;
      }
    }
    final userIds = {...mirroredIds, ...rtcByUserId.keys}.toList()
      ..sort((left, right) {
        final leftName = _displayName(
          membersById[left],
          rtcByUserId[left],
          left,
        );
        final rightName = _displayName(
          membersById[right],
          rtcByUserId[right],
          right,
        );
        return leftName.toLowerCase().compareTo(rightName.toLowerCase());
      });
    return [
      for (final userId in userIds)
        _VoiceOccupant(
          userId: userId,
          member: membersById[userId],
          participant: rtcByUserId[userId],
        ),
    ];
  }

  String? _userIdFromIdentity(String identity) {
    const prefix = 'user_';
    if (!identity.startsWith(prefix)) return null;
    final userId = identity.substring(prefix.length);
    return userId.isEmpty ? null : userId;
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
    await ref
        .read(channelsControllerProvider(serverId).notifier)
        .delete(channel.id);
  }
}

class _ServerMenuEntry extends StatelessWidget {
  const _ServerMenuEntry({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 17), const SizedBox(width: 10), Text(label)],
    );
  }
}

String _displayName(
  ServerMember? member,
  RtcParticipant? participant,
  String fallbackId,
) {
  final username = member?.user.username.trim();
  if (username != null && username.isNotEmpty) return username;
  final rtcName = participant?.name.trim();
  if (rtcName != null && rtcName.isNotEmpty) return rtcName;
  return member?.user.name ?? fallbackId;
}

/// Participante compacto abaixo de um canal de voz, no mesmo agrupamento
/// visual usado pelo Discord. Estado detalhado de fala/mídia segue no palco
/// da sala ativa, que recebe o stream direto do LiveKit.
class _VoiceOccupant {
  const _VoiceOccupant({
    required this.userId,
    required this.member,
    required this.participant,
  });

  final String userId;
  final ServerMember? member;
  final RtcParticipant? participant;

  String get name => _displayName(member, participant, userId);
  String? get avatarUrl => member?.user.avatarUrl;
}

class _VoiceOccupantRow extends StatelessWidget {
  const _VoiceOccupantRow({required this.occupant});

  final _VoiceOccupant occupant;

  @override
  Widget build(BuildContext context) {
    final participant = occupant.participant;
    final isSpeaking = participant?.isSpeaking == true;
    return Padding(
      padding: const EdgeInsets.only(left: 32, right: 12, bottom: 2),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: isSpeaking
                  ? AppTokens.accentGreen
                  : AppTokens.surface3,
              backgroundImage: occupant.avatarUrl == null
                  ? null
                  : NetworkImage(occupant.avatarUrl!),
              child: occupant.avatarUrl == null
                  ? Text(
                      occupant.name.isEmpty
                          ? '?'
                          : occupant.name[0].toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                occupant.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  color: AppTokens.textSecondary,
                ),
              ),
            ),
            if (participant != null) ...[
              const SizedBox(width: 4),
              Icon(
                participant.isMicrophoneEnabled ? Icons.mic : Icons.mic_off,
                size: 14,
                color: participant.isMicrophoneEnabled
                    ? AppTokens.textMuted
                    : AppTokens.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChannelRow extends StatefulWidget {
  const _ChannelRow({
    required this.channel,
    required this.selected,
    required this.connected,
    required this.canManageServer,
    required this.onTap,
    required this.onDelete,
  });

  final ServerChannel channel;
  final bool selected;
  final bool connected;
  final bool canManageServer;
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
        : (widget.connected
              ? AppTokens.accentGreen
              : (_hovered ? AppTokens.textPrimary : AppTokens.textSecondary));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
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
                opacity: widget.canManageServer && _hovered ? 1 : 0,
                child: AppIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Excluir canal',
                  minSize: 22,
                  iconSize: 14,
                  onPressed: widget.canManageServer ? widget.onDelete : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
