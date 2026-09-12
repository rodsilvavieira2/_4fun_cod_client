import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../desktop/desktop_lifecycle.dart';

abstract interface class NotificationWindowPort {
  Future<bool> shouldShowSystemNotification();

  Future<void> restoreAndFocus();
}

class DesktopNotificationWindowPort implements NotificationWindowPort {
  const DesktopNotificationWindowPort();

  @override
  Future<bool> shouldShowSystemNotification() async {
    final visible = await windowManager.isVisible();
    if (!visible) return true;
    if (await windowManager.isMinimized()) return true;
    return !await windowManager.isFocused();
  }

  @override
  Future<void> restoreAndFocus() => restoreDesktopWindow();
}

final notificationWindowPortProvider = Provider<NotificationWindowPort>(
  (ref) => const DesktopNotificationWindowPort(),
);
