import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_state.dart';
import '../app_icon_button.dart';
import '../section_header.dart';

/// Seção Conta do modal (UI shell): dados de `authControllerProvider`
/// (avatar/nome/username) em rows label+valor, botão "Editar" sem ação.
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
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              foregroundImage:
                  user?.avatarUrl != null ? NetworkImage(user!.avatarUrl!) : null,
              child: user?.avatarUrl == null
                  ? Text(
                      (user?.name.isNotEmpty ?? false)
                          ? user!.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(fontSize: 16),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.name ?? '—',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '@${user?.username ?? ''}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            AppIconButton(
              icon: Icons.edit_outlined,
              tooltip: 'Editar',
              onPressed: () {}, // UI shell: sem ação
            ),
          ],
        ),
        const SizedBox(height: 16),
        _LabelValueRow(label: 'E-mail', value: user?.email ?? '—'),
        const SizedBox(height: 8),
        _LabelValueRow(label: 'ID', value: user?.id ?? '—'),
      ],
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
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
