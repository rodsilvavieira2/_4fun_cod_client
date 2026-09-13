import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/ui/app_file_image.dart';
import 'package:fourfun_cod_client/core/ui/message_image_grid.dart';
import 'package:fourfun_cod_client/shared/models/message.dart';

MessageAttachment _attachment({
  String status = 'PENDING',
  String? url,
  int? width,
  int? height,
}) {
  return MessageAttachment.fromJson({
    'id': 'att-1',
    'uploadId': 'up-1',
    'url': url,
    'width': width,
    'height': height,
    'createdAt': '2026-09-12T12:00:00.000Z',
    'upload': {'status': status, 'finalUrl': null},
  });
}

/// Regressão: imagem única PENDING dentro do ListView do chat estourava
/// `BoxConstraints forces an infinite height` (RenderPositionedBox) e
/// envenenava o viewport — o chat parava de renderizar.
void main() {
  testWidgets('grid com 1 anexo monta dentro de ListView sem erro de layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                MessageImageGrid(attachments: [_attachment()]),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(MessageImageGrid), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('grid com vários anexos monta dentro de ListView', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                MessageImageGrid(
                  onRetry: (_) {},
                  attachments: [
                    _attachment(width: 800, height: 600),
                    _attachment(status: 'FAILED'),
                    _attachment(width: 100, height: 2000),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });

  testWidgets('botão direito na imagem READY abre menu copiar/salvar', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        // Sem rede no teste: bytes falsos direto no provider.
        overrides: [
          fileImageBytesProvider(
            'http://localhost:3000/api/v1/files/img-1',
          ).overrideWith((ref) async => Uint8List.fromList(const [1, 2, 3])),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                MessageImageGrid(
                  onOpen: (_) {},
                  attachments: [
                    _attachment(
                      status: 'READY',
                      url: '/api/v1/files/img-1',
                      width: 800,
                      height: 600,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    await tester.tap(
      find.byType(MessageImageGrid),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();

    expect(find.text('Copiar imagem'), findsOneWidget);
    expect(find.text('Salvar imagem'), findsOneWidget);
  });
}
