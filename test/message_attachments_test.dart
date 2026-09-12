import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/shared/models/message.dart';

void main() {
  group('ChatMessageKind', () {
    test('mapeia IMAGE; desconhecido cai em text', () {
      expect(ChatMessageKind.fromApi('IMAGE'), ChatMessageKind.image);
      expect(ChatMessageKind.fromApi('GIF'), ChatMessageKind.gif);
      expect(ChatMessageKind.fromApi('TEXT'), ChatMessageKind.text);
      expect(ChatMessageKind.fromApi('VIDEO'), ChatMessageKind.text);
      expect(ChatMessageKind.fromApi(null), ChatMessageKind.text);
      expect(ChatMessageKind.image.apiValue, 'IMAGE');
    });
  });

  group('MessageAttachment', () {
    test('parseia url/dimensões/status do upload aninhado', () {
      final attachment = MessageAttachment.fromJson({
        'id': 'att-1',
        'uploadId': 'up-1',
        'url': null,
        'width': null,
        'height': null,
        'createdAt': '2026-09-12T12:00:00.000Z',
        'upload': {
          'status': 'READY',
          'finalUrl': '/api/v1/files/attachments/ch-1/x.webp',
        },
      });

      expect(attachment.url, '/api/v1/files/attachments/ch-1/x.webp');
      expect(attachment.status, 'READY');
    });

    test('sem upload aninhado assume PENDING; aspectRatio default é 1', () {
      final attachment = MessageAttachment.fromJson({
        'id': 'att-1',
        'uploadId': 'up-1',
        'url': null,
        'width': null,
        'height': null,
        'createdAt': '2026-09-12T12:00:00.000Z',
      });

      expect(attachment.status, 'PENDING');
      expect(attachment.aspectRatio, 1);
    });

    test('aspectRatio usa width/height reais', () {
      final attachment = MessageAttachment.fromJson({
        'id': 'att-1',
        'uploadId': 'up-1',
        'url': '/api/v1/files/attachments/ch-1/x.webp',
        'width': 800,
        'height': 600,
        'createdAt': '2026-09-12T12:00:00.000Z',
        'upload': {'status': 'READY', 'finalUrl': null},
      });

      expect(attachment.aspectRatio, closeTo(800 / 600, 0.001));
      // url própria vence sobre a do upload
      expect(attachment.url, '/api/v1/files/attachments/ch-1/x.webp');
    });
  });

  group('ChatMessage.attachments', () {
    test('parseia lista; ausente vira []', () {
      final withAttachments = ChatMessage.fromJson(
        _messageJson(
          attachments: [
            {
              'id': 'att-1',
              'uploadId': 'up-1',
              'url': null,
              'width': null,
              'height': null,
              'createdAt': '2026-09-12T12:00:00.000Z',
              'upload': {'status': 'PENDING', 'finalUrl': null},
            },
          ],
        ),
      );

      expect(withAttachments.kind, ChatMessageKind.image);
      expect(withAttachments.attachments, hasLength(1));
      expect(withAttachments.attachments.first.status, 'PENDING');

      final without = ChatMessage.fromJson(_messageJson());
      expect(without.attachments, isEmpty);
    });
  });
}

Map<String, dynamic> _messageJson({List<Map<String, dynamic>>? attachments}) {
  final json = <String, dynamic>{
    'id': 'msg-1',
    'channelId': 'ch-1',
    'content': '',
    'kind': 'IMAGE',
    'author': {'id': 'user-1', 'username': 'ana', 'name': 'Ana'},
    'createdAt': '2026-09-12T12:00:00.000Z',
  };
  final list = attachments;
  if (list != null) json['attachments'] = list;
  return json;
}
