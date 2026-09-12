import 'user.dart';

enum ChatMessageKind {
  text,
  gif;

  static ChatMessageKind fromApi(Object? value) {
    return switch (value) {
      'GIF' => ChatMessageKind.gif,
      _ => ChatMessageKind.text,
    };
  }

  String get apiValue => switch (this) {
    ChatMessageKind.text => 'TEXT',
    ChatMessageKind.gif => 'GIF',
  };
}

class MessageReplyPreview {
  const MessageReplyPreview({
    required this.id,
    required this.content,
    required this.kind,
    required this.createdAt,
    required this.author,
    this.gifUrl,
  });

  factory MessageReplyPreview.fromJson(Map<String, dynamic> json) =>
      MessageReplyPreview(
        id: json['id'] as String,
        content: json['content'] as String? ?? '',
        kind: ChatMessageKind.fromApi(json['kind']),
        gifUrl: json['gifUrl'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        author: _parseMessageAuthor(json['author']),
      );

  final String id;
  final String content;
  final ChatMessageKind kind;
  final String? gifUrl;
  final DateTime createdAt;
  final User author;
}

class MessageReaction {
  const MessageReaction({
    required this.id,
    required this.emoji,
    required this.userId,
    required this.createdAt,
    this.user,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) =>
      MessageReaction(
        id: json['id'] as String,
        emoji: json['emoji'] as String,
        userId: json['userId'] as String,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        user: json['user'] is Map<String, dynamic>
            ? User.fromJson(json['user'] as Map<String, dynamic>)
            : null,
      );

  final String id;
  final String emoji;
  final String userId;
  final DateTime createdAt;
  final User? user;
}

class MessageMention {
  const MessageMention({required this.userId, required this.user});

  factory MessageMention.fromJson(Map<String, dynamic> json) => MessageMention(
    userId: json['userId'] as String,
    user: User.fromJson(json['user'] as Map<String, dynamic>),
  );

  final String userId;
  final User user;
}

/// Mensagem de canal de texto — `GET/POST /channels/:id/messages` e evento
/// `message.created`/`message.updated` do socket.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.channelId,
    required this.content,
    required this.kind,
    required this.author,
    required this.createdAt,
    this.gifUrl,
    this.replyTo,
    this.reactions = const [],
    this.mentions = const [],
    this.updatedAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    channelId: json['channelId'] as String,
    content: json['content'] as String? ?? '',
    kind: ChatMessageKind.fromApi(json['kind']),
    gifUrl: json['gifUrl'] as String?,
    author: _parseMessageAuthor(json['author']),
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    replyTo: json['replyTo'] is Map<String, dynamic>
        ? MessageReplyPreview.fromJson(json['replyTo'] as Map<String, dynamic>)
        : null,
    reactions: (json['reactions'] as List<dynamic>? ?? const [])
        .map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
        .toList(),
    mentions: (json['mentions'] as List<dynamic>? ?? const [])
        .map((e) => MessageMention.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String channelId;
  final String content;
  final ChatMessageKind kind;
  final String? gifUrl;
  final MessageReplyPreview? replyTo;
  final List<MessageReaction> reactions;
  final List<MessageMention> mentions;
  final User author;
  final DateTime createdAt;

  /// Nulo enquanto a mensagem nunca foi editada.
  final DateTime? updatedAt;
}

User _parseMessageAuthor(Object? value) {
  if (value is Map<String, dynamic>) {
    return User.fromJson(value);
  }
  return const User(
    id: 'deleted-user',
    name: 'Usuário removido',
    username: 'deleted',
  );
}

/// Página de mensagens — `GET /channels/:id/messages?limit=50&before=<id>`
/// → `{ messages: [...], nextCursor }`.
class MessagePage {
  const MessagePage({required this.messages, this.nextCursor});

  final List<ChatMessage> messages;

  /// Cursor para a próxima página (mais antiga); nulo quando não há mais.
  final String? nextCursor;
}
