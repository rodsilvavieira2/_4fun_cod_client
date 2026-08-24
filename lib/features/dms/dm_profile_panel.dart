import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../servers/servers_providers.dart';

/// Painel de perfil do contato (wireframe v3 §4.5): avatar 80, "Membro
/// desde" (data real do membership), "Sobre" placeholder e botão "Ver
/// perfil" sem ação. Só desktop ≥800 com conversa selecionada.
class DmProfilePanel extends ConsumerWidget {
  const DmProfilePanel({super.key, required this.serverId, this.userId});

  final String serverId;

  /// Id do usuário da conversa ativa; nulo = nenhuma selecionada.
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = this.userId;
    if (userId == null) return const SizedBox.shrink();

    // Nome/avatar/data via membros reais do servidor (mesma fonte da lista).
    final detail = ref.watch(serverDetailProvider(serverId)).valueOrNull;
    final member = detail?.members
        .where((m) => m.userId == userId)
        .firstOrNull;

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppThemeColors.card,
        border: Border(left: BorderSide(color: AppThemeColors.hairline)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: CircleAvatar(
                radius: 40,
                foregroundImage: member?.user.avatarUrl != null
                    ? NetworkImage(member!.user.avatarUrl!)
                    : null,
                child: member?.user.avatarUrl == null
                    ? Text(
                        (member?.user.name.isNotEmpty ?? false)
                            ? member!.user.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontSize: 24),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                member?.user.name ?? 'Contato',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '@${member?.user.username ?? ''}',
                style: const TextStyle(
                  color: AppThemeColors.hairline,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Membro desde',
              value: member?.joinedAt != null
                  ? _formatDate(member!.joinedAt)
                  : '—',
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Sobre', value: 'Sem descrição'),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {},
              child: const Text('Ver perfil'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd/$mo/${local.year}';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}
