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
    bool isWatching = true,
    VoidCallback? onTap,
    Size size = const Size(640, 360),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [rtcServiceProvider.overrideWithValue(_FakeRtcService())],
        child: MaterialApp(
          theme: theme4funCod,
          home: Scaffold(
            body: SizedBox(
              width: size.width,
              height: size.height,
              child: VoiceVideoTile(
                arg: (serverId: 'server-1', channelId: 'voice-1'),
                participant: participant,
                role: role,
                source: source,
                qualityLabel: qualityLabel,
                onExpand: onExpand,
                isWatching: isWatching,
                onTap: onTap,
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

  const remoteCamera = RtcParticipant(
    id: 'user-2',
    name: 'Remoto',
    isMicrophoneEnabled: true,
    isCameraEnabled: true,
    isScreenSharing: false,
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

  testWidgets('miniatura sem vídeo oculta badge e mantém nome', (tester) async {
    const participant = RtcParticipant(
      id: 'user-1',
      name: 'SoulEater',
      isMicrophoneEnabled: true,
      isCameraEnabled: false,
      isScreenSharing: false,
      isSystemAudioEnabled: false,
      isSpeaking: false,
    );

    await pumpTile(
      tester,
      participant: participant,
      source: VoiceVideoSource.avatar,
      role: VoiceVideoTileRole.miniature,
      size: const Size(192, 120),
    );

    expect(find.text('Sem vídeo'), findsNothing);
    expect(find.text('SoulEater'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
  });

  testWidgets('miniatura sem vídeo anima avatar enquanto fala', (tester) async {
    const participant = RtcParticipant(
      id: 'user-1',
      name: 'SoulEater',
      isMicrophoneEnabled: true,
      isCameraEnabled: false,
      isScreenSharing: false,
      isSystemAudioEnabled: false,
      isSpeaking: true,
    );

    await pumpTile(
      tester,
      participant: participant,
      source: VoiceVideoSource.avatar,
      role: VoiceVideoTileRole.miniature,
      size: const Size(192, 120),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Sem vídeo'), findsNothing);
    expect(
      find.byKey(const ValueKey('voice-speaking-avatar-pulse')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('participantes diferentes recebem gradientes base distintos', (
    tester,
  ) async {
    const first = RtcParticipant(
      id: 'user-1',
      name: 'SoulEater',
      isMicrophoneEnabled: true,
      isCameraEnabled: false,
      isScreenSharing: false,
      isSystemAudioEnabled: false,
      isSpeaking: false,
    );
    const second = RtcParticipant(
      id: 'user-2',
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
            body: Row(
              children: [
                SizedBox(
                  width: 192,
                  height: 120,
                  child: VoiceVideoTile(
                    arg: (serverId: 'server-1', channelId: 'voice-1'),
                    participant: first,
                    role: VoiceVideoTileRole.miniature,
                    source: VoiceVideoSource.avatar,
                  ),
                ),
                SizedBox(
                  width: 192,
                  height: 120,
                  child: VoiceVideoTile(
                    arg: (serverId: 'server-1', channelId: 'voice-1'),
                    participant: second,
                    role: VoiceVideoTileRole.miniature,
                    source: VoiceVideoSource.avatar,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final decorations = tester
        .widgetList<Container>(
          find.byKey(const ValueKey('voice-video-placeholder')),
        )
        .map((container) => container.decoration! as BoxDecoration)
        .toList();
    final firstGradient = decorations[0].gradient! as LinearGradient;
    final secondGradient = decorations[1].gradient! as LinearGradient;

    expect(firstGradient.colors.first, isNot(secondGradient.colors.first));
  });

  testWidgets('remoto não assistido exibe LIVE + Assistir (sem "Sem vídeo")', (
    tester,
  ) async {
    await pumpTile(
      tester,
      participant: remoteCamera,
      source: VoiceVideoSource.camera,
      role: VoiceVideoTileRole.grid,
      isWatching: false,
      onTap: () {},
    );

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Assistir'), findsOneWidget);
    expect(find.text('Sem vídeo'), findsNothing);
    expect(find.text('Remoto'), findsOneWidget);
  });

  testWidgets('botão Assistir dispara o onTap do tile', (tester) async {
    var tapped = 0;
    await pumpTile(
      tester,
      participant: remoteCamera,
      source: VoiceVideoSource.camera,
      role: VoiceVideoTileRole.grid,
      isWatching: false,
      onTap: () => tapped++,
    );

    await tester.tap(find.text('Assistir'));
    expect(tapped, 1);
  });

  testWidgets('miniatura não assistida não tem botão (toque assiste)', (
    tester,
  ) async {
    var tapped = 0;
    await pumpTile(
      tester,
      participant: remoteCamera,
      source: VoiceVideoSource.camera,
      role: VoiceVideoTileRole.miniature,
      isWatching: false,
      onTap: () => tapped++,
      size: const Size(192, 120),
    );

    expect(find.text('Assistir'), findsNothing);
    expect(find.text('Sem vídeo'), findsNothing);

    await tester.tap(find.text('Remoto'));
    expect(tapped, 1);
  });

  testWidgets('avatar com isWatching=false continua "Sem vídeo"', (
    tester,
  ) async {
    const participant = RtcParticipant(
      id: 'user-2',
      name: 'Remoto',
      isMicrophoneEnabled: true,
      isCameraEnabled: false,
      isScreenSharing: false,
      isSystemAudioEnabled: false,
      isSpeaking: false,
    );
    await pumpTile(
      tester,
      participant: participant,
      source: VoiceVideoSource.avatar,
      role: VoiceVideoTileRole.grid,
      isWatching: false,
    );

    expect(find.text('Sem vídeo'), findsOneWidget);
    expect(find.text('Assistir'), findsNothing);
    expect(find.text('LIVE'), findsNothing);
  });
}
