import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/rtc/rtc_service.dart';
import 'package:fourfun_cod_client/features/voice/voice_screen.dart';

class _TrackRef extends RtcVideoTrackRef {
  const _TrackRef();
}

void main() {
  testWidgets('mantém spinner sobre o preview enquanto a câmera carrega', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: CameraPreviewSurface(
              trackRef: _TrackRef(),
              loading: true,
              error: null,
              onRetry: null,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('mostra erro e permite nova tentativa após falha', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: CameraPreviewSurface(
              trackRef: null,
              loading: false,
              error: 'Não foi possível iniciar o preview da câmera.',
              onRetry: () => retries++,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Não foi possível iniciar o preview da câmera.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tentar novamente'));
    expect(retries, 1);
  });
}
