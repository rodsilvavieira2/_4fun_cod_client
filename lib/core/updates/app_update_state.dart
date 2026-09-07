import 'package:flutter/foundation.dart';

/// Status simplificado do auto-update para a UI.
///
/// Desacoplado dos tipos do `desktop_updater` (que só existe no io):
/// a web compila via stub sem `dart:io`.
enum AppUpdateStatus {
  /// Nada em andamento / sem resultado.
  idle,

  /// Consultando o feed.
  checking,

  /// Release nova disponível (respeita [AppUpdateBackend.isDismissed] no banner).
  available,

  /// Baixando + verificando artefato ([AppUpdateBackend.downloadProgress]).
  downloading,

  /// Artefato staged, pronto para instalar (reiniciar aplica).
  readyToInstall,

  /// Checagem manual confirmou: já está na última.
  upToDate,

  /// Última operação falhou ([AppUpdateBackend.errorMessage]).
  failed,

  /// Plataforma fora de escopo ou assinatura ainda não configurada.
  unconfigured,
}

/// Contrato do backend de update (io real / stub web).
abstract class AppUpdateBackend extends ChangeNotifier {
  AppUpdateStatus get status;
  String? get currentVersion;
  String? get latestVersion;
  double? get downloadProgress;
  String? get errorMessage;

  /// `false` em web e fora de Windows/Linux.
  bool get isSupported;

  /// Versão dispensada com "Depois" (sentinela da sessão).
  bool get isDismissed;

  /// `true` quando a última checagem manual confirmou up-to-date.
  bool get manualUpToDate;

  /// Checagem de startup: nunca lança, nunca bloqueia.
  Future<void> checkOnStartup();

  /// Checagem explícita. Retorna `true` se há update; `false` se
  /// up-to-date. Lança em falha / plataforma sem suporte / sem assinatura.
  Future<bool> checkForUpdates();

  Future<void> downloadUpdate();
  Future<void> restartToInstall();

  /// Dispensa a [latestVersion] atual (sessão).
  void dismiss();
}
