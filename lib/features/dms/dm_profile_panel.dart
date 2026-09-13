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
    final colors = context.appColors;
    final userId = this.userId;
    if (userId == null) return const SizedBox.shrink();

    final detail = ref.watch(serverDetailProvider(serverId)).valueOrNull;
    final member = detail?.members.where((m) => m.userId == userId).firstOrNull;

    return Container(
      width: AppLayout.memberPanelWidth,
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(
          left: BorderSide(color: colors.borderHairline, width: 1),
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
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: colors.borderSubtle, width: 1),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: member?.user.avatarUrl != null
                    ? AppFileImage(
                        path: member?.user.avatarUrl,
                        width: 72,
                        height: 72,
                        fallback: _initial(member?.user.name ?? '?', colors),
                      )
                    : _initial(member?.user.name ?? '?', colors),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                member?.user.name ?? 'Contato',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Center(
              child: Text(
                '@${member?.user.username ?? ''}',
                style: TextStyle(
                  fontFamily: 'Geist',
                  color: colors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Divider(height: 1, color: colors.borderHairline),
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

  Widget _initial(String name, AppThemePalette colors) {
    return Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: TextStyle(
        fontFamily: 'Geist',
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
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
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Geist Mono',
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: colors.textMuted,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Geist',
            fontSize: 13.5,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
