import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_state.dart';
import '../ui.dart';

/// Seção Conta do modal (UI shell): dados de `authControllerProvider` com alto contraste.
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final user = authState is Authenticated ? authState.user : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('CONTA'),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTokens.surface3,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppTokens.borderSubtle, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTokens.surface2,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppTokens.borderHairline, width: 1),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: user?.avatarUrl != null
                    ? Image.network(
                        user!.avatarUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _initial(user.name),
                      )
                    : _initial(user?.name ?? '?'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? '—',
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${user?.username ?? ''}',
                      style: const TextStyle(
                        fontFamily: 'Geist',
                        fontSize: 13,
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppIconButton(
                icon: Icons.edit_outlined,
                tooltip: 'Editar',
                onPressed: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _LabelValueRow(label: 'E-MAIL', value: user?.email ?? '—'),
        const SizedBox(height: 8),
        _LabelValueRow(label: 'ID', value: user?.id ?? '—'),
      ],
    );
  }

  Widget _initial(String name) {
    return Text(
      name.isEmpty ? '?' : name[0].toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Geist',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppTokens.textPrimary,
      ),
    );
  }
}

class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Geist Mono',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTokens.textMuted,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 13.5,
                color: AppTokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
