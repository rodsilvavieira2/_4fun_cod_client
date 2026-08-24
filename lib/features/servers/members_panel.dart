import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/ui/presence_dot.dart';
import '../../core/ui/section_header.dart';
import '../../shared/models/servers.dart';
import 'servers_providers.dart';

/// Painel lateral de membros (wireframe v3 §4.4): 240px, só desktop ≥800,
/// READ-ONLY — grupos ONLINE/OFFLINE caps + dot de presença. A ação de
/// remoção de membro (OWNER) continua na tela push `members_screen.dart`.
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
    for (final member in members) {
      (online.contains(member.userId) ? onlineMembers : offlineMembers)
          .add(member);
    }

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppThemeColors.card,
        border: Border(left: BorderSide(color: AppThemeColors.hairline)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          if (onlineMembers.isNotEmpty) ...[
            const SectionHeader('ONLINE'),
            for (final member in onlineMembers)
              _MemberRow(member: member, online: true),
          ],
          if (offlineMembers.isNotEmpty) ...[
            const SectionHeader('OFFLINE'),
            for (final member in offlineMembers)
              _MemberRow(member: member, online: false),
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.online});

  final ServerMember member;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final user = member.user;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            foregroundImage:
                user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
            child: user.avatarUrl == null
                ? Text(
                    user.name.isEmpty ? '?' : user.name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 11),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              user.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: online ? FontWeight.w600 : FontWeight.w400,
                color: online
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          // Dot de presença (componente compartilhado core/ui).
          PresenceDot(online: online),
        ],
      ),
    );
  }
}
