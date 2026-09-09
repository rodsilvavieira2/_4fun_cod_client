import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/native/native_media_backend.dart';
import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/core/theme/app_theme.dart';
import 'package:fourfun_cod_client/features/voice/go_live_modal.dart';

class _FakeScreenShareBackend implements NativeScreenShareBackend {
  _FakeScreenShareBackend({required this.usesSystemPicker});

  final bool usesSystemPicker;

  @override
  ScreenShareCapabilities get capabilities => ScreenShareCapabilities(
    usesSystemPicker: usesSystemPicker,
    supportsWindowSources: true,
    supportsSystemAudio: false,
  );

  @override
  Future<List<RtcScreenShareSource>> loadSources() async => const [];

  @override
  bool canUseKind(RtcScreenShareSourceKind kind) => true;

  @override
  String? disabledReasonFor(RtcScreenShareSourceKind kind) => null;
}

/// Abre o modal via botão e o mantém aberto para interação.
Future<void> _openModal(
  WidgetTester tester, {
  required NativeScreenShareBackend backend,
  required RtcScreenShareQuality pending,
  required void Function(Future<GoLiveResult?>) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme4funCod,
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => onResult(
              showGoLiveModal(
                context,
                backend: backend,
                pendingQuality: pending,
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
  expect(find.text('Compartilhar tela'), findsOneWidget);
}

void main() {
  group('goLiveQualityFor', () {
    test('mapeia os 4 chips para perfis reais', () {
      expect(goLiveQualityFor(GoLiveQuality.auto), RtcScreenShareQuality.auto);
      expect(
        goLiveQualityFor(GoLiveQuality.high),
        RtcScreenShareQuality.q1080p60,
      );
      expect(
        goLiveQualityFor(GoLiveQuality.medium),
        RtcScreenShareQuality.q1080p30,
      );
      expect(
        goLiveQualityFor(GoLiveQuality.low),
        RtcScreenShareQuality.q720p15,
      );
    });
  });

  group('goLiveQualityFromPending', () {
    test('mapeia direto os perfis com chip', () {
      expect(
        goLiveQualityFromPending(RtcScreenShareQuality.auto),
        GoLiveQuality.auto,
      );
      expect(
        goLiveQualityFromPending(RtcScreenShareQuality.q1080p60),
        GoLiveQuality.high,
      );
      expect(
        goLiveQualityFromPending(RtcScreenShareQuality.q1080p30),
        GoLiveQuality.medium,
      );
      expect(
        goLiveQualityFromPending(RtcScreenShareQuality.q720p15),
        GoLiveQuality.low,
      );
    });

    test('órfãos do sheet caem no chip mais próximo', () {
      expect(
        goLiveQualityFromPending(RtcScreenShareQuality.q1080p15),
        GoLiveQuality.medium,
      );
      expect(
        goLiveQualityFromPending(RtcScreenShareQuality.q360p3),
        GoLiveQuality.low,
      );
    });
  });

  group('showGoLiveModal (portal do sistema)', () {
    testWidgets('Go Live retorna tipo + qualidade com defaults', (
      tester,
    ) async {
      GoLiveResult? result;
      await _openModal(
        tester,
        backend: _FakeScreenShareBackend(usesSystemPicker: true),
        pending: RtcScreenShareQuality.auto,
        onResult: (f) => f.then((r) => result = r),
      );

      expect(find.text('Escolha o que você vai transmitir.'), findsOneWidget);
      expect(find.text('Escolha a qualidade da transmissão.'), findsOneWidget);
      expect(find.textContaining('portal do sistema'), findsOneWidget);

      await tester.tap(find.text('Go Live'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.kind, RtcScreenShareSourceKind.display);
      expect(result!.sourceId, isNull);
      expect(result!.quality, GoLiveQuality.auto);
      expect(
        result!.includeAudio,
        isTrue,
        reason: 'áudio de sistema vai junto por padrão (opt-out)',
      );
    });

    testWidgets('troca de tipo e qualidade reflete no resultado', (
      tester,
    ) async {
      GoLiveResult? result;
      await _openModal(
        tester,
        backend: _FakeScreenShareBackend(usesSystemPicker: true),
        pending: RtcScreenShareQuality.q360p3,
        onResult: (f) => f.then((r) => result = r),
      );

      // Pendente órfão (q360p3) abre no chip mais próximo (Baixa); troca tudo.
      await tester.tap(find.text('Janela'));
      await tester.pump();
      await tester.tap(find.text('Alta'));
      await tester.pump();
      await tester.tap(find.text('Go Live'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.kind, RtcScreenShareSourceKind.window);
      expect(result!.quality, GoLiveQuality.high);
    });

    testWidgets('opt-out do áudio reflete no resultado', (tester) async {
      GoLiveResult? result;
      await _openModal(
        tester,
        backend: _FakeScreenShareBackend(usesSystemPicker: true),
        pending: RtcScreenShareQuality.auto,
        onResult: (f) => f.then((r) => result = r),
      );

      await tester.tap(find.text('Incluir áudio do sistema'));
      await tester.pump();
      await tester.tap(find.text('Go Live'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.includeAudio, isFalse);
    });

    testWidgets('modo janela no Linux avisa mix geral', (tester) async {
      await _openModal(
        tester,
        backend: _FakeScreenShareBackend(usesSystemPicker: true),
        pending: RtcScreenShareQuality.auto,
        onResult: (_) async {},
      );

      await tester.tap(find.text('Janela'));
      await tester.pump();

      expect(find.textContaining('mix geral do sistema'), findsOneWidget);
    });

    testWidgets('Cancelar retorna null', (tester) async {
      GoLiveResult? result = const GoLiveResult(
        kind: RtcScreenShareSourceKind.display,
        sourceId: 'x',
        quality: GoLiveQuality.high,
        includeAudio: true,
      );
      var completed = false;
      await _openModal(
        tester,
        backend: _FakeScreenShareBackend(usesSystemPicker: true),
        pending: RtcScreenShareQuality.auto,
        onResult: (f) => f.then((r) {
          result = r;
          completed = true;
        }),
      );

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
      expect(result, isNull);
    });
  });
}
