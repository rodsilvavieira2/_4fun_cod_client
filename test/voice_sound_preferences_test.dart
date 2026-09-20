import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fourfun_cod_client/core/sound/voice_sound_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('default ligado e persiste desligar', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(voiceSoundPreferencesProvider, (_, _) {});
    addTearDown(sub.close);

    expect(container.read(voiceSoundPreferencesProvider), isTrue);

    await container
        .read(voiceSoundPreferencesProvider.notifier)
        .setEnabled(false);
    expect(container.read(voiceSoundPreferencesProvider), isFalse);

    final stored = await SharedPreferences.getInstance();
    expect(stored.getBool(voiceSoundsEnabledKey), isFalse);
  });

  test('restaura desligado salvo', () async {
    SharedPreferences.setMockInitialValues({voiceSoundsEnabledKey: false});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final sub = container.listen(voiceSoundPreferencesProvider, (_, _) {});
    addTearDown(sub.close);

    await container
        .read(voiceSoundPreferencesProvider.notifier)
        .ensureInitialized();
    expect(container.read(voiceSoundPreferencesProvider), isFalse);
  });
}
