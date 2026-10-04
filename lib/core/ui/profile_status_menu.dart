import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/profile_repository.dart';
import '../auth/auth_controller.dart';

String profileStatusLabel(String status) => switch (status) {
  'IDLE' => 'Ausente',
  'DND' => 'Não perturbe',
  'INVISIBLE' => 'Invisível',
  _ => 'Online',
};

/// A mesma seleção de presença no rodapé e no cartão do próprio usuário.
class ProfileStatusMenu extends ConsumerWidget {
  const ProfileStatusMenu({
    super.key,
    required this.status,
    required this.child,
  });

  final String status;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Alterar status',
      onSelected: (value) async {
        if (value == status) return;
        try {
          final repository = ref.read(profileRepositoryProvider);
          final auth = ref.read(authControllerProvider.notifier);
          await repository.setStatus(value);
          await auth.refreshCurrentUser();
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Não foi possível alterar o status.'),
              ),
            );
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'ONLINE', child: Text('Online')),
        PopupMenuItem(value: 'IDLE', child: Text('Ausente')),
        PopupMenuItem(value: 'DND', child: Text('Não perturbe')),
        PopupMenuItem(value: 'INVISIBLE', child: Text('Invisível')),
      ],
      child: child,
    );
  }
}
