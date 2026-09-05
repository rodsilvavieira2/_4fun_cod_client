import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/auth/auth_controller.dart';
import 'package:fourfun_cod_client/core/auth/auth_state.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/features/servers/user_panel.dart';
import 'package:fourfun_cod_client/features/voice/voice_controls_provider.dart';
import 'package:fourfun_cod_client/features/voice/voice_providers.dart';
import 'package:fourfun_cod_client/shared/models/user.dart';

/// Fake do AuthController: nunca toca em backend/storage/dio.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this.initialState);

  final AuthState initialState;

  @override
  Future<AuthState> build() async => initialState;
}

class _FakeRtcService implements RtcService {
  int enableMicrophoneCalls = 0;
  int disableMicrophoneCalls = 0;
  final List<bool> remoteAudioSelections = [];

  @override
  Future<void> enableMicrophone() async => enableMicrophoneCalls++;

  @override
  Future<void> disableMicrophone() async => disableMicrophoneCalls++;

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) async {
    remoteAudioSelections.add(enabled);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  testWidgets(
    'UserPanel renderiza sem assert (color+decoration) com usuário autenticado',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      const user = User(
        id: 'user-1',
        name: 'Rodrigo',
        username: 'rodrigo',
        email: 'rodrigo@example.com',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(const Authenticated(user: user)),
            ),
            rtcServiceProvider.overrideWithValue(_FakeRtcService()),
          ],
          child: const MaterialApp(home: Scaffold(body: UserPanel())),
        ),
      );
      await tester.pumpAndSettle();

      // O container não pode lançar a assert do Flutter ("color is just a
      // shorthand for decoration") — a presença dos widgets confirma o
      // build sem ErrorWidget.
      expect(find.text('Rodrigo'), findsOneWidget);
      expect(find.text('Online'), findsOneWidget);
      // Fora de uma chamada os controles continuam funcionais e refletem a
      // preferência global padrão (microfone ativo, não ensurdecido).
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.byIcon(Icons.headset_outlined), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    },
  );

  testWidgets('UserPanel tolera usuário ausente (estado de bootstrap)', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(const AuthUnknown()),
          ),
          rtcServiceProvider.overrideWithValue(_FakeRtcService()),
        ],
        child: const MaterialApp(home: Scaffold(body: UserPanel())),
      ),
    );
    await tester.pumpAndSettle();

    // Bootstrap sem usuário: painel renderiza com placeholder (avatar +
    // nome usam '…') — o importante é não lançar e manter o ⚙️.
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.text('…'), findsNWidgets(2));
  });

  testWidgets('UserPanel alterna mute e ensurdecer fora de uma chamada', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final rtc = _FakeRtcService();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => _FakeAuthController(const AuthUnknown()),
        ),
        rtcServiceProvider.overrideWithValue(rtc),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: UserPanel())),
      ),
    );
    await tester.pumpAndSettle();
    await container.read(voiceControlsProvider.notifier).ensureInitialized();
    rtc.enableMicrophoneCalls = 0;
    rtc.disableMicrophoneCalls = 0;
    rtc.remoteAudioSelections.clear();

    await tester.tap(find.byTooltip('Desativar microfone'));
    await tester.pumpAndSettle();
    expect(container.read(voiceControlsProvider).isMuted, isTrue);
    expect(rtc.disableMicrophoneCalls, 1);

    await tester.tap(find.byTooltip('Ensurdecer'));
    await tester.pumpAndSettle();
    expect(container.read(voiceControlsProvider).isDeafened, isTrue);
    expect(rtc.disableMicrophoneCalls, 2);
    expect(rtc.remoteAudioSelections, [true, false]);
  });

  testWidgets(
    'UserPanel mostra compartilhar à direita do mic e o ping da voz',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [rtcServiceProvider.overrideWithValue(_FakeRtcService())],
          child: MaterialApp(
            home: Scaffold(
              body: UserPanel(
                voiceArg: (serverId: 'server-1', channelId: 'voice-1'),
                voiceChannelName: 'reunião',
                voiceState: const VoiceState(
                  status: VoiceSessionStatus.connected,
                  latencyMs: 42,
                ),
                onLeaveVoice: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voz conectada'), findsOneWidget);
      expect(find.text('reunião'), findsOneWidget);
      expect(find.text('42 ms'), findsOneWidget);
      expect(find.byIcon(Icons.present_to_all), findsOneWidget);
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(find.byIcon(Icons.headset_outlined), findsOneWidget);

      final micX = tester.getCenter(find.byIcon(Icons.mic_none)).dx;
      final shareX = tester.getCenter(find.byIcon(Icons.present_to_all)).dx;
      final headsetX = tester.getCenter(find.byIcon(Icons.headset_outlined)).dx;
      expect(micX, lessThan(shareX));
      expect(shareX, lessThan(headsetX));
    },
  );
}
