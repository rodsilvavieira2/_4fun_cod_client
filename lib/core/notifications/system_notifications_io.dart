import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'system_notifications.dart';

const _windowsAppName = '4FunCode';
const _windowsAumid = 'com.example.u_4fun_cod_client';
const _windowsGuid = '42c85c9e-1fb0-4b84-ae3d-0cc3aa93f9c2';

SystemNotificationPort createSystemNotificationPort() =>
    _FlutterSystemNotificationPort();

class _FlutterSystemNotificationPort implements SystemNotificationPort {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _selectedPayloads =
      StreamController<String>.broadcast();

  Future<void>? _initialization;

  @override
  Stream<String> get selectedPayloads => _selectedPayloads.stream;

  @override
  Future<void> show(SystemNotification notification) async {
    if (!Platform.isLinux && !Platform.isWindows) return;
    await (_initialization ??= _initialize());

    final details = NotificationDetails(
      linux: LinuxNotificationDetails(
        urgency: notification.isMention
            ? LinuxNotificationUrgency.critical
            : LinuxNotificationUrgency.normal,
        suppressSound: !notification.playSound,
      ),
      windows: WindowsNotificationDetails(
        audio: notification.playSound
            ? null
            : WindowsNotificationAudio.silent(),
      ),
    );
    await _plugin.show(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      notificationDetails: details,
      payload: notification.payload,
    );
  }

  Future<void> _initialize() {
    final settings = InitializationSettings(
      linux: LinuxInitializationSettings(
        defaultActionName: 'Abrir 4FunCode',
        defaultIcon: AssetsLinuxIcon('web/favicon.png'),
      ),
      windows: const WindowsInitializationSettings(
        appName: _windowsAppName,
        appUserModelId: _windowsAumid,
        guid: _windowsGuid,
      ),
    );
    return _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        _selectedPayloads.add(payload);
      },
    );
  }

  @override
  void dispose() {
    _selectedPayloads.close();
  }
}
