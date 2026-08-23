/// Sink de arquivo do [AppLogger] — stub para web (sem dart:io).
///
/// Em plataformas web não há sistema de arquivos; o log fica apenas no
/// console. Compilado quando `dart.library.io` não existe (import
/// condicional em app_logger.dart).
class AppLoggerFileSink {
  AppLoggerFileSink({String? logsDirectory});

  String? get logFilePath => null;

  void write(String line) {}
}
