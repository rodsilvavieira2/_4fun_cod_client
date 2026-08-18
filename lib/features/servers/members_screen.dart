import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/models/servers.dart';
import 'servers_providers.dart';

/// Lista de membros do servidor com remoção (apenas OWNER, e nunca de si
/// mesmo nem de outros donos).
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(serverDetailProvider(serverId));
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final currentUserId = authState is Authenticated ? authState.user.id : null;
    final isOwner = detail.valueOrNull?.isOwner ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Membros')),
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
          data: (data) => ListView.builder(
            itemCount: data.members.length,
            itemBuilder: (context, index) {
              final member = data.members[index];
              final canRemove = isOwner &&
                  member.userId != currentUserId &&
                  !member.isOwner;
              return ListTile(
                leading: CircleAvatar(
                  foregroundImage: member.user.avatarUrl != null
                      ? NetworkImage(member.user.avatarUrl!)
                      : null,
                  child: member.user.avatarUrl == null
                      ? Text(
                          member.user.name.isEmpty
                              ? '?'
                              : member.user.name[0].toUpperCase(),
                        )
                      : null,
                ),
                title: Text(member.user.name),
                subtitle: Text('@${member.user.username}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoleChip(role: member.role),
                    if (canRemove)
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        tooltip: 'Remover membro',
                        onPressed: () => _confirmRemove(context, ref, member),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    ServerMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover membro'),
        content: Text('Remover ${member.user.name} deste servidor?'),
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
    await ref
        .read(serverDetailProvider(serverId).notifier)
        .removeMember(member.userId);
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(role == 'OWNER' ? 'Dono' : 'Membro'),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
