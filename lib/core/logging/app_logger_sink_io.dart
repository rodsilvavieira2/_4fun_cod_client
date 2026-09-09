import 'dart:io';

/// Sink de arquivo do [AppLogger] — implementação IO (desktop/mobile).
///
/// Grava em `<HOME>/.local/share/4fun_cod_client/logs/app.log` (rotativo
/// ~2MB: renomeia para `app.log.1` e recomeça). Compilado apenas em
/// plataformas com `dart.library.io` (import condicional em app_logger.dart).
class AppLoggerFileSink {
  AppLoggerFileSink({String? logsDirectory})
    : directory = logsDirectory ?? _defaultDirectory();

  final String? directory;

  static const _maxFileBytes = 2 * 1024 * 1024; // 2MB
  static final _locks = <String, Future<void>>{};

  static String? _defaultDirectory() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) return null;
    return '$home/.local/share/4fun_cod_client/logs';
  }

  /// Caminho do arquivo de log ativo (null se não houver diretório).
  String? get logFilePath => directory == null ? null : '$directory/app.log';

  /// Serializa gravações por diretório (append concorrente seguro).
  void write(String line) {
    final dir = directory;
    if (dir == null) return;
    _locks[dir] = (_locks[dir] ?? Future.value()).then((_) async {
      try {
        final folder = Directory(dir);
        if (!folder.existsSync()) {
          folder.createSync(recursive: true);
        }
        final file = File('$dir/app.log');
        if (file.existsSync() && file.lengthSync() > _maxFileBytes) {
          final backup = File('$dir/app.log.1');
          if (backup.existsSync()) backup.deleteSync();
          file.renameSync(backup.path);
        }
        final sink = file.openSync(mode: FileMode.append);
        try {
          sink.writeStringSync('$line\n');
        } finally {
          sink.closeSync();
        }
      } catch (_) {
        // Logging nunca pode derrubar o app.
      }
    });
  }
}
