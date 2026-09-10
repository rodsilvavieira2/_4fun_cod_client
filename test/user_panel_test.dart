import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/theme/app_theme.dart';

import 'package:fourfun_cod_client/core/auth/auth_controller.dart';
import 'package:fourfun_cod_client/core/auth/auth_state.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/ui/settings_sections/voice_video_section.dart';
import 'package:fourfun_cod_client/features/servers/user_panel.dart';
import 'package:fourfun_cod_client/features/voice/voice_audio_processing_provider.dart';
import 'package:fourfun_cod_client/features/voice/voice_controls_provider.dart';
import 'package:fourfun_cod_client/features/voice/voice_providers.dart';
import 'package:fourfun_cod_client/features/voice/voice_volume_controller.dart';
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
  double inputGain = 1.0;
  double outputGain = 1.0;
  bool noiseSuppressionEnabled = true;
  final List<bool> remoteAudioSelections = [];
  List<RtcAudioDevice> inputs = const [
    RtcAudioDevice(
      id: 'mic-1',
      label: 'Microfone USB',
      kind: RtcMediaDeviceKind.audioInput,
    ),
  ];
  List<RtcAudioDevice> outputs = const [
    RtcAudioDevice(
      id: 'out-1',
      label: 'Fone USB',
      kind: RtcMediaDeviceKind.audioOutput,
    ),
  ];

  @override
  Future<void> enableMicrophone() async => enableMicrophoneCalls++;

  @override
  Future<void> disableMicrophone() async => disableMicrophoneCalls++;

  @override
  Future<void> setRemoteAudioEnabled(bool enabled) async {
    remoteAudioSelections.add(enabled);
  }

  @override
  Future<List<RtcAudioDevice>> listAudioInputDevices() async => inputs;

  @override
  Future<List<RtcAudioDevice>> listAudioOutputDevices() async => outputs;

  @override
  Future<List<RtcVideoDevice>> listCameraDevices() async => const [];

  @override
  Stream<void> get mediaDevicesChanged => const Stream.empty();

  @override
  Future<void> selectAudioInput(String? deviceId) async {}

  @override
  Future<void> selectAudioOutput(String? deviceId) async {}

  @override
  Future<void> setInputVolume(double gain) async => inputGain = gain;

  @override
  Future<void> setOutputVolume(double gain) async => outputGain = gain;

  @override
  Future<void> setNoiseSuppressionEnabled(bool enabled) async {
    noiseSuppressionEnabled = enabled;
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
        name: 'Rodrigo Silva',
        username: 'rodrigo_nick',
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
      expect(find.text('rodrigo_nick'), findsOneWidget);
      expect(find.text('Rodrigo Silva'), findsNothing);
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

  testWidgets('menu do microfone exibe e aplica volume de entrada', (
    tester,
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
        child: MaterialApp(
          theme: theme4funCod,
          home: const Scaffold(body: UserPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Dispositivo de entrada'));
    await tester.pumpAndSettle();

    expect(find.text('Volume de entrada'), findsOneWidget);

    await tester.tap(find.text('Dispositivo de entrada').last);
    await tester.pumpAndSettle();

    expect(find.text('Microfone USB'), findsOneWidget);

    tester.widget<Slider>(find.byType(Slider)).onChanged?.call(50);
    await tester.pumpAndSettle();

    expect(container.read(voiceVolumeProvider).inputPercent, 50);
    expect(rtc.inputGain, 0.5);
  });

  testWidgets('Voz e Vídeo exibe e aplica supressão de ruído', (tester) async {
    SharedPreferences.setMockInitialValues({
      VoiceAudioProcessingController.noiseSuppressionKey: false,
    });
    final rtc = _FakeRtcService();
    final container = ProviderContainer(
      overrides: [rtcServiceProvider.overrideWithValue(rtc)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme4funCod,
          home: const Scaffold(
            body: SingleChildScrollView(child: VoiceVideoSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Supressão de ruído'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);

    tester.widget<Switch>(find.byType(Switch).first).onChanged?.call(true);
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(rtc.noiseSuppressionEnabled, isTrue);
    expect(
      container.read(voiceAudioProcessingProvider).isNoiseSuppressionEnabled,
      isTrue,
    );
    expect(
      preferences.getBool(VoiceAudioProcessingController.noiseSuppressionKey),
      isTrue,
    );
  });

  testWidgets('UserPanel organiza ações de voz acima dos controles pessoais', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(256, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    expect(find.text('42 ms'), findsNothing);
    expect(find.byIcon(Icons.wifi_rounded), findsOneWidget);
    expect(find.byTooltip('Latência da conexão: 42 ms'), findsOneWidget);
    expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.present_to_all), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.byIcon(Icons.headset_outlined), findsOneWidget);

    final cameraY = tester
        .getCenter(find.byIcon(Icons.videocam_off_outlined))
        .dy;
    final shareY = tester.getCenter(find.byIcon(Icons.present_to_all)).dy;
    final micX = tester.getCenter(find.byIcon(Icons.mic_none)).dx;
    final micY = tester.getCenter(find.byIcon(Icons.mic_none)).dy;
    final headsetX = tester.getCenter(find.byIcon(Icons.headset_outlined)).dx;
    final headsetY = tester.getCenter(find.byIcon(Icons.headset_outlined)).dy;
    expect(cameraY, lessThan(micY));
    expect(shareY, lessThan(headsetY));
    expect(micX, lessThan(headsetX));
  });

  testWidgets('UserPanel flutuante aplica sombra e raio maior no card', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    BoxDecoration cardOf() {
      return tester
              .widget<Container>(find.byKey(const Key('user-panel-card')))
              .decoration!
          as BoxDecoration;
    }

    Future<void> pumpPanel({required bool floating}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [rtcServiceProvider.overrideWithValue(_FakeRtcService())],
          child: MaterialApp(
            home: Scaffold(body: UserPanel(floating: floating)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpPanel(floating: false);
    expect(cardOf().boxShadow, isNull);

    await pumpPanel(floating: true);
    expect(cardOf().boxShadow, isNotNull);
  });

  testWidgets('Botões câmera/share mostram cursor click na área cheia', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rtcServiceProvider.overrideWithValue(_FakeRtcService())],
        child: MaterialApp(
          theme: theme4funCod,
          home: Scaffold(
            body: UserPanel(
              voiceArg: (serverId: 'server-1', channelId: 'voice-1'),
              voiceChannelName: 'reunião',
              voiceState: const VoiceState(
                status: VoiceSessionStatus.connected,
              ),
              onLeaveVoice: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cameraIcon = find.byIcon(Icons.videocam_off_outlined);
    expect(cameraIcon, findsOneWidget);
    // Caixa do IconButton (34px de altura, largura cheia).
    final buttonBox = tester.getRect(
      find.ancestor(
        of: cameraIcon,
        matching: find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == 34,
        ),
      ),
    );
    expect(buttonBox.height, 34);

    // Cursor ativo do dispositivo de mouse (id 1 por padrão nos testes).
    MouseCursor? cursorOf(int device) =>
        tester.binding.mouseTracker.debugDeviceActiveCursor(device);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await tester.pump();

    // Canto do botão, fora do glifo: o tema força click (o padrão do
    // framework no desktop seria seta via adaptiveClickable).
    await mouse.moveTo(buttonBox.topLeft + const Offset(2, 17));
    await tester.pump();
    expect(cursorOf(1), SystemMouseCursors.click);

    // Centro do glifo também.
    await mouse.moveTo(tester.getCenter(cameraIcon));
    await tester.pump();
    expect(cursorOf(1), SystemMouseCursors.click);
  });
}
