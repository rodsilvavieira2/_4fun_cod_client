import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/profile_repository.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';
import 'profile_card.dart';
import 'profile_editor_dialog.dart';
import 'profile_status_menu.dart';
import 'ui.dart';

/// Abre o perfil junto ao avatar, sem ocupar toda a tela como o perfil público.
Future<void> showOwnProfilePopover(
  BuildContext context, {
  required String userId,
  required Rect anchor,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar perfil',
    barrierColor: Colors.black.withValues(alpha: .24),
    transitionDuration: const Duration(milliseconds: 160),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        LayoutBuilder(
          builder: (dialogContext, constraints) {
            final size = constraints.biggest;
            final padding = MediaQuery.paddingOf(dialogContext);
            const gap = 8.0;
            const margin = 12.0;
            final width = math.min(340.0, size.width - margin * 2);
            final left = anchor.left.clamp(margin, size.width - width - margin);
            final above = anchor.top - padding.top - margin - gap;
            final below =
                size.height - padding.bottom - margin - anchor.bottom - gap;
            final placeAbove = above >= 260 || above > below;
            final height = math.max(0.0, placeAbove ? above : below);

            return Stack(
              children: [
                Positioned(
                  left: left,
                  width: width,
                  bottom: placeAbove ? size.height - anchor.top + gap : null,
                  top: placeAbove ? null : anchor.bottom + gap,
                  child: SizedBox(
                    height: math.min(520.0, height),
                    child: Material(
                      key: const Key('own-profile-popover'),
                      color: dialogContext.appColors.surface1,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      elevation: 16,
                      clipBehavior: Clip.antiAlias,
                      child: _OwnProfileContent(
                        userId: userId,
                        onEdit: () async {
                          Navigator.of(dialogContext).pop();
                          await showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => const ProfileEditorDialog(),
                          );
                          if (context.mounted) {
                            ProviderScope.containerOf(context).invalidate(
                              profileProvider((userId: userId, serverId: null)),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
  );
}

class _OwnProfileContent extends ConsumerWidget {
  const _OwnProfileContent({required this.userId, required this.onEdit});

  final String userId;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileKey = (userId: userId, serverId: null as String?);
    final profile = ref.watch(profileProvider(profileKey));
    final catalog = ref.watch(visualCatalogProvider).valueOrNull ?? const [];
    final fonts = ref.watch(profileFontsProvider).valueOrNull ?? const [];
    final auth = ref.watch(authControllerProvider).valueOrNull;
    final status = auth is Authenticated ? auth.user.manualStatus : 'ONLINE';

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: profile.when(
                  data: (value) => ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: ProfileCard(
                      profile: value,
                      catalog: catalog,
                      fonts: fonts,
                    ),
                  ),
                  loading: () => const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (error, stack) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Não foi possível carregar o perfil.'),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(profileProvider(profileKey)),
                          child: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ProfileStatusMenu(
            status: status,
            child: _ProfileAction(
              icon: Icons.circle,
              iconColor: switch (status) {
                'IDLE' => AppTokens.accentAmber,
                'DND' => AppTokens.accentDanger,
                'INVISIBLE' => AppTokens.accentOffline,
                _ => AppTokens.accentGreen,
              },
              label: profileStatusLabel(status),
              trailing: Icons.keyboard_arrow_down,
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            key: const Key('own-profile-edit'),
            onTap: onEdit,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: const _ProfileAction(
              icon: Icons.edit_outlined,
              label: 'Editar perfil',
              trailing: Icons.arrow_forward_ios,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({
    required this.icon,
    required this.label,
    required this.trailing,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final IconData trailing;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: iconColor ?? colors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: colors.textPrimary,
              ),
            ),
          ),
          Icon(trailing, size: 14, color: colors.textSecondary),
        ],
      ),
    );
  }
}
