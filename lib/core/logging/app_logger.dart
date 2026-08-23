import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Nível de severidade do log.
enum LogLevel {
  debug(0),
  info(1),
  warning(2),
  error(3);

  const LogLevel(this.severity);
  final int severity;

  String get label => name.toUpperCase();
}

/// Serviço central de log do client (diagnóstico).
///
/// - **Console**: `debugPrint` sempre (visível no `flutter run`).
/// - **Arquivo**: em desktop/IO, grava em
///   `<HOME>/.local/share/4fun_cod_client/logs/app.log` (rotativo ~2MB) —
///   permite inspecionar o que o client fez de FORA (ex.: `tail -f` no log
///   durante um diagnóstico). Em web o file logging é desativado.
/// - **NUNCA logar segredos**: o logger redige `Bearer <token>` e valores
///   de campos `password`/`secret`; os interceptors que o usam não logam
///   headers nem bodies de auth.
class AppLogger {
  AppLogger({
    this.minLevel = LogLevel.debug,
    String? logsDirectory,
  }) : _logsDirectory = logsDirectory ?? _defaultLogsDirectory();

  final LogLevel minLevel;
  final String? _logsDirectory;

  static const _maxFileBytes = 2 * 1024 * 1024; // 2MB
  static final _fileLock = <String, Future<void>>{};

  static String? _defaultLogsDirectory() {
    if (kIsWeb) return null;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home == null) return null;
    return '$home/.local/share/4fun_cod_client/logs';
  }

  /// Caminho do arquivo de log ativo (null em web / sem diretório).
  String? get logFilePath =>
      _logsDirectory == null ? null : '$_logsDirectory/app.log';

  void d(String message, {String tag = 'app'}) =>
      _log(LogLevel.debug, message, tag: tag);

  void i(String message, {String tag = 'app'}) =>
      _log(LogLevel.info, message, tag: tag);

  void w(String message, {String tag = 'app'}) =>
      _log(LogLevel.warning, message, tag: tag);

  void e(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String tag = 'app',
  }) =>
      _log(LogLevel.error, message, tag: tag, error: error, stackTrace: stackTrace);

  void _log(
    LogLevel level,
    String message, {
    required String tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.severity < minLevel.severity) return;
    final line = _format(level, tag, message, error, stackTrace);
    debugPrint(line);
    _writeToFile(line);
  }

  String _format(
    LogLevel level,
    String tag,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    final now = DateTime.now().toIso8601String();
    final buffer = StringBuffer('$now [${level.label}] [$tag] ${_redact(message)}');
    if (error != null) {
      buffer.write(' | ${_redact(error.toString())}');
    }
    if (stackTrace != null) {
      final firstFrame = stackTrace.toString().split('\n').firstOrNull;
      if (firstFrame != null && firstFrame.trim().isNotEmpty) {
        buffer.write(' | $firstFrame');
      }
    }
    return buffer.toString();
  }

  /// Redige segredos óbvios que possam vazar em mensagens de erro: tokens
  /// Bearer e valores de campos sensíveis.
  static String _redact(String input) {
    var out = input.replaceAllMapped(
      RegExp(r'Bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false),
      (_) => 'Bearer ***',
    );
    out = out.replaceAllMapped(
      RegExp(r'("(?:password|token|secret|refreshToken)"\s*:\s*")[^"]*(")',
          caseSensitive: false),
      (m) => '${m.group(1)}***${m.group(2)}',
    );
    return out;
  }

  void _writeToFile(String line) {
    final dir = _logsDirectory;
    if (dir == null) return;
    // Serializa gravações por diretório (append concorrente seguro).
    _fileLock[dir] = (_fileLock[dir] ?? Future.value()).then((_) async {
      try {
        final directory = Directory(dir);
        if (!directory.existsSync()) {
          directory.createSync(recursive: true);
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

/// Provider do logger da aplicação.
final appLoggerProvider = Provider<AppLogger>((ref) {
  // DEBUG por padrão; em release, apenas warnings/errors no arquivo.
  final isDebug = !kReleaseMode;
  return AppLogger(minLevel: isDebug ? LogLevel.debug : LogLevel.warning);
});
