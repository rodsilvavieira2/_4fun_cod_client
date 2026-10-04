import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/native/native_media_backend.dart';
import 'package:fourfun_cod_client/core/rtc/screen_share_picker.dart';

class _FakeBackend implements NativeScreenShareBackend {
  _FakeBackend(this.load);

  final Future<List<RtcScreenShareSource>> Function() load;

  @override
  ScreenShareCapabilities get capabilities => const ScreenShareCapabilities(
    usesSystemPicker: false,
    supportsWindowSources: true,
    supportsSystemAudio: true,
  );

  @override
  Future<List<RtcScreenShareSource>> loadSources() => load();

  @override
  bool canUseKind(RtcScreenShareSourceKind kind) => true;

  @override
  String? disabledReasonFor(RtcScreenShareSourceKind kind) => null;
}

typedef _Diagnostic = ({String name, Map<String, String> attributes});

Future<void> _openPicker(
  WidgetTester tester, {
  required NativeScreenShareBackend backend,
  required List<_Diagnostic> events,
  required void Function(Future<RtcScreenShareSelection?>) onResult,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => onResult(
              RtcScreenSharePicker.show(
                context,
                backend: backend,
                initialKind: RtcScreenShareSourceKind.display,
                onDiagnosticEvent: (name, attributes) =>
                    events.add((name: name, attributes: attributes)),
              ),
            ),
            child: const Text('Abrir seletor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir seletor'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('minimizada retorna identidade local sem fabricar fonte RTC', (
    tester,
  ) async {
    final events = <_Diagnostic>[];
    RtcScreenShareSelection? selection;
    const target = NativeShareWindowTarget('123', 456);
    await _openPicker(
      tester,
      backend: _FakeBackend(
        () async => const [
          RtcScreenShareSource(
            id: '123',
            name: 'Jogo de teste',
            kind: RtcScreenShareSourceKind.window,
            minimized: true,
            windowTarget: target,
          ),
        ],
      ),
      events: events,
      onResult: (future) => future.then((value) => selection = value),
    );
    await tester.tap(find.text('Janela'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jogo de teste · Minimizada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();
    expect(selection?.sourceId, isNull);
    expect(selection?.windowTarget, target);
    expect(selection?.attemptId, events.first.attributes['attempt_id']);
    expect(events.last.attributes['minimized'], 'true');
    expect(events.toString(), isNot(contains('Jogo de teste')));
    expect(events.toString(), isNot(contains('456')));
  });
  testWidgets('registra contagens, aba e seleção sem dados da fonte', (
    tester,
  ) async {
    final events = <_Diagnostic>[];
    RtcScreenShareSelection? selection;
    final backend = _FakeBackend(
      () async => const [
        RtcScreenShareSource(
          id: 'window:123',
          name: 'Jogo privado',
          kind: RtcScreenShareSourceKind.window,
        ),
        RtcScreenShareSource(
          id: 'screen:456',
          name: 'Display pessoal',
          kind: RtcScreenShareSourceKind.display,
        ),
      ],
    );

    await _openPicker(
      tester,
      backend: backend,
      events: events,
      onResult: (future) => future.then((value) => selection = value),
    );

    final opened = events.singleWhere(
      (event) => event.name == 'screen_share.picker.opened',
    );
    final loaded = events.singleWhere(
      (event) => event.name == 'screen_share.picker.sources_loaded',
    );
    expect(loaded.attributes['attempt_id'], opened.attributes['attempt_id']);
    expect(loaded.attributes['window_count'], '1');
    expect(loaded.attributes['display_count'], '1');
    expect(loaded.attributes['active_kind'], 'display');
    expect(loaded.attributes['visible_count'], '1');

    await tester.tap(find.text('Janela'));
    await tester.pumpAndSettle();
    expect(
      events
          .singleWhere(
            (event) => event.name == 'screen_share.picker.tab_changed',
          )
          .attributes['kind'],
      'window',
    );

    await tester.tap(find.text('Jogo privado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();

    expect(selection?.sourceId, 'window:123');
    expect(
      events
          .singleWhere(
            (event) => event.name == 'screen_share.picker.source_selected',
          )
          .attributes['kind'],
      'window',
    );
    expect(events.toString(), isNot(contains('Jogo privado')));
    expect(events.toString(), isNot(contains('window:123')));
  });

  testWidgets('registra falha, retry e cancelamento', (tester) async {
    final events = <_Diagnostic>[];
    var calls = 0;
    RtcScreenShareSelection? selection;
    final backend = _FakeBackend(() async {
      if (++calls == 1) throw StateError('segredo da exceção');
      return const [];
    });

    await _openPicker(
      tester,
      backend: backend,
      events: events,
      onResult: (future) => future.then((value) => selection = value),
    );

    final failed = events.singleWhere(
      (event) => event.name == 'screen_share.picker.sources_failed',
    );
    expect(failed.attributes['load_attempt'], '1');
    expect(failed.attributes['error_type'], 'StateError');
    expect(events.toString(), isNot(contains('segredo da exceção')));

    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();
    final loaded = events.singleWhere(
      (event) => event.name == 'screen_share.picker.sources_loaded',
    );
    expect(loaded.attributes['load_attempt'], '2');
    expect(loaded.attributes['window_count'], '0');
    expect(
      events
          .lastWhere(
            (event) => event.name == 'screen_share.picker.sources_started',
          )
          .attributes['reason'],
      'retry',
    );

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(selection, isNull);
    expect(
      events
          .singleWhere((event) => event.name == 'screen_share.picker.cancelled')
          .attributes['attempt_id'],
      failed.attributes['attempt_id'],
    );
  });
}
