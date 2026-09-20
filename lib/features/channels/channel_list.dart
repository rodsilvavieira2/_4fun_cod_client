import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_service.dart';
import '../../core/rtc/rtc_providers.dart';
import '../../core/ui/participant_volume_popover.dart';
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
    final colors = context.appColors;
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
    final localParticipantId = ref.watch(rtcServiceProvider).localParticipantId;
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
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                AppMenuButton<String>(
                  tooltip: 'Menu do servidor',
                  icon: AppIcon(
                    AppIcons.chevronDown,
                    size: 18,
                    color: colors.textSecondary,
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
                      AppMenuItem<String>.labeled(
                        value: 'invite',
                        icon: AppIcons.userAdd,
                        label: 'Convidar pessoas',
                      ),
                      AppMenuItem<String>.labeled(
                        value: 'create',
                        icon: AppIcons.addCircle,
                        label: 'Criar canal',
                      ),
                    ],
                    AppMenuItem<String>.labeled(
                      value: 'members',
                      icon: AppIcons.userGroup,
                      label: 'Membros e cargos',
                    ),
                    if (canManageServer) ...[
                      const AppMenuDivider(),
                      AppMenuItem<String>.labeled(
                        value: 'settings',
                        icon: AppIcons.settings,
                        label: 'Configurações do servidor',
                      ),
                    ],
                    if (canLeaveServer) ...[
                      const AppMenuDivider(),
                      AppMenuItem<String>.labeled(
                        value: 'leave',
                        icon: AppIcons.logout,
                        label: 'Sair do servidor',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: colors.borderHairline),
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
                icon: AppIcon(AppIcons.refresh, size: 18),
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
                                _VoiceOccupantRow(
                                  occupant: occupant,
                                  localParticipantId: localParticipantId,
                                ),
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

const _voiceAvatarGoldenAngle = 137.50776405003785;

Color _voiceOccupantAccent(_VoiceOccupant occupant) {
  final hash = _stableVoiceOccupantHash('${occupant.userId}|${occupant.name}');
  final hue = ((hash % 1024) * _voiceAvatarGoldenAngle) % 360;
  return HSVColor.fromAHSV(1, hue, 0.42, 0.76).toColor();
}

int _stableVoiceOccupantHash(String value) {
  const fnvPrime = 0x01000193;
  var hash = 0x811C9DC5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return hash;
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
  const _VoiceOccupantRow({
    required this.occupant,
    required this.localParticipantId,
  });

  final _VoiceOccupant occupant;
  final String? localParticipantId;

  @override
  Widget build(BuildContext context) {
    final participant = occupant.participant;
    final isSpeaking = participant?.isSpeaking == true;
    final canOpenVolume =
        participant != null && participant.id != localParticipantId;
    final accent = _voiceOccupantAccent(occupant);
    final row = Padding(
      padding: const EdgeInsets.only(left: 32, right: 12, bottom: 2),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            _VoiceOccupantAvatar(
              occupant: occupant,
              accent: accent,
              speaking: isSpeaking,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 13,
                  fontWeight: isSpeaking ? FontWeight.w600 : FontWeight.w400,
                  color: isSpeaking
                      ? AppTokens.textPrimary
                      : AppTokens.textSecondary,
                ),
                child: Text(occupant.name, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (participant != null) ...[
              const SizedBox(width: 6),
              _VoiceOccupantSpeakingMeter(active: isSpeaking, accent: accent),
              const SizedBox(width: 6),
              AppIcon(
                participant.isMicrophoneEnabled
                    ? AppIcons.mic
                    : AppIcons.micOff,
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
    if (!canOpenVolume) return row;
    return ParticipantVolumeMenuRegion(
      identity: participant.id,
      displayName: occupant.name,
      child: row,
    );
  }
}

class _VoiceOccupantAvatar extends StatelessWidget {
  const _VoiceOccupantAvatar({
    required this.occupant,
    required this.accent,
    required this.speaking,
  });

  final _VoiceOccupant occupant;
  final Color accent;
  final bool speaking;

  @override
  Widget build(BuildContext context) {
    final initial = occupant.name.isEmpty
        ? '?'
        : occupant.name[0].toUpperCase();
    final image = occupant.avatarUrl;
    return SizedBox.square(
      dimension: 32,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: image == null
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(
                        accent.withValues(alpha: speaking ? 0.54 : 0.32),
                        AppTokens.surface3,
                      ),
                      Color.alphaBlend(
                        accent.withValues(alpha: speaking ? 0.24 : 0.10),
                        AppTokens.surface2,
                      ),
                    ],
                  )
                : null,
            color: image == null ? null : AppTokens.surface3,
            border: Border.all(
              color: speaking
                  ? accent.withValues(alpha: 0.95)
                  : Colors.white.withValues(alpha: 0.05),
              width: speaking ? 3.5 : 1,
            ),
            boxShadow: [
              if (speaking)
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 10,
                  spreadRadius: -3,
                ),
            ],
          ),
          child: ClipOval(
            child: image == null
                ? Center(child: _VoiceOccupantInitial(initial: initial))
                : AppFileImage(
                    path: image,
                    width: 24,
                    height: 24,
                    fallback: Center(
                      child: _VoiceOccupantInitial(initial: initial),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _VoiceOccupantInitial extends StatelessWidget {
  const _VoiceOccupantInitial({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Text(
      initial,
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTokens.textPrimary,
      ),
    );
  }
}

class _VoiceOccupantSpeakingMeter extends StatefulWidget {
  const _VoiceOccupantSpeakingMeter({
    required this.active,
    required this.accent,
  });

  final bool active;
  final Color accent;

  @override
  State<_VoiceOccupantSpeakingMeter> createState() =>
      _VoiceOccupantSpeakingMeterState();
}

class _VoiceOccupantSpeakingMeterState
    extends State<_VoiceOccupantSpeakingMeter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_VoiceOccupantSpeakingMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const SizedBox(width: 16, height: 16);
    }

    return RepaintBoundary(
      key: const ValueKey('voice-occupant-speaking-meter'),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _VoiceOccupantMeterPainter(
            progress: _controller.value,
            accent: widget.accent,
          ),
          child: const SizedBox(width: 16, height: 16),
        ),
      ),
    );
  }
}

class _VoiceOccupantMeterPainter extends CustomPainter {
  const _VoiceOccupantMeterPainter({
    required this.progress,
    required this.accent,
  });

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const barWidth = 2.2;
    const gap = 1.65;
    const minHeight = 4.0;
    const maxHeight = 13.0;
    const phases = [0.0, 0.34, 0.68, 0.18];
    const weights = [0.68, 1.0, 0.82, 0.54];
    final totalWidth = barWidth * phases.length + gap * (phases.length - 1);
    final startX = (size.width - totalWidth) / 2;
    final centerY = size.height / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var index = 0; index < phases.length; index++) {
      final phase = (progress + phases[index]) % 1;
      final wave = (math.sin(phase * math.pi * 2) + 1) / 2;
      final eased = Curves.easeInOutCubic.transform(wave);
      final height =
          minHeight + (maxHeight - minHeight) * eased * weights[index];
      final x = startX + index * (barWidth + gap);
      final rect = Rect.fromLTWH(x, centerY - height / 2, barWidth, height);
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accent.withValues(alpha: 0.95),
          accent.withValues(alpha: 0.36),
        ],
      ).createShader(rect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(barWidth)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_VoiceOccupantMeterPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.accent != accent;
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
    final colors = context.appColors;
    final selected = widget.selected;
    final icon = widget.channel.type == ChannelType.text
        ? AppIcons.channelText
        : AppIcons.volumeHigh;
    final baseColor = selected
        ? colors.textPrimary
        : (widget.connected
              ? AppTokens.accentGreen
              : (_hovered ? colors.textPrimary : colors.textSecondary));

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
                ? colors.surface3
                : (_hovered ? colors.hoverOverlay : Colors.transparent),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? colors.borderSubtle : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              AppIcon(icon, size: 15, color: baseColor),
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
                  icon: AppIcons.delete,
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
