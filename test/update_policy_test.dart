import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/updates/update_config.dart';

void main() {
  group('shouldEnableUpdates', () {
    test('enables on linux/windows desktop builds', () {
      for (final platform in ['linux', 'windows']) {
        expect(
          shouldEnableUpdates(
            isWeb: false,
            isLinux: platform == 'linux',
            isWindows: platform == 'windows',
          ),
          isTrue,
          reason: platform,
        );
      }
    });

    test('disables on web and out-of-scope platforms', () {
      expect(
        shouldEnableUpdates(isWeb: true, isLinux: false, isWindows: true),
        isFalse,
        reason: 'web nunca atualiza in-place',
      );
      expect(
        shouldEnableUpdates(isWeb: false, isLinux: false, isWindows: false),
        isFalse,
        reason: 'macOS/mobile fora de escopo',
      );
    });
  });

  group('expectedPackageIdForPlatform', () {
    test('matches publish identity per platform', () {
      expect(
        expectedPackageIdForPlatform(isWindows: true, isLinux: false),
        windowsPackageId,
      );
      expect(
        expectedPackageIdForPlatform(isWindows: false, isLinux: true),
        linuxPackageId,
      );
      expect(
        expectedPackageIdForPlatform(isWindows: false, isLinux: false),
        isNull,
      );
    });
  });

  group('update feed', () {
    test('app archive url points to github releases', () {
      expect(updateAppArchiveUrl.host, 'github.com');
      expect(updateAppArchiveUrl.pathSegments.last, 'app-archive.json');
    });

    test('signing configured (release key pinned)', () {
      expect(isUpdateSigningConfigured, isTrue);
      expect(
        trustedReleasePublicKeys,
        contains('release-de4dba08820a7c59511f86ce'),
      );
    });
  });
}
