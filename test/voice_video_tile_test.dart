import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/theme/app_theme.dart';
import 'package:fourfun_cod_client/features/voice/voice_video_tile.dart';

class _FakeRtcService implements RtcService {
  @override
  String? get localParticipantId => 'user-1';

  @override
  RtcVideoTrackRef? videoTrackOf(String participantId) => null;

  @override
  RtcVideoTrackRef? screenTrackOf(String participantId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    required RtcParticipant participant,
    required VoiceVideoSource source,
    required VoiceVideoTileRole role,
    String? qualityLabel,
    VoidCallback? onExpand,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rtcServiceProvider.overrideWithValue(_FakeRtcService())],
        child: MaterialApp(
          theme: theme4funCod,
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: VoiceVideoTile(
                arg: (serverId: 'server-1', channelId: 'voice-1'),
                participant: participant,
                role: role,
                source: source,
                qualityLabel: qualityLabel,
                onExpand: onExpand,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const localScreen = RtcParticipant(
    id: 'user-1',
    name: 'SoulEater',
    isMicrophoneEnabled: true,
    isCameraEnabled: false,
    isScreenSharing: true,
    isSystemAudioEnabled: false,
    isSpeaking: false,
  );

  const remoteScreen = RtcParticipant(
    id: 'user-2',
    name: 'Remoto',
    isMicrophoneEnabled: true,
    isCameraEnabled: false,
    isScreenSharing: true,
    isSystemAudioEnabled: false,
    isSpeaking: false,
  );

  testWidgets('tile de tela local exibe LIVE + qualidade + expandir', (
    tester,
  ) async {
    var expanded = false;
    await pumpTile(
      tester,
      participant: localScreen,
      source: VoiceVideoSource.screen,
      role: VoiceVideoTileRole.grid,
      qualityLabel: '1080p60',
      onExpand: () => expanded = true,
    );

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('1080p60'), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen), findsOneWidget);
    // Nome dinâmico do transmissor continua no badge inferior.
    expect(find.text('SoulEater'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.fullscreen));
    expect(expanded, isTrue);
  });

  testWidgets('tile de tela remoto exibe só LIVE (qualidade desconhecida)', (
    tester,
  ) async {
    await pumpTile(
      tester,
      participant: remoteScreen,
      source: VoiceVideoSource.screen,
      role: VoiceVideoTileRole.grid,
      qualityLabel: '1080p60',
      onExpand: () {},
    );

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('1080p60'), findsNothing);
    expect(find.text('Remoto'), findsOneWidget);
  });

  testWidgets('tile de câmera não exibe overlay de transmissão', (
    tester,
  ) async {
    const camera = RtcParticipant(
      id: 'user-1',
      name: 'SoulEater',
      isMicrophoneEnabled: true,
      isCameraEnabled: true,
      isScreenSharing: false,
      isSystemAudioEnabled: false,
      isSpeaking: false,
    );
    await pumpTile(
      tester,
      participant: camera,
      source: VoiceVideoSource.camera,
      role: VoiceVideoTileRole.grid,
      qualityLabel: '1080p60',
      onExpand: () {},
    );

    expect(find.text('LIVE'), findsNothing);
    expect(find.byIcon(Icons.fullscreen), findsNothing);
  });

  testWidgets(
    'mostra placeholder visível quando o participante está sem vídeo',
    (tester) async {
      const participant = RtcParticipant(
        id: 'user-1',
        name: 'Rodrigo',
        isMicrophoneEnabled: true,
        isCameraEnabled: false,
        isScreenSharing: false,
        isSystemAudioEnabled: false,
        isSpeaking: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [rtcServiceProvider.overrideWithValue(_FakeRtcService())],
          child: MaterialApp(
            theme: theme4funCod,
            home: const Scaffold(
              body: SizedBox(
                width: 640,
                height: 360,
                child: VoiceVideoTile(
                  arg: (serverId: 'server-1', channelId: 'voice-1'),
                  participant: participant,
                  role: VoiceVideoTileRole.grid,
                  source: VoiceVideoSource.avatar,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Sem vídeo'), findsOneWidget);
      expect(find.text('Câmera desligada'), findsNothing);
      expect(find.text('R'), findsOneWidget);

      final placeholder = tester.widget<Container>(
        find.byKey(const ValueKey('voice-video-placeholder')),
      );
      final decoration = placeholder.decoration! as BoxDecoration;
      expect(decoration.color, AppTokens.surface1);
    },
  );
}
