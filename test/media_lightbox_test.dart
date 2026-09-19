import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/ui/app_file_image.dart';
import 'package:fourfun_cod_client/core/ui/media_lightbox.dart';

// PNG 1x1 transparente — bytes válidos para Image.memory nos testes.
final _png1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

List<Override> _bytesOverrides(List<String> paths) {
  return [
    for (final path in paths)
      fileImageBytesProvider(
        'http://localhost:3000$path',
      ).overrideWith((ref) async => _png1x1),
  ];
}

Future<void> _openViewer(
  WidgetTester tester, {
  required List<MediaItem> items,
  int initialIndex = 0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: _bytesOverrides(
        items
            .expand((item) => [item.url, if (item.previewUrl != null) item.previewUrl!])
            .where((url) => url.startsWith('/'))
            .toList(),
      ),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMediaLightbox(
                context: context,
                items: items,
                initialIndex: initialIndex,
                authorName: 'Iscudina',
                sentAt: DateTime(2026, 9, 18, 18, 30),
                channelName: 'chat',
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('viewer exibe header avatar+nome+timestamp e toolbar', (
    tester,
  ) async {
    await _openViewer(
      tester,
      items: const [MediaItem(url: '/api/v1/files/img-1')],
    );

    expect(find.text('Iscudina'), findsOneWidget);
    expect(find.textContaining('18/09/2026'), findsOneWidget);
    expect(find.text('# chat'), findsOneWidget);
    expect(find.byTooltip('Ampliar zoom'), findsOneWidget);
    expect(find.byTooltip('Reduzir zoom'), findsOneWidget);
    expect(find.byTooltip('Copiar imagem'), findsOneWidget);
    expect(find.byTooltip('Salvar imagem'), findsOneWidget);
    expect(find.byTooltip('Abrir original'), findsNothing);
    expect(find.byTooltip('Fechar (Esc)'), findsOneWidget);
    // Item único: sem setas nem contador.
    expect(find.textContaining(' de '), findsNothing);
  });

  testWidgets('multi-anexos navegam com setas e contador', (tester) async {
    await _openViewer(
      tester,
      items: const [
        MediaItem(url: '/api/v1/files/img-1'),
        MediaItem(url: '/api/v1/files/img-2'),
      ],
    );

    expect(find.text('1 de 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Próxima'));
    await tester.pumpAndSettle();
    expect(find.text('2 de 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Anterior'));
    await tester.pumpAndSettle();
    expect(find.text('1 de 2'), findsOneWidget);
  });

  testWidgets('gif mostra badge e alterna play/pause', (tester) async {
    await _openViewer(
      tester,
      items: const [
        MediaItem(
          url: '/api/v1/files/anim.gif',
          kind: MediaKind.gif,
          previewUrl: '/api/v1/files/anim-preview.png',
        ),
      ],
    );

    expect(find.text('GIF'), findsOneWidget);
    expect(find.byTooltip('Pausar GIF'), findsOneWidget);

    await tester.tap(find.byTooltip('Pausar GIF'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Reproduzir GIF'), findsOneWidget);
  });

  testWidgets('zoom in mostra o percentual e o reset no header', (
    tester,
  ) async {
    await _openViewer(
      tester,
      items: const [MediaItem(url: '/api/v1/files/img-1')],
    );

    // Pill limpa em 100%: sem % e sem reset.
    expect(find.text('100%'), findsNothing);
    expect(find.byTooltip('Resetar zoom (100%)'), findsNothing);

    await tester.tap(find.byTooltip('Ampliar zoom'));
    await tester.pump();
    expect(find.text('125%'), findsOneWidget);
    expect(find.byTooltip('Resetar zoom (100%)'), findsOneWidget);

    await tester.tap(find.byTooltip('Resetar zoom (100%)'));
    await tester.pump();
    expect(find.text('100%'), findsNothing);
    expect(find.byTooltip('Resetar zoom (100%)'), findsNothing);
  });
}
