import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/theme/app_theme.dart';
import 'package:fourfun_cod_client/features/channels/channel_list.dart';
import 'package:fourfun_cod_client/features/channels/channels_providers.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';

class _FakeChannelsController extends ChannelsController {
  @override
  Future<List<ServerChannel>> build(String serverId) async => const [];
}

class _FakeServerDetailController extends ServerDetailController {
  @override
  Future<ServerDetail> build(String serverId) async => const ServerDetail(
    server: Server(id: 'server-1', name: 'Servidor de teste'),
    channels: [],
    members: [],
    myRole: ServerRole.owner,
  );
}

class _FakeVoicePresenceController extends VoicePresenceController {
  @override
  Map<String, Set<String>> build(String serverId) => const {};
}

void main() {
  setUpAll(() async {
    final geist = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'));
    await geist.load();
  });

  Future<void> pumpChannelList(
    WidgetTester tester, {
    required bool canManageServer,
    bool canLeaveServer = false,
    VoidCallback? onOpenSettings,
    VoidCallback? onLeaveServer,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          channelsControllerProvider.overrideWith(_FakeChannelsController.new),
          serverDetailProvider.overrideWith(_FakeServerDetailController.new),
          voicePresenceProvider.overrideWith(_FakeVoicePresenceController.new),
        ],
        child: MaterialApp(
          theme: theme4funCod,
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: ChannelList(
                serverId: 'server-1',
                canManageServer: canManageServer,
                canLeaveServer: canLeaveServer,
                onOpenSettings: onOpenSettings,
                onLeaveServer: onLeaveServer,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'oculta configurações do servidor para quem não pode administrá-lo',
    (tester) async {
      await pumpChannelList(tester, canManageServer: false);

      await tester.tap(find.byTooltip('Menu do servidor'));
      await tester.pumpAndSettle();

      expect(find.text('Membros e cargos'), findsOneWidget);
      expect(find.text('Configurações do servidor'), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    },
  );

  testWidgets(
    'exibe configurações do servidor e invoca a ação para administradores',
    (tester) async {
      var settingsOpened = false;
      await pumpChannelList(
        tester,
        canManageServer: true,
        onOpenSettings: () => settingsOpened = true,
      );

      await tester.tap(find.byTooltip('Menu do servidor'));
      await tester.pumpAndSettle();

      final settingsItem = find.text('Configurações do servidor');
      expect(settingsItem, findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

      await tester.tap(settingsItem);
      await tester.pumpAndSettle();

      expect(settingsOpened, isTrue);
    },
  );

  testWidgets('membro pode sair sem receber acesso às configurações', (
    tester,
  ) async {
    var leaveRequested = false;
    await pumpChannelList(
      tester,
      canManageServer: false,
      canLeaveServer: true,
      onLeaveServer: () => leaveRequested = true,
    );

    await tester.tap(find.byTooltip('Menu do servidor'));
    await tester.pumpAndSettle();

    expect(find.text('Configurações do servidor'), findsNothing);
    final leaveItem = find.text('Sair do servidor');
    expect(leaveItem, findsOneWidget);

    await tester.tap(leaveItem);
    await tester.pumpAndSettle();
    expect(leaveRequested, isTrue);
  });
}
