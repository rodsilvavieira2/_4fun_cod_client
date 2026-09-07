import 'package:package_info_plus/package_info_plus.dart';

import 'app_update_state.dart';

/// Backend no-op (web e qualquer não-io): compila sem `dart:io` e nunca
/// faz request. A seção de Atualizações mostra ao menos a versão atual.
AppUpdateBackend createAppUpdateBackend() => StubAppUpdateBackend();

class StubAppUpdateBackend extends AppUpdateBackend {
  StubAppUpdateBackend() {
    _loadVersion();
  }

  final AppUpdateStatus _status = AppUpdateStatus.unconfigured;
  String? _currentVersion;
  bool _disposed = false;

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _currentVersion = null;
    }
    if (_disposed) return;
    notifyListeners();
  }

  @override
  AppUpdateStatus get status => _status;

  @override
  String? get currentVersion => _currentVersion;

  @override
  String? get latestVersion => null;

  @override
  double? get downloadProgress => null;

  @override
  String? get errorMessage => null;

  @override
  bool get isSupported => false;

  @override
  bool get isDismissed => true;

  @override
  bool get manualUpToDate => false;

  @override
  Future<void> checkOnStartup() async {}

  @override
  Future<bool> checkForUpdates() async => false;

  @override
  Future<void> downloadUpdate() async {}

  @override
  Future<void> restartToInstall() async {}

  @override
  void dismiss() {}

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
