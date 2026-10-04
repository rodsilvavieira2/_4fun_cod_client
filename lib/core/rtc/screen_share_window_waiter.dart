import 'dart:async';

import '../native/native_media_backend.dart';

enum WindowShareWaitFailure { cancelled, closed, timeout }

class WindowShareWaitException implements Exception {
  const WindowShareWaitException(this.reason);
  final WindowShareWaitFailure reason;
}

/// Revalida a identidade da janela antes de devolver uma fonte WebRTC.
/// Prazo nulo mantém a espera até restauração, fechamento ou cancelamento.
class ScreenShareWindowWaiter {
  ScreenShareWindowWaiter({
    required this.backend,
    required this.target,
    this.timeout = const Duration(seconds: 60),
    this.interval = const Duration(milliseconds: 250),
  }) : _elapsed = Stopwatch()..start();

  final NativeWindowShareBackend backend;
  final NativeShareWindowTarget target;
  final Duration? timeout;
  final Duration interval;
  final Stopwatch _elapsed;
  final _cancelled = Completer<void>();
  bool _hasWaited = false;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void _check() {
    if (_cancelled.isCompleted) {
      throw const WindowShareWaitException(WindowShareWaitFailure.cancelled);
    }
    if (timeout != null && _elapsed.elapsed >= timeout!) {
      throw const WindowShareWaitException(WindowShareWaitFailure.timeout);
    }
  }

  Future<T> _query<T>(Future<T> query) async {
    _check();
    final result = await Future.any<T>([
      timeout == null
          ? query
          : query.timeout(
              timeout! - _elapsed.elapsed,
              onTimeout: () => throw const WindowShareWaitException(
                WindowShareWaitFailure.timeout,
              ),
            ),
      _cancelled.future.then<T>(
        (_) => throw const WindowShareWaitException(
          WindowShareWaitFailure.cancelled,
        ),
      ),
    ]);
    _check();
    return result;
  }

  Future<String> resolve({
    required FutureOr<void> Function() onWaiting,
    bool requireFocus = false,
  }) async {
    _hasWaited = _hasWaited || requireFocus;
    while (true) {
      _check();
      final state = await _query(backend.readWindowState(target));
      if (!state.valid) {
        throw const WindowShareWaitException(WindowShareWaitFailure.closed);
      }
      if (state.capturable && (!_hasWaited || state.foreground)) {
        final id = await _query(backend.resolveWindowSource(target));
        final after = await _query(backend.readWindowState(target));
        if (!after.valid) {
          throw const WindowShareWaitException(WindowShareWaitFailure.closed);
        }
        if (id != null &&
            after.capturable &&
            (!_hasWaited || after.foreground)) {
          return id;
        }
      }
      _hasWaited = true;
      await onWaiting();
      final timerDone = Completer<void>();
      final timer = Timer(interval, timerDone.complete);
      try {
        await Future.any([timerDone.future, _cancelled.future]);
      } finally {
        timer.cancel();
      }
    }
  }
}
