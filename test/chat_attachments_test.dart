import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/storage/chat_attachments.dart';
import 'package:fourfun_cod_client/shared/models/message.dart';

void main() {
  group('validateAttachmentFile', () {
    test('aceita qualquer arquivo até 61 MB', () {
      expect(
        validateAttachmentFile(
          fileName: 'video.mp4',
          sizeBytes: 60 * 1024 * 1024,
          currentCount: 0,
        ),
        isNull,
      );
      expect(
        validateAttachmentFile(
          fileName: 'doc.pdf',
          sizeBytes: 1024,
          currentCount: 9,
        ),
        isNull,
      );
    });

    test('rejeita > 61 MB com mensagem em pt-BR', () {
      final error = validateAttachmentFile(
        fileName: 'filme.mkv',
        sizeBytes: 61 * 1024 * 1024 + 1,
        currentCount: 0,
      );
      expect(error, contains('61 MB'));
      expect(error, contains('filme.mkv'));
    });

    test('aceita exatamente 61 MB (fronteira)', () {
      expect(
        validateAttachmentFile(
          fileName: 'limite.zip',
          sizeBytes: 61 * 1024 * 1024,
          currentCount: 0,
        ),
        isNull,
      );
    });

    test('rejeita vazio, sem nome e além de 10', () {
      expect(
        validateAttachmentFile(
          fileName: 'x.txt',
          sizeBytes: 0,
          currentCount: 0,
        ),
        contains('vazio'),
      );
      expect(
        validateAttachmentFile(
          fileName: '   ',
          sizeBytes: 10,
          currentCount: 0,
        ),
        contains('sem nome'),
      );
      expect(
        validateAttachmentFile(
          fileName: 'a.txt',
          sizeBytes: 10,
          currentCount: 10,
        ),
        contains('10 anexos'),
      );
    });
  });

  group('contentTypeForAnyFile', () {
    test('imagens mantêm mime de imagem', () {
      expect(contentTypeForAnyFile('foto.jpg'), 'image/jpeg');
      expect(contentTypeForAnyFile('FOTO.PNG'), 'image/png');
      expect(contentTypeForAnyFile('anim.webp'), 'image/webp');
      expect(contentTypeForAnyFile('meme.gif'), 'image/gif');
    });

    test('genéricos comuns e fallback octet-stream', () {
      expect(contentTypeForAnyFile('doc.pdf'), 'application/pdf');
      expect(contentTypeForAnyFile('pacote.zip'), 'application/zip');
      expect(contentTypeForAnyFile('video.mp4'), 'video/mp4');
      expect(contentTypeForAnyFile('sem-extensao'), 'application/octet-stream');
      expect(contentTypeForAnyFile('estranho.xyz123'), 'application/octet-stream');
    });
  });

  group('formatFileSize', () {
    test('B, KB e MB', () {
      expect(formatFileSize(512), '512 B');
      expect(formatFileSize(2048), '2 KB');
      expect(formatFileSize(12 * 1024 * 1024 + 512 * 1024), contains('MB'));
    });
  });

  group('MessageAttachment.isImage', () {
    MessageAttachment att({String? fileName, String? mime, String? url}) {
      return MessageAttachment(
        id: 'a1',
        uploadId: 'u1',
        url: url,
        width: null,
        height: null,
        status: 'READY',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        fileName: fileName,
        mimeType: mime,
      );
    }

    test('mime image/* é imagem mesmo sem extensão', () {
      expect(att(mime: 'image/png').isImage, isTrue);
    });

    test('pdf/zip/mp4 não são imagem', () {
      expect(att(fileName: 'doc.pdf', mime: 'application/pdf').isImage, isFalse);
      expect(att(fileName: 'p.zip', mime: 'application/zip').isImage, isFalse);
    });

    test('legado sem metadados: cai p/ extensão da url', () {
      expect(att(url: '/api/v1/files/attachments/x.webp').isImage, isTrue);
      expect(att(url: '/api/v1/files/attachments/x.bin').isImage, isFalse);
    });
  });

  group('ChatMessageKind.file', () {
    test('fromApi/toApi round-trip FILE', () {
      expect(ChatMessageKind.fromApi('FILE'), ChatMessageKind.file);
      expect(ChatMessageKind.file.apiValue, 'FILE');
      expect(ChatMessageKind.fromApi('IMAGE'), ChatMessageKind.image);
    });
  });

  group('stripPastedPaths', () {
    test('remove path exato colado e mantém texto digitado', () {
      expect(
        stripPastedPaths(
          'olha isso /home/rodrigo/Pictures/Screenshot-10.png',
          ['/home/rodrigo/Pictures/Screenshot-10.png'],
        ),
        'olha isso',
      );
    });

    test('input só com o path vira vazio', () {
      expect(
        stripPastedPaths(
          '/home/rodrigo/Pictures/Screenshot-10.png',
          ['/home/rodrigo/Pictures/Screenshot-10.png'],
        ),
        isEmpty,
      );
    });

    test('cobre file://, aspas e um por linha', () {
      expect(
        stripPastedPaths(
          '"/home/a/b.png"\nfile:///home/a/b.png\ntexto',
          ['/home/a/b.png'],
        ),
        'texto',
      );
    });

    test('sem paths não toca em nada (cola só-texto)', () {
      expect(stripPastedPaths('oi mundo', []), 'oi mundo');
    });
  });

  group('parseFilePathsFromText', () {
    bool Function(String) exists(Set<String> files) =>
        (String p) => files.contains(p);

    test('path absoluto existente', () {
      expect(
        parseFilePathsFromText(
          '/home/rodrigo/Pictures/Screenshot-10.png',
          exists: exists({'/home/rodrigo/Pictures/Screenshot-10.png'}),
        ),
        ['/home/rodrigo/Pictures/Screenshot-10.png'],
      );
    });

    test('path com espaço entre aspas + file:// com %20', () {
      expect(
        parseFilePathsFromText(
          '"/home/a/Screenshot From 2026.png"\nfile:///home/a/outro%20doc.pdf',
          exists: exists({
            '/home/a/Screenshot From 2026.png',
            '/home/a/outro doc.pdf',
          }),
        ),
        ['/home/a/Screenshot From 2026.png', '/home/a/outro doc.pdf'],
      );
    });

    test('texto misto nunca é tocado (ex. snippet com /etc/hosts)', () {
      expect(
        parseFilePathsFromText(
          'edite /etc/hosts e rode o server',
          exists: exists({'/etc/hosts'}),
        ),
        isEmpty,
      );
    });

    test('relativo e inexistente → []', () {
      expect(
        parseFilePathsFromText('docs/x.png', exists: exists({'docs/x.png'})),
        isEmpty,
      );
      expect(
        parseFilePathsFromText('/sumiu.png', exists: (_) => false),
        isEmpty,
      );
      expect(parseFilePathsFromText('   \n  '), isEmpty);
    });

    test('drive Windows', () {
      expect(
        parseFilePathsFromText(
          r'C:\Users\ana\foto.png',
          exists: exists({r'C:\Users\ana\foto.png'}),
        ),
        [r'C:\Users\ana\foto.png'],
      );
    });
  });

  group('PendingAttachment', () {
    test('isImage por extensão; sizeBytes do buffer', () {
      final img = PendingAttachment(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'foto.png',
        contentType: 'image/png',
      );
      expect(img.isImage, isTrue);
      expect(img.sizeBytes, 3);
      final doc = PendingAttachment(
        bytes: Uint8List.fromList([1]),
        fileName: 'relatorio.pdf',
        contentType: 'application/pdf',
      );
      expect(doc.isImage, isFalse);
    });
  });
}
