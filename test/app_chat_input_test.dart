import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/ui/inputs/app_chat_input.dart';

void main() {
  testWidgets('Enter envia e limpa; Shift+Enter quebra linha', (tester) async {
    final controller = TextEditingController();
    final sent = <String>[];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppChatInput(
            controller: controller,
            onSend: (text) {
              sent.add(text);
              controller.clear();
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'oi');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, ['oi']);
    expect(controller.text, isEmpty);

    // Shift+Enter insere nova linha em vez de enviar.
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    expect(sent, hasLength(1), reason: 'Shift+Enter não deve enviar');
    expect(controller.text, contains('\n'));
  });

  testWidgets('campo interno não pinta fill próprio (superfície única)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppChatInput(
            controller: TextEditingController(),
            onSend: (_) {},
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final decoration = field.decoration!;
    expect(decoration.filled, isFalse);
    expect(
      decoration.border,
      isA<InputBorder>().having((b) => b.borderSide.width, 'largura', 0.0),
    );
  });

  testWidgets('trailingActions ficam à direita do campo e antes do envio', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppChatInput(
            controller: controller,
            trailingActions: const [Text('Ação direita')],
            onSend: (_) {},
          ),
        ),
      ),
    );

    final fieldRect = tester.getRect(find.byType(TextField));
    final actionRect = tester.getRect(find.text('Ação direita'));
    final sendRect = tester.getRect(find.byIcon(Icons.arrow_upward));

    expect(actionRect.left, greaterThan(fieldRect.right));
    expect(sendRect.left, greaterThan(actionRect.right));
  });
}
