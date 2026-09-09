import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/desktop/single_instance_policy.dart';

void main() {
  group('shouldEnforceSingleInstance', () {
    test('enforces on linux/windows release builds', () {
      for (final platform in ['linux', 'windows']) {
        expect(
          shouldEnforceSingleInstance(
            isWeb: false,
            isDebug: false,
            isLinux: platform == 'linux',
            isWindows: platform == 'windows',
          ),
          isTrue,
          reason: platform,
        );
      }
    });

    test('skips on unsupported web, debug and out-of-scope platforms', () {
      // Web está fora de suporte; esta política defensiva nunca impõe trava.
      expect(
        shouldEnforceSingleInstance(
          isWeb: true,
          isDebug: false,
          isLinux: false,
          isWindows: true,
        ),
        isFalse,
      );
      // Debug permite múltiplas cópias lado a lado.
      expect(
        shouldEnforceSingleInstance(
          isWeb: false,
          isDebug: true,
          isLinux: true,
          isWindows: false,
        ),
        isFalse,
      );
      // macOS/mobile fora do escopo do projeto (linux/windows).
      expect(
        shouldEnforceSingleInstance(
          isWeb: false,
          isDebug: false,
          isLinux: false,
          isWindows: false,
        ),
        isFalse,
      );
    });
  });
}
