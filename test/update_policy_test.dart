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
    test('app archive url points to the VPS feed', () {
      expect(updateAppArchiveUrl.host, 'updates.srv1849611.hstgr.cloud');
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

  group('manual download url (VPS por plataforma)', () {
    test('windows resolve para o setup.exe versionado', () {
      expect(
        manualDownloadUrl(
          isWindows: true,
          isLinux: false,
          latestVersion: '1.2.4+59',
        ),
        'https://updates.srv1849611.hstgr.cloud/v1.2.4/4fun-cod-windows-x64-1.2.4-setup.exe',
      );
    });

    test('linux resolve para o tar.gz versionado', () {
      expect(
        manualDownloadUrl(
          isWindows: false,
          isLinux: true,
          latestVersion: '1.2.4+59',
        ),
        'https://updates.srv1849611.hstgr.cloud/v1.2.4/4fun-cod-linux-x64-1.2.4.tar.gz',
      );
    });

    test('sem versao cai para o listing /latest/', () {
      expect(
        manualDownloadUrl(isWindows: true, isLinux: false),
        updatesReleasesListingUrl,
      );
      expect(
        manualDownloadUrl(
          isWindows: false,
          isLinux: true,
          latestVersion: 'invalida',
        ),
        updatesReleasesListingUrl,
      );
      expect(
        manualDownloadUrl(isWindows: false, isLinux: false, latestVersion: '1.2.4+59'),
        updatesReleasesListingUrl,
      );
    });

    test('extractUpdateVersionCore tolera build metadata', () {
      expect(extractUpdateVersionCore('1.2.4+59'), '1.2.4');
      expect(extractUpdateVersionCore('1.2.4'), '1.2.4');
      expect(extractUpdateVersionCore(null), isNull);
      expect(extractUpdateVersionCore(''), isNull);
      expect(extractUpdateVersionCore('abc'), isNull);
    });
  });
}
