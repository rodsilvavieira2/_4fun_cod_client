import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/native/native_media_backend.dart';
import 'package:fourfun_cod_client/core/rtc/screen_share_window_waiter.dart';

const target = NativeShareWindowTarget('123', 456);
const readyWindow = NativeShareWindowState(
  valid: true,
  visible: true,
  minimized: false,
  foreground: true,
);
const minimizedWindow = NativeShareWindowState(
  valid: true,
  visible: true,
  minimized: true,
  foreground: false,
);

class FakeWindowBackend extends WindowsScreenShareBackend {
  NativeShareWindowState window = minimizedWindow;
  String? resolvedId = '123';
  int resolveCalls = 0;
  Future<NativeShareWindowState> Function()? onRead;
  void Function()? onResolve;
  @override
  Future<NativeShareWindowState> readWindowState(
    NativeShareWindowTarget target,
  ) async => onRead == null ? window : await onRead!();
  @override
  Future<String?> resolveWindowSource(NativeShareWindowTarget target) async {
    resolveCalls++;
    onResolve?.call();
    return resolvedId;
  }
}

void main() {
  ScreenShareWindowWaiter waiter(FakeWindowBackend backend) =>
      ScreenShareWindowWaiter(
        backend: backend,
        target: target,
        timeout: const Duration(milliseconds: 100),
        interval: const Duration(milliseconds: 1),
      );
  Matcher failure(WindowShareWaitFailure reason) =>
      isA<WindowShareWaitException>().having((e) => e.reason, 'reason', reason);

  test('espera restaurar e focar antes de consultar fontes reais', () async {
    final backend = FakeWindowBackend();
    var waits = 0;
    final result = waiter(backend).resolve(
      onWaiting: () {
        waits++;
        expect(backend.resolveCalls, 0);
        backend.window = waits == 1
            ? const NativeShareWindowState(
                valid: true,
                visible: true,
                minimized: false,
                foreground: false,
              )
            : readyWindow;
      },
    );
    expect(await result, '123');
    expect(waits, 2);
    expect(backend.resolveCalls, 1);
  });

  test('janela comum visível não exige foco', () async {
    final backend = FakeWindowBackend()
      ..window = const NativeShareWindowState(
        valid: true,
        visible: true,
        minimized: false,
        foreground: false,
      );
    expect(
      await waiter(backend).resolve(onWaiting: () => fail('Não deve esperar')),
      '123',
    );
  });

  test('revalida minimização após enumerar fontes', () async {
    final backend = FakeWindowBackend()..window = readyWindow;
    backend.onResolve = () {
      if (backend.resolveCalls == 1) backend.window = minimizedWindow;
    };
    expect(
      await waiter(
        backend,
      ).resolve(onWaiting: () => backend.window = readyWindow),
      '123',
    );
    expect(backend.resolveCalls, 2);
  });

  test('aguarda fonte real em vez de fabricar sourceId', () async {
    final backend = FakeWindowBackend()
      ..window = readyWindow
      ..resolvedId = null;
    expect(
      await waiter(
        backend,
      ).resolve(onWaiting: () => backend.resolvedId = 'real-source'),
      'real-source',
    );
    expect(backend.resolveCalls, 2);
  });

  test('janela fechada ou PID diferente termina a espera', () async {
    final backend = FakeWindowBackend()
      ..window = const NativeShareWindowState(
        valid: false,
        visible: false,
        minimized: false,
        foreground: false,
      );
    await expectLater(
      waiter(backend).resolve(onWaiting: () {}),
      throwsA(failure(WindowShareWaitFailure.closed)),
    );
    expect(backend.resolveCalls, 0);
  });

  test('prazo único limita espera', () async {
    await expectLater(
      waiter(FakeWindowBackend()).resolve(onWaiting: () {}),
      throwsA(failure(WindowShareWaitFailure.timeout)),
    );
  });

  test(
    'cancelamento interrompe consulta travada e ignora resposta tardia',
    () async {
      final answer = Completer<NativeShareWindowState>();
      final backend = FakeWindowBackend()..onRead = () => answer.future;
      final pending = waiter(backend);
      final result = pending.resolve(onWaiting: () => fail('Cancelado'));
      pending.cancel();
      await expectLater(
        result,
        throwsA(failure(WindowShareWaitFailure.cancelled)),
      );
      answer.complete(readyWindow);
      await pumpEventQueue();
      expect(backend.resolveCalls, 0);
    },
  );

  test('consulta travada também expira', () async {
    final backend = FakeWindowBackend()
      ..onRead = () => Completer<NativeShareWindowState>().future;
    await expectLater(
      waiter(backend).resolve(onWaiting: () {}),
      throwsA(failure(WindowShareWaitFailure.timeout)),
    );
  });
}
