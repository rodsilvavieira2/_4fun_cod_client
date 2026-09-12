import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/notifications/notification_preferences.dart';
import 'package:fourfun_cod_client/core/ui/settings_sections/notifications_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('carrega defaults e persiste alterações locais', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(notificationPreferencesProvider, (_, _) {});
    addTearDown(sub.close);

    final preferences = await container.read(
      notificationPreferencesProvider.future,
    );

    expect(preferences.channelMessages, isTrue);
    expect(preferences.mentions, isTrue);
    expect(preferences.sounds, isFalse);

    await container
        .read(notificationPreferencesProvider.notifier)
        .setChannelMessages(false);
    await container
        .read(notificationPreferencesProvider.notifier)
        .setSounds(true);

    final stored = await SharedPreferences.getInstance();
    expect(stored.getBool(notificationChannelMessagesKey), isFalse);
    expect(stored.getBool(notificationMentionsKey), isTrue);
    expect(stored.getBool(notificationSoundsKey), isTrue);
  });

  testWidgets('seção de notificações reflete e salva os switches', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: NotificationsSection())),
      ),
    );
    await tester.pumpAndSettle();

    var switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.map((item) => item.value), [true, true, false]);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches.map((item) => item.value), [false, true, false]);

    final stored = await SharedPreferences.getInstance();
    expect(stored.getBool(notificationChannelMessagesKey), isFalse);
  });
}
