import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'system_notifications_impl.dart';

class SystemNotification {
  const SystemNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
    required this.playSound,
    required this.isMention,
  });

  final int id;
  final String title;
  final String body;
  final String payload;
  final bool playSound;
  final bool isMention;
}

abstract interface class SystemNotificationPort {
  Stream<String> get selectedPayloads;

  Future<void> show(SystemNotification notification);

  void dispose();
}

final systemNotificationPortProvider = Provider<SystemNotificationPort>((ref) {
  final port = createSystemNotificationPort();
  ref.onDispose(port.dispose);
  return port;
});
