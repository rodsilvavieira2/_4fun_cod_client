import 'dart:io';

import 'package:desktop_updater/updater_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/updates/update_recovery_store.dart';

void main() {
  test(
    'roundtrip preserva transactionId (handoff exige readback exato)',
    () async {
      final dir = await Directory.systemTemp.createTemp('recovery-store-test');
      try {
        final store = JsonFileUpdateRecoveryStore(
          File('${dir.path}/pending-install-stable.json'),
        );
        final marker = UpdateInstallRecoveryMarker.pendingV3(
          createdAt: DateTime.now().toUtc(),
          packageVersion: '3.1.6',
          platform: 'windows',
          channel: 'stable',
          appVersion: '1.0.1+1',
          updateVersion: '1.1.0',
          updateBuildNumber: 1,
          expectedPackageId: 'fourfun_cod_client',
          stagingPath: r'C:\staging\update',
          stageProvenanceSha256: 'a' * 64,
          diagnosticsText: null,
          transactionId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
        );

        await store.writePendingInstall(marker);
        final readback = await store.readPendingInstall(channel: 'stable');

        // Sem transactionId o handoff falha com "Recovery marker readback did
        // not match the write" (regressão v1.1.0 no Windows).
        expect(readback?.transactionId, marker.transactionId);
        expect(readback?.stagingPath, marker.stagingPath);
        expect(readback?.stageProvenanceSha256, marker.stageProvenanceSha256);
        expect(readback?.createdAt.toUtc(), marker.createdAt.toUtc());
        expect(readback?.updateVersion, marker.updateVersion);

        // Canal diferente não vaza marker.
        expect(await store.readPendingInstall(channel: 'beta'), isNull);

        await store.clearPendingInstall(channel: 'stable');
        expect(await store.readPendingInstall(channel: 'stable'), isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
