import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/profile_repository.dart';
import '../theme/appearance_theme.dart';
import 'profile_card.dart';

Future<void> showProfilePopup(
  BuildContext context,
  String userId, {
  String? serverId,
}) => showDialog<void>(
  context: context,
  builder: (_) => ProfilePopup(userId: userId, serverId: serverId),
);

class ProfilePopup extends ConsumerWidget {
  const ProfilePopup({super.key, required this.userId, this.serverId});
  final String userId;
  final String? serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(
      profileProvider((userId: userId, serverId: serverId)),
    );
    final catalog = ref.watch(visualCatalogProvider).valueOrNull ?? const [];
    final fonts = ref.watch(profileFontsProvider).valueOrNull ?? const [];
    return Dialog(
      backgroundColor: context.appColors.surface1,
      child: SizedBox(
        width: 420,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      serverId == null ? 'Perfil' : 'Perfil neste servidor',
                      style: TextStyle(
                        color: context.appColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              profile.when(
                data: (value) =>
                    ProfileCard(profile: value, catalog: catalog, fonts: fonts),
                loading: () => const Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) =>
                    Text('Não foi possível abrir o perfil: $error'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
