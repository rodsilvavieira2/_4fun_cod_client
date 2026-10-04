import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/ui/inputs/app_color_picker.dart';
import 'package:fourfun_cod_client/core/ui/inputs/app_select.dart';

void main() {
  testWidgets('select abre menu compacto e escolhe uma opção', (tester) async {
    String selection = 'a';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 260,
              child: AppSelect<String>(
                label: 'Fonte',
                value: selection,
                options: const [
                  AppSelectOption(value: 'a', label: 'Geist'),
                  AppSelectOption(value: 'b', label: 'Geist Mono'),
                ],
                onChanged: (value) => setState(() => selection = value),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Geist').first);
    await tester.pumpAndSettle();
    expect(find.text('Geist Mono'), findsOneWidget);
    await tester.tap(find.text('Geist Mono'));
    await tester.pumpAndSettle();

    expect(selection, 'b');
    expect(find.text('Geist Mono'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cores validam HEX e atualizam seleção', (tester) async {
    String? selection = '#5B76FF';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => AppColorPicker(
              label: 'Cor primária',
              value: selection,
              swatches: const ['#5B76FF', '#62D6B0'],
              onChanged: (value) => setState(() => selection = value),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('Cor #62D6B0'));
    await tester.pump();
    expect(selection, '#62D6B0');

    await tester.tap(find.text('Personalizar'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '#123');
    await tester.tap(find.text('Aplicar'));
    await tester.pump();
    expect(find.text('Use o formato #RRGGBB.'), findsOneWidget);
    expect(selection, '#62D6B0');

    await tester.enterText(find.byType(TextField), '#abcdef');
    await tester.tap(find.text('Aplicar'));
    await tester.pump();
    expect(selection, '#ABCDEF');
    expect(find.byTooltip('Cor #ABCDEF'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
