import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('carrega defaults e persiste preset local', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(appearanceThemeProvider, (_, _) {});
    addTearDown(sub.close);

    final preferences = await container.read(appearanceThemeProvider.future);

    expect(preferences.mode, AppearanceThemeMode.preset);
    expect(preferences.presetId, 'default');

    await container
        .read(appearanceThemeProvider.notifier)
        .selectPreset('orange');

    final stored = await SharedPreferences.getInstance();
    expect(stored.getString(appearanceThemeModeKey), 'preset');
    expect(stored.getString(appearanceThemePresetIdKey), 'orange');
  });

  test('salva cor customizada local', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(appearanceThemeProvider.notifier)
        .setCustomSeed(const Color(0xFF11AA77));

    final preferences = container.read(appearanceThemeProvider).valueOrNull!;
    expect(preferences.mode, AppearanceThemeMode.custom);
    expect(preferences.customSeed.toARGB32(), 0xFF11AA77);

    final stored = await SharedPreferences.getInstance();
    expect(stored.getString(appearanceThemeModeKey), 'custom');
    expect(stored.getInt(appearanceThemeCustomSeedArgbKey), 0xFF11AA77);
  });

  test('valida HEX e normaliza fallback de preset inexistente', () async {
    SharedPreferences.setMockInitialValues({
      appearanceThemePresetIdKey: 'sumiu',
      appearanceThemeCustomSeedArgbKey: 0x00123456,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final preferences = await container.read(appearanceThemeProvider.future);

    expect(preferences.presetId, 'default');
    expect(preferences.customSeed.toARGB32(), 0xFF123456);
    expect(parseHexColor('#FF7100')?.toARGB32(), 0xFFFF7100);
    expect(parseHexColor('ff7100')?.toARGB32(), 0xFFFF7100);
    expect(parseHexColor('#XYZ'), isNull);
    expect(colorToHex(const Color(0xFFFF7100)), '#FF7100');
  });
}
