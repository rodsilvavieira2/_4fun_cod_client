import 'dart:async';
import 'dart:io';

import 'package:desktop_updater/desktop_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_update_state.dart';
import 'update_config.dart';
import 'update_recovery_store.dart';

/// Backend real (Windows/Linux via `desktop_updater`, fluxo assinado
/// `app-archive.json → release.json → artefato`). Arquivo io-only.
AppUpdateBackend createAppUpdateBackend() => IoAppUpdateBackend();

class IoAppUpdateBackend extends AppUpdateBackend {
  IoAppUpdateBackend() {
    _loadVersion();
  }

  DesktopUpdaterController? _controller;
  AppUpdateStatus _status = AppUpdateStatus.idle;
  String? _currentVersion;
  String? _latestVersion;
  String? _dismissedVersion;
  double? _downloadProgress;
  String? _errorMessage;
  bool _manualUpToDate = false;
  bool _disposed = false;

  bool get _supported => shouldEnableUpdates(
    isWeb: kIsWeb,
    isLinux: Platform.isLinux,
    isWindows: Platform.isWindows,
  );

  void _set(AppUpdateStatus status) {
    if (_disposed) return;
    _status = status;
    notifyListeners();
  }

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

  Future<DesktopUpdaterController> _ensureController() async {
    final existing = _controller;
    if (existing != null) return existing;
    final packageId = expectedPackageIdForPlatform(
      isWindows: Platform.isWindows,
      isLinux: Platform.isLinux,
    );
    if (packageId == null) {
      throw UnsupportedError('Auto-update suportado só em Windows/Linux.');
    }
    final support = await getApplicationSupportDirectory();
    final sep = Platform.pathSeparator;
    final file = File(
      <String>[
        support.path,
        'desktop_updater',
        'pending-install-stable.json',
      ].join(sep),
    );
    final controller = DesktopUpdaterController(
      appArchiveUrl: updateAppArchiveUrl,
      expectedPackageId: packageId,
      trustedReleasePublicKeys: trustedReleasePublicKeys,
      recoveryStore: JsonFileUpdateRecoveryStore(file),
      channel: updateChannel,
      skipInitialVersionCheck: true,
    )..addListener(_onControllerState);
    _controller = controller;
    return controller;
  }

  void _onControllerState() {
    final controller = _controller;
    if (controller == null) return;
    final state = controller.state;
    if (state is UpdateChecking) {
      _downloadProgress = null;
      _set(AppUpdateStatus.checking);
    } else if (state is UpdateAvailable) {
      _latestVersion = state.descriptor.version;
      _downloadProgress = null;
      _manualUpToDate = false;
      _set(AppUpdateStatus.available);
    } else if (state is UpdateFreshInstallRequired) {
      _latestVersion = state.descriptor.version;
      _downloadProgress = null;
      _manualUpToDate = false;
      // Sem install in-place: o banner vira aviso + link manual.
      _errorMessage =
          'Essa versão exige instalação manual ($updateReleasesPageUrl).';
      _set(AppUpdateStatus.available);
    } else if (state is UpdateBlockedBySupportPolicy) {
      _latestVersion = state.descriptor.version;
      _manualUpToDate = false;
      _set(AppUpdateStatus.available);
    } else if (state is UpdateDownloading) {
      _downloadProgress = state.totalBytes > 0
          ? state.receivedBytes / state.totalBytes
          : null;
      _set(AppUpdateStatus.downloading);
    } else if (state is UpdateReadyToInstall) {
      _downloadProgress = 1;
      _set(AppUpdateStatus.readyToInstall);
    } else if (state is UpdateInstalling) {
      _set(AppUpdateStatus.downloading);
    } else if (state is UpdateFailed) {
      _errorMessage = _friendly(state.error);
      _downloadProgress = null;
      _set(AppUpdateStatus.failed);
    }
    // UpdateIdle: mantém o status atual (up-to-date não tem estado próprio;
    // a checagem manual resolve via ManualUpdateCheckResult).
  }

  static String _friendly(Object error) {
    if (error is SocketException) {
      return 'Sem conexão com o servidor de updates.';
    }
    if (error is TimeoutException) {
      return 'Tempo esgotado ao verificar updates.';
    }
    final text = error.toString();
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  @override
  AppUpdateStatus get status => _status;

  @override
  String? get currentVersion => _currentVersion;

  @override
  String? get latestVersion => _latestVersion;

  @override
  double? get downloadProgress => _downloadProgress;

  @override
  String? get errorMessage => _errorMessage;

  @override
  bool get isSupported => _supported;

  @override
  bool get isDismissed =>
      _latestVersion != null && _dismissedVersion == _latestVersion;

  @override
  bool get manualUpToDate => _manualUpToDate;

  @override
  Future<void> checkOnStartup() async {
    if (!_supported || !isUpdateSigningConfigured) return;
    try {
      final controller = await _ensureController();
      _set(AppUpdateStatus.checking);
      await controller.checkVersion().timeout(const Duration(seconds: 20));
      if (_status == AppUpdateStatus.checking) {
        _set(AppUpdateStatus.idle);
      }
    } catch (_) {
      // Startup nunca incomoda: volta a idle em silêncio.
      if (_status == AppUpdateStatus.checking) {
        _set(AppUpdateStatus.idle);
      }
    }
  }

  @override
  Future<bool> checkForUpdates() async {
    if (!_supported) {
      throw UnsupportedError('Auto-update suportado só em Windows/Linux.');
    }
    if (!isUpdateSigningConfigured) {
      _errorMessage =
          'Updates ainda não configurados (assinatura pendente, ver ADR).';
      _set(AppUpdateStatus.unconfigured);
      throw StateError(_errorMessage!);
    }
    final controller = await _ensureController();
    _manualUpToDate = false;
    _errorMessage = null;
    _set(AppUpdateStatus.checking);
    final result = await controller.checkForUpdates().timeout(
      const Duration(seconds: 30),
    );
    if (result is ManualUpdateCheckUpToDate) {
      _manualUpToDate = true;
      _set(AppUpdateStatus.upToDate);
      return false;
    }
    if (result is ManualUpdateCheckFailed) {
      Error.throwWithStackTrace(result.error, result.stackTrace);
    }
    return true;
  }

  @override
  Future<void> downloadUpdate() async {
    final controller = _controller ?? await _ensureController();
    await controller.downloadUpdate().timeout(const Duration(minutes: 10));
  }

  @override
  Future<void> restartToInstall() async {
    final controller = _controller ?? await _ensureController();
    await controller.restartApp();
  }

  @override
  void dismiss() {
    _dismissedVersion = _latestVersion;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.removeListener(_onControllerState);
    _controller?.dispose();
    super.dispose();
  }
}
