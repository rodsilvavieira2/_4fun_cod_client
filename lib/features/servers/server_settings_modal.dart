import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/ui.dart';
import 'server_settings_screen.dart';

enum _ServerSettingsResult { openMembers, serverExited }

/// Opens server administration in a modal that is separate from personal
/// account settings.
Future<void> showServerSettingsModal(
  BuildContext context, {
  required String serverId,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final result = await showMacModalWindow<_ServerSettingsResult>(
    context: context,
    title: 'Configurações do servidor',
    maxWidth: 600,
    maxHeight: 620,
    child: ServerSettingsContent(
      serverId: serverId,
      onOpenMembers: () => navigator.pop(_ServerSettingsResult.openMembers),
      onServerExited: () => navigator.pop(_ServerSettingsResult.serverExited),
    ),
  );

  if (!context.mounted) return;
  switch (result) {
    case _ServerSettingsResult.openMembers:
      await context.push('/servers/$serverId/members');
      break;
    case _ServerSettingsResult.serverExited:
      context.go('/');
      break;
    case null:
      break;
  }
}
