import 'user.dart';

/// Mensagem de canal de texto — `GET/POST /channels/:id/messages` e evento
/// `message.created`/`message.updated` do socket.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.content,
    required this.author,
    required this.createdAt,
    this.updatedAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    channelId: json['channelId'] as String,
    content: json['content'] as String,
    author: User.fromJson(json['author'] as Map<String, dynamic>),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );

  final String id;
  final String channelId;
  final String content;
  final User author;
  final DateTime createdAt;

  /// Nulo enquanto a mensagem nunca foi editada.
  final DateTime? updatedAt;
}

/// Página de mensagens — `GET /channels/:id/messages?limit=50&before=<id>`
/// → `{ messages: [...], nextCursor }`.
class MessagePage {
  const MessagePage({required this.messages, this.nextCursor});

  final List<ChatMessage> messages;

  /// Cursor para a próxima página (mais antiga); nulo quando não há mais.
  final String? nextCursor;
}
