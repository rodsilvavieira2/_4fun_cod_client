import 'package:flutter/material.dart';
import 'package:fourfun_cod_client/core/ui/app_icon.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/theme/app_theme.dart';
import 'package:fourfun_cod_client/features/channels/channel_list.dart';
import 'package:fourfun_cod_client/features/channels/channels_providers.dart';
import 'package:fourfun_cod_client/features/servers/servers_providers.dart';
import 'package:fourfun_cod_client/shared/models/servers.dart';
import 'package:fourfun_cod_client/shared/models/user.dart';

class _FakeChannelsController extends ChannelsController {
  @override
  Future<List<ServerChannel>> build(String serverId) async => _channels;
}

class _FakeServerDetailController extends ServerDetailController {
  @override
  Future<ServerDetail> build(String serverId) async => _detail;
}

class _FakeVoicePresenceController extends VoicePresenceController {
  @override
  Map<String, Set<String>> build(String serverId) => _voicePresence;
}

class _FakeRtcService implements RtcService {
  _FakeRtcService({this.localId});

  final String? localId;
  final Map<String, double> participantGains = {};

  @override
  String? get localParticipantId => localId;

  @override
  Future<void> setInputVolume(double gain) async {}

  @override
  Future<void> setOutputVolume(double gain) async {}

  @override
  Future<void> setParticipantVolume(String identity, double gain) async {
    participantGains[identity] = gain;
  }

  @override
  Future<void> setParticipantSourceVolume(
    String identity,
    RtcAudioSource source,
    double gain,
  ) async {
    participantGains['$identity#${source.name}'] = gain;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<ServerChannel> _channels = const [];
ServerDetail _detail = const ServerDetail(
  server: Server(id: 'server-1', name: 'Servidor de teste'),
  channels: [],
  members: [],
  myRole: ServerRole.owner,
);
Map<String, Set<String>> _voicePresence = const {};

void main() {
  setUpAll(() async {
    final geist = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'));
    await geist.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _channels = const [];
    _detail = const ServerDetail(
      server: Server(id: 'server-1', name: 'Servidor de teste'),
      channels: [],
      members: [],
      myRole: ServerRole.owner,
    );
    _voicePresence = const {};
  });

  Future<void> pumpChannelList(
    WidgetTester tester, {
    required bool canManageServer,
    bool canLeaveServer = false,
    String? activeVoiceChannelId,
    List<RtcParticipant> activeVoiceParticipants = const [],
    String? localParticipantId,
    VoidCallback? onOpenSettings,
    VoidCallback? onLeaveServer,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          channelsControllerProvider.overrideWith(_FakeChannelsController.new),
          serverDetailProvider.overrideWith(_FakeServerDetailController.new),
          voicePresenceProvider.overrideWith(_FakeVoicePresenceController.new),
          rtcServiceProvider.overrideWithValue(
            _FakeRtcService(localId: localParticipantId),
          ),
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
                activeVoiceChannelId: activeVoiceChannelId,
                activeVoiceParticipants: activeVoiceParticipants,
                onOpenSettings: onOpenSettings,
                onLeaveServer: onLeaveServer,
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'oculta configurações do servidor para quem não pode administrá-lo',
    (tester) async {
      await pumpChannelList(tester, canManageServer: false);

      await tester.tap(find.byTooltip('Menu do servidor'));
      await tester.pumpAndSettle();

      expect(find.text('Membros e cargos'), findsOneWidget);
      expect(find.text('Configurações do servidor'), findsNothing);
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == AppIcons.settings), findsNothing);
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
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.icon == AppIcons.settings), findsOneWidget);

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

  testWidgets('clique direito no ocupante remoto abre volume do usuário', (
    tester,
  ) async {
    _channels = const [
      ServerChannel(id: 'voice-1', name: 'Música', type: ChannelType.voice),
    ];
    _detail = ServerDetail(
      server: const Server(id: 'server-1', name: 'Servidor de teste'),
      channels: _channels,
      members: [
        ServerMember(
          id: 'member-2',
          userId: 'remote-2',
          role: ServerRole.member,
          joinedAt: DateTime.fromMillisecondsSinceEpoch(0),
          user: const User(id: 'remote-2', name: 'Dione', username: 'Dione'),
        ),
      ],
      myRole: ServerRole.owner,
    );
    _voicePresence = const {
      'voice-1': {'remote-2'},
    };

    await pumpChannelList(
      tester,
      canManageServer: true,
      activeVoiceChannelId: 'voice-1',
      activeVoiceParticipants: const [
        RtcParticipant(
          id: 'user_remote-2',
          name: 'Dione',
          isMicrophoneEnabled: true,
          isCameraEnabled: false,
          isScreenSharing: false,
          isSystemAudioEnabled: false,
          isSpeaking: false,
        ),
      ],
      localParticipantId: 'user-local',
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Dione')),
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Volume do usuário'), findsOneWidget);
    expect(find.text('Silenciar para mim'), findsOneWidget);

    await tester.tap(find.text('Silenciar para mim'));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(checkbox.value, isTrue);
  });

  testWidgets('ocupante de voz mostra medidor enquanto está falando', (
    tester,
  ) async {
    _channels = const [
      ServerChannel(id: 'voice-1', name: 'chat', type: ChannelType.voice),
    ];
    _detail = ServerDetail(
      server: const Server(id: 'server-1', name: 'Servidor de teste'),
      channels: _channels,
      members: [
        ServerMember(
          id: 'member-1',
          userId: 'soul',
          role: ServerRole.member,
          joinedAt: DateTime.fromMillisecondsSinceEpoch(0),
          user: const User(
            id: 'soul',
            name: 'SoulEater',
            username: 'SoulEater',
          ),
        ),
      ],
      myRole: ServerRole.owner,
    );
    _voicePresence = const {
      'voice-1': {'soul'},
    };

    await pumpChannelList(
      tester,
      canManageServer: true,
      activeVoiceChannelId: 'voice-1',
      activeVoiceParticipants: const [
        RtcParticipant(
          id: 'user_soul',
          name: 'SoulEater',
          isMicrophoneEnabled: true,
          isCameraEnabled: false,
          isScreenSharing: false,
          isSystemAudioEnabled: false,
          isSpeaking: true,
        ),
      ],
      localParticipantId: 'user-local',
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('SoulEater'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('voice-occupant-speaking-meter')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
