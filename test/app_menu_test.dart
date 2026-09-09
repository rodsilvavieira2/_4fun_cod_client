import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/ui/menus/app_menu.dart';

void _noop(String? value) {}

List<PopupMenuEntry<String>> _buildItems(BuildContext context) => [
  AppMenuHeader<String>(title: 'Dispositivo de entrada'),
  AppMenuCheckedItem<String>.labeled(
    value: 'sys',
    checked: false,
    icon: Icons.mic_outlined,
    label: 'Padrão do sistema',
  ),
  AppMenuCheckedItem<String>.labeled(
    value: 'fifine',
    checked: true,
    icon: Icons.mic_outlined,
    label: 'Fifine Microphone',
  ),
  const AppMenuDivider(),
  AppMenuItem<String>.labeled(
    value: 'settings',
    icon: Icons.settings_outlined,
    label: 'Configurações de voz',
  ),
];

void main() {
  testWidgets('itens do AppMenu respeitam a altura compacta (32px)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            onSelected: _noop,
            itemBuilder: _buildItems,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();

    for (final label in [
      'Padrão do sistema',
      'Fifine Microphone',
      'Configurações de voz',
    ]) {
      final rows = find.ancestor(
        of: find.text(label),
        matching: find.byType(InkWell),
      );
      expect(rows, findsWidgets, reason: 'linha "$label" não encontrada');
      final heights = [
        for (var i = 0; i < rows.evaluate().length; i++)
          tester.getSize(rows.at(i)).height,
      ];
      // ignore: avoid_print
      print('ALTURAS "$label": $heights');
      final rowHeight = heights.reduce((a, b) => a < b ? a : b);
      expect(rowHeight, lessThanOrEqualTo(33.0), reason: 'linha "$label" alta');
    }
  });
}
