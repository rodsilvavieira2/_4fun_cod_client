import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/ui/screen_share_pending_notice.dart';

void main() {
  testWidgets('mensagem exata e cancelamento cabem na sidebar estreita', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: ScreenSharePendingNotice(onCancel: () => cancelled = true),
          ),
        ),
      ),
    );
    expect(find.text('Iniciando transmissão…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancelar'));
    expect(cancelled, isTrue);
  });
}
