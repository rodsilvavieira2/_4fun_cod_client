import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui/app_icon_button.dart';

/// Rodapé da sidebar (wireframe v3 §4.2): avatar 32 + nome + status, e 3
/// ícones de ação (mic/fones/⚙️). O ⚙️ dispara [onOpenSettings] (SPEC 3
/// implementa o modal; aqui só a cablagem).
class UserPanel extends ConsumerWidget {
  const UserPanel({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider).valueOrNull;
    final user = authState is Authenticated ? authState.user : null;
    final name = user?.name ?? '…';
    final avatarUrl = user?.avatarUrl;

    return Container(
      // color + decoration simultâneos disparam a assert do Flutter
      // ("color is just a shorthand for decoration") — cor vai no
      // BoxDecoration.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: AppThemeColors.card,
        border: Border(top: BorderSide(color: AppThemeColors.hairline)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            foregroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: const TextStyle(fontSize: 12),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Text(
                  'Online',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppStatusColors.online,
                  ),
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: Icons.mic_none,
            tooltip: 'Microfone',
            minSize: 32,
            onPressed: () {},
          ),
          AppIconButton(
            icon: Icons.headset_outlined,
            tooltip: 'Fones de ouvido',
            minSize: 32,
            onPressed: () {},
          ),
          AppIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Configurações',
            minSize: 32,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}
