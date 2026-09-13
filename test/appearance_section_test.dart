import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/theme/app_theme.dart';
import 'package:fourfun_cod_client/core/ui/settings_sections/appearance_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpSection(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme4funCod,
          home: const Scaffold(
            body: SingleChildScrollView(child: AppearanceSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renderiza presets e seleciona um preset', (tester) async {
    await pumpSection(tester);

    expect(find.text('Cores'), findsOneWidget);
    expect(find.byTooltip('Padrão'), findsOneWidget);
    expect(find.byTooltip('Laranja'), findsOneWidget);

    await tester.tap(find.byTooltip('Laranja'));
    await tester.pumpAndSettle();

    final stored = await SharedPreferences.getInstance();
    expect(stored.getString(appearanceThemeModeKey), 'preset');
    expect(stored.getString(appearanceThemePresetIdKey), 'orange');
    expect(find.text('#FF7100'), findsOneWidget);
  });

  testWidgets('campo HEX aplica cor customizada válida', (tester) async {
    await pumpSection(tester);

    await tester.enterText(find.byType(TextField), '#11AA77');
    await tester.pumpAndSettle();

    final stored = await SharedPreferences.getInstance();
    expect(stored.getString(appearanceThemeModeKey), 'custom');
    expect(stored.getInt(appearanceThemeCustomSeedArgbKey), 0xFF11AA77);
    expect(find.text('CUSTOM'), findsOneWidget);
  });

  testWidgets('campo HEX rejeita cor inválida', (tester) async {
    await pumpSection(tester);

    await tester.enterText(find.byType(TextField), '#11');
    await tester.pumpAndSettle();

    final stored = await SharedPreferences.getInstance();
    expect(stored.getString(appearanceThemeModeKey), isNull);
    expect(stored.getInt(appearanceThemeCustomSeedArgbKey), isNull);
    expect(find.text('Use #RRGGBB.'), findsOneWidget);
  });
}
