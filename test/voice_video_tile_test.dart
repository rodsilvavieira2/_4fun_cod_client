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
