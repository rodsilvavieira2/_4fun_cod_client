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
      // BoxDecoration. Padding 10/14 conforme wireframe (.user-panel).
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppThemeColors.card,
        border: Border(top: BorderSide(color: AppThemeColors.hairline)),
      ),
      child: Row(
        children: [
          // Avatar 32 com "ring" (wireframe: .up-avatar .ring radius 8,
          // borda hairline, fundo bg-surface).
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
            child: avatarUrl != null
                ? Image.network(
                    avatarUrl,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _initial(name),
                  )
                : _initial(name),
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
          // Ícones 28x28 com gap 4 (wireframe: .up-icons gap 4, .up-icon
          // 28x28 radius 6).
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                icon: Icons.mic_none,
                tooltip: 'Microfone',
                minSize: 28,
                onPressed: () {},
              ),
              AppIconButton(
                icon: Icons.headset_outlined,
                tooltip: 'Fones de ouvido',
                minSize: 28,
                onPressed: () {},
              ),
              AppIconButton(
                icon: Icons.settings_outlined,
                tooltip: 'Configurações',
                minSize: 28,
                onPressed: onOpenSettings,
              ),
            ],
          ),
        ],
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
