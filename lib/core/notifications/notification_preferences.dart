import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const notificationChannelMessagesKey = 'notifications.channelMessages';
const notificationMentionsKey = 'notifications.mentions';
const notificationSoundsKey = 'notifications.sounds';

class NotificationPreferences {
  const NotificationPreferences({
    required this.channelMessages,
    required this.mentions,
    required this.sounds,
  });

  static const defaults = NotificationPreferences(
    channelMessages: true,
    mentions: true,
    sounds: false,
  );

  final bool channelMessages;
  final bool mentions;
  final bool sounds;

  NotificationPreferences copyWith({
    bool? channelMessages,
    bool? mentions,
    bool? sounds,
  }) {
    return NotificationPreferences(
      channelMessages: channelMessages ?? this.channelMessages,
      mentions: mentions ?? this.mentions,
      sounds: sounds ?? this.sounds,
    );
  }
}

class NotificationPreferencesController
    extends AsyncNotifier<NotificationPreferences> {
  SharedPreferences? _preferences;

  @override
  Future<NotificationPreferences> build() async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    return NotificationPreferences(
      channelMessages:
          preferences.getBool(notificationChannelMessagesKey) ??
          NotificationPreferences.defaults.channelMessages,
      mentions:
          preferences.getBool(notificationMentionsKey) ??
          NotificationPreferences.defaults.mentions,
      sounds:
          preferences.getBool(notificationSoundsKey) ??
          NotificationPreferences.defaults.sounds,
    );
  }

  Future<void> setChannelMessages(bool value) =>
      _save((current) => current.copyWith(channelMessages: value));

  Future<void> setMentions(bool value) =>
      _save((current) => current.copyWith(mentions: value));

  Future<void> setSounds(bool value) =>
      _save((current) => current.copyWith(sounds: value));

  Future<void> _save(
    NotificationPreferences Function(NotificationPreferences current) update,
  ) async {
    final current = state.valueOrNull ?? await future;
    final next = update(current);
    state = AsyncData(next);
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setBool(notificationChannelMessagesKey, next.channelMessages),
      preferences.setBool(notificationMentionsKey, next.mentions),
      preferences.setBool(notificationSoundsKey, next.sounds),
    ]);
  }
}

final notificationPreferencesProvider =
    AsyncNotifierProvider<
      NotificationPreferencesController,
      NotificationPreferences
    >(NotificationPreferencesController.new);
