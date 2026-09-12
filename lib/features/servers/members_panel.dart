import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/rtc/rtc_providers.dart';
import '../../core/ui/participant_volume_popover.dart';
import '../../core/ui/ui.dart';
import '../../shared/models/servers.dart';
import 'servers_providers.dart';

/// Painel lateral de membros estilo macOS Sidebar (240px, grupos ONLINE/OFFLINE).
class MembersPanel extends ConsumerWidget {
  const MembersPanel({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(serverDetailProvider(serverId));
    final online = ref.watch(presenceProvider(serverId));
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
      decoration: const BoxDecoration(
        color: AppTokens.surface1,
        border: Border(
          left: BorderSide(color: AppTokens.borderHairline, width: 1),
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
              _MemberRow(member: member, online: true),
          ],
          if (offlineMembers.isNotEmpty) ...[
            SectionHeader(
              'OFFLINE — ${offlineMembers.length}',
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            ),
            for (final member in offlineMembers)
              _MemberRow(member: member, online: false),
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends ConsumerStatefulWidget {
  const _MemberRow({required this.member, required this.online});

  final ServerMember member;
  final bool online;

  @override
  ConsumerState<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends ConsumerState<_MemberRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.member.user;
    final online = widget.online;
    // Nickname (username) primeiro — cai para o nome se vazio.
    final displayName = user.username.trim().isNotEmpty
        ? user.username
        : user.name;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _hovered ? AppTokens.hoverOverlay : Colors.transparent,
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
                    color: AppTokens.surface2,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: AppTokens.borderHairline,
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
                    status: online
                        ? PresenceStatus.online
                        : PresenceStatus.offline,
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
                  color: online ? AppTokens.textPrimary : AppTokens.textMuted,
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
    );
  }

  Widget _initial(String name) {
    return Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTokens.textPrimary,
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
