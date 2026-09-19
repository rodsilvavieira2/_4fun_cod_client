import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../notifications/notification_preferences.dart';
import '../app_icon.dart';
import '../settings_section_layout.dart';

class NotificationsSection extends ConsumerWidget {
  const NotificationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(notificationPreferencesProvider);
    final value = preferences.valueOrNull ?? NotificationPreferences.defaults;
    final controller = ref.read(notificationPreferencesProvider.notifier);
    final enabled = !preferences.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsStack(
          children: [
            SettingsGroup(
              title: 'Conversas',
              children: [
                SettingsRow(
                  icon: AppIcons.channelText,
                  title: 'Mensagens em canais',
                  trailing: SettingsSwitch(
                    value: value.channelMessages,
                    onChanged: enabled ? controller.setChannelMessages : null,
                  ),
                ),
                SettingsRow(
                  icon: AppIcons.mention,
                  title: 'Menções com @',
                  trailing: SettingsSwitch(
                    value: value.mentions,
                    onChanged: enabled ? controller.setMentions : null,
                  ),
                ),
              ],
            ),
            SettingsGroup(
              title: 'Alertas',
              children: [
                SettingsRow(
                  icon: AppIcons.volumeHigh,
                  title: 'Sons de notificação',
                  trailing: SettingsSwitch(
                    value: value.sounds,
                    onChanged: enabled ? controller.setSounds : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
