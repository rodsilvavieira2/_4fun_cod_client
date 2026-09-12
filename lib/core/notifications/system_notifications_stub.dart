import 'system_notifications.dart';

SystemNotificationPort createSystemNotificationPort() =>
    const _NoopSystemNotificationPort();

class _NoopSystemNotificationPort implements SystemNotificationPort {
  const _NoopSystemNotificationPort();

  @override
  Stream<String> get selectedPayloads => const Stream.empty();

  @override
  Future<void> show(SystemNotification notification) async {}

  @override
  void dispose() {}
}
