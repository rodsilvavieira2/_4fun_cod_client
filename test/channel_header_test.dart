import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/features/channels/channel_header.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';

void main() {
  Future<void> pumpHeader(WidgetTester tester, {VoidCallback? onOpenSettings}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChannelHeader(
            channelName: 'geral',
            channelType: ChannelType.text,
            onOpenSettings: onOpenSettings,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'oculta configurações do servidor quando a ação não está disponível',
    (tester) async {
      await pumpHeader(tester);

      expect(find.byTooltip('Configurações do servidor'), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    },
  );

  testWidgets('exibe configurações do servidor e invoca a ação fornecida', (
    tester,
  ) async {
    var settingsOpened = false;
    await pumpHeader(tester, onOpenSettings: () => settingsOpened = true);

    final settingsButton = find.byTooltip('Configurações do servidor');
    expect(settingsButton, findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    await tester.tap(settingsButton);
    await tester.pump();

    expect(settingsOpened, isTrue);
  });
}
