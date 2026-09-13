import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/ui/ui.dart';
import '../../shared/models/servers.dart';
import 'servers_providers.dart';

/// Administração de membros e cargos com hierarquia inspirada no Discord.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(serverDetailProvider(serverId));
    final online = ref.watch(presenceProvider(serverId));
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final currentUserId = authState is Authenticated ? authState.user.id : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Membros e cargos')),
      body: SafeArea(
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Tentar novamente',
              onPressed: () => ref.invalidate(serverDetailProvider(serverId)),
            ),
          ),
          data: (data) {
            final actorRole = data.myRole ?? ServerRole.member;
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
              children: [
                Text(
                  'Permissões do servidor',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Cada cargo define o que a pessoa pode administrar. O backend valida a mesma hierarquia em todas as ações.',
                  style: TextStyle(color: context.appColors.textSecondary),
                ),
                const SizedBox(height: 16),
                _PermissionOverview(currentRole: actorRole),
                const SizedBox(height: 28),
                for (final role in ServerRole.values) ...[
                  if (data.members.any((member) => member.role == role)) ...[
                    SectionHeader(
                      '${role.label.toUpperCase()} — ${data.members.where((member) => member.role == role).length}',
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                    ),
                    for (final member in data.members.where(
                      (member) => member.role == role,
                    ))
                      _MemberAdminTile(
                        member: member,
                        actorRole: actorRole,
                        isCurrentUser: member.userId == currentUserId,
                        online: online.contains(member.userId),
                        onRoleChanged: (role) =>
                            _changeRole(context, ref, member, role),
                        onRemove: () => _confirmRemove(context, ref, member),
                      ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    ServerMember member,
    ServerRole role,
  ) async {
    if (role == member.role) return;
    try {
      await ref
          .read(serverDetailProvider(serverId).notifier)
          .updateMemberRole(member.userId, role);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${member.user.name} agora é ${role.label}.')),
      );
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    ServerMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover do servidor'),
        content: Text(
          '${member.user.name} perderá acesso aos canais de texto e voz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(serverDetailProvider(serverId).notifier)
          .removeMember(member.userId);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _PermissionOverview extends StatelessWidget {
  const _PermissionOverview({required this.currentRole});

  final ServerRole currentRole;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 780 ? 3 : 1;
        final width = columns == 3
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final role in ServerRole.values)
              SizedBox(
                width: width,
                child: AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ServerRoleBadge(role: role),
                          const Spacer(),
                          if (role == currentRole)
                            const AppBadge(label: 'Seu cargo'),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        role.description,
                        style: TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 12.5,
                          color: context.appColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MemberAdminTile extends StatelessWidget {
  const _MemberAdminTile({
    required this.member,
    required this.actorRole,
    required this.isCurrentUser,
    required this.online,
    required this.onRoleChanged,
    required this.onRemove,
  });

  final ServerMember member;
  final ServerRole actorRole;
  final bool isCurrentUser;
  final bool online;
  final ValueChanged<ServerRole> onRoleChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final canChangeRole =
        actorRole.canManageRoles && !member.isOwner && !isCurrentUser;
    final canRemove = !isCurrentUser && actorRole.canRemove(member.role);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderHairline),
      ),
      child: ListTile(
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: colors.surface3,
              child: member.user.avatarUrl == null
                  ? Text(
                      member.user.name.isEmpty
                          ? '?'
                          : member.user.name[0].toUpperCase(),
                    )
                  : ClipOval(
                      child: AppFileImage(
                        path: member.user.avatarUrl,
                        width: 40,
                        height: 40,
                        fallback: Text(
                          member.user.name.isEmpty
                              ? '?'
                              : member.user.name[0].toUpperCase(),
                        ),
                      ),
                    ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: PresenceDot(
                status: online ? PresenceStatus.online : PresenceStatus.offline,
                size: 10,
              ),
            ),
          ],
        ),
        title: Text(
          isCurrentUser ? '${member.user.name} (você)' : member.user.name,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('@${member.user.username}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canChangeRole)
              AppMenuButton<ServerRole>(
                tooltip: 'Alterar cargo',
                initialValue: member.role,
                onSelected: onRoleChanged,
                itemBuilder: (context) => [
                  AppMenuItem<ServerRole>.labeled(
                    value: ServerRole.admin,
                    label: 'Administrador',
                  ),
                  AppMenuItem<ServerRole>.labeled(
                    value: ServerRole.member,
                    label: 'Membro',
                  ),
                ],
                child: ServerRoleBadge(role: member.role),
              )
            else
              ServerRoleBadge(role: member.role),
            if (canRemove) ...[
              const SizedBox(width: 4),
              AppIconButton(
                icon: Icons.person_remove_outlined,
                tooltip: 'Remover do servidor',
                onPressed: onRemove,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
