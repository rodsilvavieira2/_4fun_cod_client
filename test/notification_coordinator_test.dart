import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/notifications/notification_coordinator.dart';
import 'package:fourfun_cod_client/core/notifications/notification_preferences.dart';
import 'package:fourfun_cod_client/core/notifications/system_notifications.dart';
import 'package:fourfun_cod_client/core/websocket/realtime_event.dart';
import 'package:fourfun_cod_client/shared/models/message.dart';
import 'package:fourfun_cod_client/shared/models/user.dart';

class _FakeSystemNotificationPort implements SystemNotificationPort {
  final StreamController<String> selectedController =
      StreamController<String>.broadcast();
  final List<SystemNotification> shown = [];

  @override
  Stream<String> get selectedPayloads => selectedController.stream;

  @override
  Future<void> show(SystemNotification notification) async {
    shown.add(notification);
  }

  @override
  void dispose() {
    selectedController.close();
  }
}

const _author = User(id: 'u2', name: 'Bia', username: 'bia');

NotificationMessageCreatedEvent _event({
  String messageId = 'm1',
  NotificationMessageType type = NotificationMessageType.channelMessage,
  String authorId = 'u2',
}) => NotificationMessageCreatedEvent(
  type: type,
  serverId: 's1',
  serverName: 'Servidor',
  channelId: 'c1',
  channelName: 'geral',
  messageId: messageId,
  author: User(id: authorId, name: 'Bia', username: 'bia'),
  kind: ChatMessageKind.text,
  preview: 'olá',
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  late StreamController<RealtimeEvent> events;
  late _FakeSystemNotificationPort notifications;
  late NotificationPreferences preferences;
  late bool shouldShow;
  late List<({String serverId, String channelId})> opened;
  late NotificationCoordinator coordinator;

  setUp(() {
    events = StreamController<RealtimeEvent>.broadcast();
    notifications = _FakeSystemNotificationPort();
    preferences = NotificationPreferences.defaults;
    shouldShow = true;
    opened = [];
    coordinator = NotificationCoordinator(
      events: events.stream,
      selectedPayloads: notifications.selectedPayloads,
      notifications: notifications,
      readPreferences: () async => preferences,
      readCurrentUserId: () => 'u1',
      shouldShowSystemNotification: () async => shouldShow,
      openChannel: (serverId, channelId) async {
        opened.add((serverId: serverId, channelId: channelId));
      },
    )..start();
  });

  tearDown(() async {
    coordinator.dispose();
    notifications.dispose();
    await events.close();
  });

  test('não notifica mensagem própria nem janela em foco', () async {
    events.add(_event(authorId: 'u1'));
    await pumpEventQueue();
    expect(notifications.shown, isEmpty);

    shouldShow = false;
    events.add(_event(messageId: 'm2'));
    await pumpEventQueue();
    expect(notifications.shown, isEmpty);
  });

  test(
    'mostra notificação de canal fora de foco e deduplica mensagem',
    () async {
      events.add(_event());
      await pumpEventQueue();
      events.add(_event());
      await pumpEventQueue();

      expect(notifications.shown, hasLength(1));
      expect(notifications.shown.single.title, '#geral em Servidor');
      expect(notifications.shown.single.body, '${_author.name}: olá');
      expect(notifications.shown.single.playSound, isFalse);
    },
  );

  test('respeita preferência de menções', () async {
    preferences = const NotificationPreferences(
      channelMessages: true,
      mentions: false,
      sounds: true,
    );

    events.add(_event(type: NotificationMessageType.mention));
    await pumpEventQueue();

    expect(notifications.shown, isEmpty);
  });

  test('payload selecionado abre servidor e canal', () async {
    notifications.selectedController.add(
      jsonEncode({'serverId': 's1', 'channelId': 'c1'}),
    );
    await pumpEventQueue();

    expect(opened, [(serverId: 's1', channelId: 'c1')]);
  });
}
