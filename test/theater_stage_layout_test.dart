import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/theme/app_theme.dart';
import 'package:fourfun_cod_client/features/voice/theater/theater_stage.dart';
import 'package:fourfun_cod_client/features/voice/theater/theater_ui_provider.dart';
import 'package:fourfun_cod_client/features/voice/voice_providers.dart';
import 'package:fourfun_cod_client/features/voice/voice_video_tile.dart';

class _FakeRtcService implements RtcService {
  @override
  String? get localParticipantId => 'u1';

  @override
  RtcVideoTrackRef? videoTrackOf(String participantId) => null;

  @override
  RtcVideoTrackRef? screenTrackOf(String participantId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// VoiceController com estado fixo: prova a matemática de layout do
/// [TheaterStage] real sem precisar dirigir o `join` (backend/LiveKit).
class _FixedVoiceController extends VoiceController {
  _FixedVoiceController(this._fixed);

  final VoiceState _fixed;

  @override
  VoiceState build(({String serverId, String channelId}) arg) => _fixed;
}

const _arg = (serverId: 's1', channelId: 'c1');

RtcParticipant _participant(
  String id,
  String name, {
  bool camera = false,
  bool screen = false,
}) => RtcParticipant(
  id: id,
  name: name,
  isMicrophoneEnabled: true,
  isCameraEnabled: camera,
  isScreenSharing: screen,
  isSystemAudioEnabled: false,
  isSpeaking: false,
);

void main() {
  group('TheaterStage focus', () {
    Future<ProviderContainer> pumpStage(
      WidgetTester tester, {
      required Size size,
      required List<RtcParticipant> participants,
    }) async {
      // A superfície default do teste é 800x600: fixa o tamanho lógico
      // para o stage receber as constraints reais (sem overflow).
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      late ProviderContainer container;
      final fixed = VoiceState(
        status: VoiceSessionStatus.connected,
        participants: participants,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rtcServiceProvider.overrideWithValue(_FakeRtcService()),
            voiceControllerProvider.overrideWith(
              () => _FixedVoiceController(fixed),
            ),
          ],
          child: MaterialApp(
            theme: theme4funCod,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  container = ProviderScope.containerOf(context);
                  return SizedBox(
                    width: size.width,
                    height: size.height,
                    child: TheaterStage(arg: _arg),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('tile único pinnado preenche 16:9 com gaps simétricos', (
      tester,
    ) async {
      // Janela larga e baixa (caso do screenshot do usuário).
      const stageSize = Size(1620, 850);
      final container = await pumpStage(
        tester,
        size: stageSize,
        participants: [
          _participant('u1', 'Soul', screen: true),
          _participant('u2', 'Luna', camera: true),
        ],
      );
      container
          .read(theaterUiControllerProvider(_arg).notifier)
          .togglePin('u1:screen');
      await tester.pump();

      expect(tester.takeException(), isNull);
      // 1 pinnado + 1 restante: foco com rail lateral proporcional.
      expect(find.byType(VoiceVideoTile), findsNWidgets(2));

      // Rail proporcional (~24% clamp 200–320) + gap entre colunas.
      // Tile único preenche o máximo 16:9 da área principal; a borda de
      // destaque (1.5px do tema) come 3px do vídeo por dentro.
      const border = 1.5;
      final railWidth = (stageSize.width * 0.24).clamp(200.0, 320.0);
      final mainW = stageSize.width - railWidth - kTheaterGap;
      const gridH = 850.0;
      final boxW = math.min(mainW, gridH * 16 / 9);
      final expectedW = boxW - border * 2;
      final expectedH = (boxW * 9 / 16) - border * 2;

      final tile = tester.getSize(find.byType(VoiceVideoTile).first);
      expect(tile.width, moreOrLessEquals(expectedW, epsilon: 2));
      expect(tile.height, moreOrLessEquals(expectedH, epsilon: 2));

      // Tile principal encosta na borda esquerda do stage (sem pad extra
      // interno): só a borda do tema + letterbox vertical centralizado.
      final tileLeft = tester.getTopLeft(find.byType(VoiceVideoTile).first).dx;
      expect(tileLeft, moreOrLessEquals(border, epsilon: 2));

      // Hierarquia: foco domina o rail.
      final railTile = tester.getSize(find.byType(VoiceVideoTile).at(1));
      expect(tile.width, greaterThan(railTile.width * 2));
    });

    testWidgets('sem pins usa grid com os dois tiles', (tester) async {
      const stageSize = Size(1620, 850);
      await pumpStage(
        tester,
        size: stageSize,
        participants: [
          _participant('u1', 'Soul', screen: true),
          _participant('u2', 'Luna', camera: true),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(VoiceVideoTile), findsNWidgets(2));
    });
  });
}
