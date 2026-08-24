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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            // Avatar 32 com ring + dot de presença no canto (wireframe:
            // .member .ava 32x32 radius 8, .dot 10px right/bottom -4).
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppThemeColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppThemeColors.hairline),
                  ),
                  alignment: Alignment.center,
                  clipBehavior: Clip.antiAlias,
                  child: user.avatarUrl != null
                      ? Image.network(
                          user.avatarUrl!,
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _initial(user.name),
                        )
                      : _initial(user.name),
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: PresenceDot(online: online, size: 10),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                user.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: online
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _initial(String name) {
    return Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
  }
}
