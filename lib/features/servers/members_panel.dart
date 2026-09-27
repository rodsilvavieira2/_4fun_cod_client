import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_providers.dart';
import '../../core/ui/participant_volume_popover.dart';
import '../../core/ui/ui.dart';
import '../../shared/models/servers.dart';
import 'servers_providers.dart';
import '../../core/ui/profile_popup.dart';

/// Painel lateral de membros estilo macOS Sidebar (240px, grupos ONLINE/OFFLINE).
class MembersPanel extends ConsumerWidget {
  const MembersPanel({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final detail = ref.watch(serverDetailProvider(serverId));
    final online = ref.watch(presenceProvider(serverId));
    final statuses = ref.watch(presenceStatusProvider(serverId));
    final members = detail.valueOrNull?.members ?? const <ServerMember>[];

    final onlineMembers = <ServerMember>[];
    final offlineMembers = <ServerMember>[];
    final orderedMembers = [...members]
      ..sort((left, right) => left.role.index.compareTo(right.role.index));
    for (final member in orderedMembers) {
      (online.contains(member.userId) ? onlineMembers : offlineMembers).add(
        member,
      );
    }

    return Container(
      width: AppLayout.memberPanelWidth,
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(
          left: BorderSide(color: colors.borderHairline, width: 1),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (onlineMembers.isNotEmpty) ...[
            SectionHeader(
              'ONLINE — ${onlineMembers.length}',
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            ),
            for (final member in onlineMembers)
              _MemberRow(
                member: member,
                serverId: serverId,
                online: true,
                status: statuses[member.userId] ?? 'ONLINE',
              ),
          ],
          if (offlineMembers.isNotEmpty) ...[
            SectionHeader(
              'OFFLINE — ${offlineMembers.length}',
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            ),
            for (final member in offlineMembers)
              _MemberRow(
                member: member,
                serverId: serverId,
                online: false,
                status: 'OFFLINE',
              ),
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends ConsumerStatefulWidget {
  const _MemberRow({
    required this.member,
    required this.serverId,
    required this.online,
    required this.status,
  });

  final ServerMember member;
  final String serverId;
  final bool online;
  final String status;

  @override
  ConsumerState<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends ConsumerState<_MemberRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final user = widget.member.user;
    final online = widget.online;
    final displayName = user.name;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => showProfilePopup(
          context,
          widget.member.userId,
          serverId: widget.serverId,
        ),
        child: Container(
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? colors.hoverOverlay : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: colors.borderHairline,
                        width: 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    clipBehavior: Clip.antiAlias,
                    child: user.avatarUrl != null
                        ? AppFileImage(
                            path: user.avatarUrl,
                            width: 30,
                            height: 30,
                            fallback: _initial(displayName),
                          )
                        : _initial(displayName),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: PresenceDot(
                      status: switch (widget.status) {
                        'IDLE' => PresenceStatus.idle,
                        'DND' => PresenceStatus.dnd,
                        'ONLINE' => PresenceStatus.online,
                        _ => PresenceStatus.offline,
                      },
                      size: 9,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  displayName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: online ? colors.textPrimary : colors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ServerRoleBadge(role: widget.member.role, showLabel: false),
              _VoiceVolumeAction(
                userId: widget.member.userId,
                displayName: displayName,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _initial(String name) {
    return Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: TextStyle(
        fontFamily: 'Geist',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.appColors.textPrimary,
      ),
    );
  }
}

/// Botão de volume individual na linha do membro — visível só para quem está
/// na sala de voz atual e não é o usuário local (mesma regra do tile da sala).
class _VoiceVolumeAction extends ConsumerWidget {
  const _VoiceVolumeAction({required this.userId, required this.displayName});

  final String userId;
  final String displayName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final participants =
        ref.watch(rtcParticipantsProvider).valueOrNull ?? const [];
    if (participants.isEmpty) return const SizedBox.shrink();
    final rtc = ref.watch(rtcServiceProvider);
    final identity = 'user_$userId';
    if (rtc.localParticipantId == identity) return const SizedBox.shrink();
    final participant = participants.where((p) => p.id == identity).firstOrNull;
    if (participant == null) return const SizedBox.shrink();
    return ParticipantVolumeButton(
      identity: identity,
      displayName: displayName,
    );
  }
}
