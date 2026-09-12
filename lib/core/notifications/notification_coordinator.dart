import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_state.dart';
import '../router/app_router.dart';
import '../websocket/realtime_event.dart';
import '../websocket/socket_service.dart';
import 'notification_preferences.dart';
import 'notification_window.dart';
import 'system_notifications.dart';

typedef NotificationPreferencesReader =
    Future<NotificationPreferences> Function();
typedef CurrentUserIdReader = String? Function();
typedef NotificationNavigator =
    Future<void> Function(String serverId, String channelId);

class NotificationCoordinator {
  NotificationCoordinator({
    required this.events,
    required this.selectedPayloads,
    required this.notifications,
    required this.readPreferences,
    required this.readCurrentUserId,
    required this.shouldShowSystemNotification,
    required this.openChannel,
  });

  final Stream<RealtimeEvent> events;
  final Stream<String> selectedPayloads;
  final SystemNotificationPort notifications;
  final NotificationPreferencesReader readPreferences;
  final CurrentUserIdReader readCurrentUserId;
  final Future<bool> Function() shouldShowSystemNotification;
  final NotificationNavigator openChannel;

  final Set<String> _seenMessageIds = {};
  final Queue<String> _seenMessageOrder = Queue<String>();

  StreamSubscription<RealtimeEvent>? _eventsSub;
  StreamSubscription<String>? _payloadSub;
  int _nextNotificationId = 1;

  void start() {
    _eventsSub ??= events.listen((event) {
      if (event is NotificationMessageCreatedEvent) {
        unawaited(_handleMessageCreated(event));
      }
    });
    _payloadSub ??= selectedPayloads.listen((payload) {
      unawaited(_handleSelectedPayload(payload));
    });
  }

  Future<void> _handleMessageCreated(
    NotificationMessageCreatedEvent event,
  ) async {
    if (event.author.id == readCurrentUserId()) return;
    if (!_markSeen(event.messageId)) return;

    final preferences = await readPreferences();
    if (event.type == NotificationMessageType.mention) {
      if (!preferences.mentions) return;
    } else if (!preferences.channelMessages) {
      return;
    }
    if (!await shouldShowSystemNotification()) return;

    await notifications.show(
      SystemNotification(
        id: _nextNotificationId++,
        title: _titleFor(event),
        body: _bodyFor(event),
        payload: _payloadFor(event),
        playSound: preferences.sounds,
        isMention: event.type == NotificationMessageType.mention,
      ),
    );
  }

  bool _markSeen(String messageId) {
    if (_seenMessageIds.contains(messageId)) return false;
    _seenMessageIds.add(messageId);
    _seenMessageOrder.addLast(messageId);
    while (_seenMessageOrder.length > 200) {
      _seenMessageIds.remove(_seenMessageOrder.removeFirst());
    }
    return true;
  }

  String _titleFor(NotificationMessageCreatedEvent event) {
    final channelName = event.channelName.isEmpty ? 'canal' : event.channelName;
    if (event.type == NotificationMessageType.mention) {
      return '${event.author.name} mencionou você em #$channelName';
    }
    final serverName = event.serverName.isEmpty ? '4FunCode' : event.serverName;
    return '#$channelName em $serverName';
  }

  String _bodyFor(NotificationMessageCreatedEvent event) {
    final preview = event.preview.trim().isEmpty ? 'GIF' : event.preview.trim();
    return '${event.author.name}: $preview';
  }

  String _payloadFor(NotificationMessageCreatedEvent event) {
    return jsonEncode({
      'serverId': event.serverId,
      'channelId': event.channelId,
    });
  }

  Future<void> _handleSelectedPayload(String payload) async {
    try {
      final json = jsonDecode(payload);
      if (json is! Map<String, dynamic>) return;
      final serverId = json['serverId'];
      final channelId = json['channelId'];
      if (serverId is! String || channelId is! String) return;
      await openChannel(serverId, channelId);
    } catch (_) {
      // Payload antigo/malformado: ignora.
    }
  }

  void dispose() {
    unawaited(_eventsSub?.cancel());
    unawaited(_payloadSub?.cancel());
  }
}

final notificationCoordinatorProvider = Provider<NotificationCoordinator>((
  ref,
) {
  final notifications = ref.watch(systemNotificationPortProvider);
  final window = ref.watch(notificationWindowPortProvider);
  final socket = ref.watch(socketServiceProvider);
  final router = ref.watch(routerProvider);

  final coordinator = NotificationCoordinator(
    events: socket.events,
    selectedPayloads: notifications.selectedPayloads,
    notifications: notifications,
    readPreferences: () => ref.read(notificationPreferencesProvider.future),
    readCurrentUserId: () {
      final auth = ref.read(authControllerProvider).valueOrNull;
      return auth is Authenticated ? auth.user.id : null;
    },
    shouldShowSystemNotification: window.shouldShowSystemNotification,
    openChannel: (serverId, channelId) async {
      await window.restoreAndFocus();
      _goToChannel(router, serverId, channelId);
    },
  );
  coordinator.start();
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

void _goToChannel(GoRouter router, String serverId, String channelId) {
  router.go(
    Uri(
      path: '/servers/$serverId',
      queryParameters: {'channelId': channelId},
    ).toString(),
  );
}
