import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/ui/app_file_image.dart';
import 'package:fourfun_cod_client/core/ui/message_image_grid.dart';
import 'package:fourfun_cod_client/core/ui/spoiler_overlay.dart';
import 'package:fourfun_cod_client/features/chat/chat_providers.dart';
import 'package:fourfun_cod_client/shared/models/message.dart';

MessageAttachment attachment({
  bool spoiler = false,
  String status = 'READY',
  String? url = '/api/v1/files/img-1',
}) {
  return MessageAttachment.fromJson({
    'id': 'att-1',
    'uploadId': 'up-1',
    'url': url,
    'width': 800,
    'height': 600,
    'createdAt': '2026-09-12T12:00:00.000Z',
    'spoiler': spoiler,
    'upload': {'status': status, 'finalUrl': null},
  });
}

void main() {
  group('MessageAttachment.isSpoiler', () {
    test('default false quando ausente', () {
      final a = MessageAttachment.fromJson({
        'id': 'att-1',
        'uploadId': 'up-1',
        'url': null,
        'width': null,
        'height': null,
        'createdAt': '2026-09-12T12:00:00.000Z',
      });
      expect(a.isSpoiler, isFalse);
    });

    test('lê spoiler/isSpoiler/is_spoiler e do upload aninhado', () {
      expect(attachment(spoiler: true).isSpoiler, isTrue);
      expect(attachment(spoiler: false).isSpoiler, isFalse);

      MessageAttachment parse(Map<String, dynamic> json) =>
          MessageAttachment.fromJson({
            'id': 'att-1',
            'uploadId': 'up-1',
            'url': null,
            'width': null,
            'height': null,
            'createdAt': '2026-09-12T12:00:00.000Z',
            ...json,
          });

      expect(parse({'isSpoiler': true}).isSpoiler, isTrue);
      expect(parse({'is_spoiler': 1}).isSpoiler, isTrue);
      expect(
        parse({
          'upload': {'status': 'READY', 'spoiler': true},
        }).isSpoiler,
        isTrue,
      );
    });

    test('copyWith alterna o flag', () {
      final a = attachment(spoiler: false);
      expect(a.copyWith(isSpoiler: true).isSpoiler, isTrue);
    });
  });

  group('ChatImageSlot / ChatAttachmentMeta', () {
    test('copyWith preserva bytes e alterna spoiler', () {
      final slot = ChatImageSlot(
        bytes: Uint8List.fromList(const [1, 2, 3]),
        fileName: 'foto.png',
        contentType: 'image/png',
      );
      expect(slot.isSpoiler, isFalse);
      final toggled = slot.copyWith(isSpoiler: true);
      expect(toggled.isSpoiler, isTrue);
      expect(toggled.fileName, 'foto.png');
      final renamed = toggled.copyWith(fileName: 'nova.png');
      expect(renamed.fileName, 'nova.png');
      expect(renamed.isSpoiler, isTrue);
    });

    test('ChatAttachmentMeta.toJson', () {
      const meta = ChatAttachmentMeta(uploadId: 'up-1', spoiler: true);
      expect(meta.toJson(), {'uploadId': 'up-1', 'spoiler': true});
    });
  });

  group('MessageImageGrid spoiler', () {
    testWidgets('spoiler mostra badge e revela no 1º tap', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        ProviderScope(
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
                    attachments: [attachment(spoiler: true)],
                    onOpen: (_) => opened++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('SPOILER'), findsWidgets);
      expect(find.text('Clique para revelar'), findsOneWidget);
      expect(opened, 0);

      // 1º tap revela, não abre o lightbox.
      await tester.tap(find.byType(MessageImageGrid));
      await tester.pump();
      expect(find.text('Clique para revelar'), findsNothing);
      expect(opened, 0);

      // 2º tap abre o lightbox.
      await tester.tap(find.byType(MessageImageGrid));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('sem spoiler abre direto', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        ProviderScope(
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
                    attachments: [attachment(spoiler: false)],
                    onOpen: (_) => opened++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('SPOILER'), findsNothing);

      await tester.tap(find.byType(MessageImageGrid));
      await tester.pump();
      expect(opened, 1);
    });
  });

  group('SpoilerCover', () {
    testWidgets('renderiza badge + hint', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 120,
              child: SpoilerCover(child: ColoredBox(color: Colors.red)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('SPOILER'), findsOneWidget);
    });
  });
}
