import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_logger_sink_stub.dart'
    if (dart.library.io) 'app_logger_sink_io.dart';

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
///   `<HOME>/.local/share/4fun_cod_client/logs/app.log` (rotativo ~2MB,
///   ver [AppLoggerFileSink]) — permite inspecionar o que o client fez de
///   FORA (ex.: `tail -f` no log durante um diagnóstico). Em web o file
///   logging é desativado (sink stub).
/// - **NUNCA logar segredos**: o logger redige `Bearer <token>` e valores
///   de campos `password`/`secret`; os interceptors que o usam não logam
///   headers nem bodies de auth.
class AppLogger {
  AppLogger({
    this.minLevel = LogLevel.debug,
    String? logsDirectory,
  }) : _fileSink = AppLoggerFileSink(logsDirectory: logsDirectory);

  final LogLevel minLevel;
  final AppLoggerFileSink _fileSink;

  /// Caminho do arquivo de log ativo (null em web / sem diretório).
  String? get logFilePath => _fileSink.logFilePath;

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
    _fileSink.write(line);
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
}

/// Provider do logger da aplicação.
final appLoggerProvider = Provider<AppLogger>((ref) {
  // DEBUG por padrão; em release, apenas warnings/errors no arquivo.
  final isDebug = !kReleaseMode;
  return AppLogger(minLevel: isDebug ? LogLevel.debug : LogLevel.warning);
});
