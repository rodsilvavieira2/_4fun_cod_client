import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/ui.dart';
import '../servers/servers_providers.dart';

/// Painel de perfil do contato estilo macOS Sidebar:
/// Avatar 80, username com alto contraste, dados de adesão e ação de perfil.
class DmProfilePanel extends ConsumerWidget {
  const DmProfilePanel({super.key, required this.serverId, this.userId});

  final String serverId;
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = this.userId;
    if (userId == null) return const SizedBox.shrink();

    final detail = ref.watch(serverDetailProvider(serverId)).valueOrNull;
    final member = detail?.members
        .where((m) => m.userId == userId)
        .firstOrNull;

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: AppTokens.surface1,
        border: Border(
          left: BorderSide(color: AppTokens.borderHairline, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTokens.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppTokens.borderSubtle, width: 1),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: member?.user.avatarUrl != null
                    ? Image.network(
                        member!.user.avatarUrl!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _initial(member.user.name),
                      )
                    : _initial(member?.user.name ?? '?'),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                member?.user.name ?? 'Contato',
                style: const TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTokens.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Center(
              child: Text(
                '@${member?.user.username ?? ''}',
                style: const TextStyle(
                  fontFamily: 'Geist',
                  color: AppTokens.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Divider(height: 1, color: AppTokens.borderHairline),
            const SizedBox(height: 14),
            _InfoRow(
              label: 'MEMBRO DESDE',
              value: member?.joinedAt != null
                  ? _formatDate(member!.joinedAt)
                  : '—',
            ),
            const SizedBox(height: 14),
            const _InfoRow(label: 'SOBRE', value: 'Sem descrição'),
            const SizedBox(height: 22),
            AppButton(
              label: 'Ver perfil completo',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              onPressed: () {},
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
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: AppTokens.textPrimary,
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
          style: const TextStyle(
            fontFamily: 'Geist Mono',
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: AppTokens.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Geist',
            fontSize: 13.5,
            color: AppTokens.textPrimary,
          ),
        ),
      ],
    );
  }
}
