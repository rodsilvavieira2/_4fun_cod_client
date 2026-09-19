import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_providers.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/theme/app_theme.dart';
import 'package:fourfun_cod_client/features/voice/theater/theater_empty_illustration.dart';
import 'package:fourfun_cod_client/features/voice/theater/theater_stage.dart';
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

/// VoiceController com estado fixo: prova o empty state do [TheaterStage]
/// real sem precisar dirigir o `join` (backend/LiveKit).
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
  group('recolorUndrawSvg', () {
    test('troca só o primário undraw pelo accent (outras cores intactas)', () {
      const raw =
          '<svg><path fill="#6C63FF"/><path fill="#ed9da0"/>'
          '<rect fill="#f2f2f2"/></svg>';
      final out = recolorUndrawSvg(raw, '#A78BFA');

      expect(out.contains(RegExp('6c63ff', caseSensitive: false)), isFalse);
      expect(out.contains('#A78BFA'), isTrue);
      // Pele e brancos preservados.
      expect(out.contains('#ed9da0'), isTrue);
      expect(out.contains('#f2f2f2'), isTrue);
    });

    test('aceita accent sem #', () {
      const raw = '<svg><path fill="#6c63ff"/></svg>';
      expect(recolorUndrawSvg(raw, '5865F2'), contains('#5865F2'));
    });
  });

  group('TheaterEmptyStage', () {
    Future<void> pumpEmpty(
      WidgetTester tester, {
      ThemeData? theme,
      VoidCallback? onShareScreen,
      List<RtcParticipant> participants = const [],
    }) async {
      const stageSize = Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = stageSize;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
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
            theme: theme ?? theme4funCod,
            home: Scaffold(
              body: SizedBox(
                width: stageSize.width,
                height: stageSize.height,
                child: TheaterStage(arg: _arg, onShareScreen: onShareScreen),
              ),
            ),
          ),
        ),
      );
      // FutureBuilder do SVG (rootBundle) resolve aqui.
      await tester.pumpAndSettle();
    }

    testWidgets('mostra título, subtítulo, ilustração e CTAs', (tester) async {
      await pumpEmpty(tester, onShareScreen: () {});

      expect(tester.takeException(), isNull);
      expect(find.text('Nenhuma transmissão ativa'), findsOneWidget);
      expect(
        find.text('Inicie sua câmera ou compartilhe sua tela para começar'),
        findsOneWidget,
      );
      expect(find.byType(TheaterEmptyIllustration), findsOneWidget);
      expect(find.byType(SvgPicture), findsWidgets);
      // O fundo temático fica atrás do card mesmo sem transmissão.
      expect(find.byType(TheaterStageBackdrop), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Iniciar câmera'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Compartilhar tela'),
        findsOneWidget,
      );
      expect(find.text('Saiba como funciona'), findsOneWidget);
    });

    testWidgets('CTA compartilhar chama onShareScreen', (tester) async {
      var shared = false;
      await pumpEmpty(tester, onShareScreen: () => shared = true);

      await tester.tap(find.text('Compartilhar tela'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(shared, isTrue);
    });

    testWidgets('CTA câmera não derruba a sessão', (tester) async {
      await pumpEmpty(tester, onShareScreen: () {});

      await tester.tap(find.text('Iniciar câmera'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Nenhuma transmissão ativa'), findsOneWidget);
    });

    testWidgets('acompanha o accent de vários presets', (tester) async {
      // Foto de referência é roxa (lavender/blurple); default é azul e
      // orange/mint exercitam accents claros — o mecanismo é o mesmo.
      for (final id in ['default', 'blurple', 'lavender', 'orange', 'mint']) {
        final palette = appThemePresetById(id).palette;
        await pumpEmpty(
          tester,
          theme: build4funTheme(palette),
          onShareScreen: () {},
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'preset $id quebrou o empty state',
        );
        expect(find.byType(TheaterEmptyIllustration), findsOneWidget);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Iniciar câmera'),
        );
        expect(
          button.style?.backgroundColor?.resolve({}),
          palette.accent,
          reason: 'preset $id: CTA primário fora do accent',
        );
      }
    });

    testWidgets('backdrop temático persiste com transmissões ativas', (
      tester,
    ) async {
      await pumpEmpty(
        tester,
        onShareScreen: () {},
        participants: [
          _participant('u1', 'Soul', screen: true),
          _participant('u2', 'Luna', camera: true),
        ],
      );

      expect(tester.takeException(), isNull);
      // Tiles renderizados E o mesmo fundo do estado vazio atrás deles.
      expect(find.byType(VoiceVideoTile), findsNWidgets(2));
      expect(find.byType(TheaterStageBackdrop), findsOneWidget);
      // Card do vazio não aparece junto das transmissões.
      expect(find.text('Nenhuma transmissão ativa'), findsNothing);
    });

    testWidgets('Saiba como funciona abre o diálogo de ajuda', (tester) async {
      await pumpEmpty(tester, onShareScreen: () {});

      await tester.tap(find.text('Saiba como funciona'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Como funciona o Modo Teatro'), findsOneWidget);
    });
  });
}
