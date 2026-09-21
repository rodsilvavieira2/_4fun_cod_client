import 'user.dart';

enum ChatMessageKind {
  text,
  gif,
  image;

  static ChatMessageKind fromApi(Object? value) {
    return switch (value) {
      'GIF' => ChatMessageKind.gif,
      'IMAGE' => ChatMessageKind.image,
      _ => ChatMessageKind.text,
    };
  }

  String get apiValue => switch (this) {
    ChatMessageKind.text => 'TEXT',
    ChatMessageKind.gif => 'GIF',
    ChatMessageKind.image => 'IMAGE',
  };
}

/// Anexo de imagem de uma mensagem (`MessageAttachment` do Prisma).
///
/// `url` é nulo enquanto o upload está PENDING/PROCESSING; `status` resolve
/// do `upload` aninhado (READY/FAILED) para o retry parcial por anexo.
/// `isSpoiler` borra a imagem até o usuário revelar (estilo Discord).
class MessageAttachment {
  const MessageAttachment({
    required this.id,
    required this.uploadId,
    required this.url,
    required this.width,
    required this.height,
    required this.status,
    required this.createdAt,
    this.isSpoiler = false,
  });

  final String id;
  final String uploadId;
  final String? url;
  final int? width;
  final int? height;

  /// `READY` | `PENDING` | `PROCESSING` | `FAILED` (default PENDING).
  final String status;
  final DateTime createdAt;

  /// Blur estilo Discord até revelar. Sessão local; persistido via API.
  final bool isSpoiler;

  /// Aspect ratio real (width/height) ou 1 enquanto sem dimensões.
  double get aspectRatio {
    if (width == null || height == null || height == 0) return 1;
    return width! / height!;
  }

  MessageAttachment copyWith({bool? isSpoiler}) {
    return MessageAttachment(
      id: id,
      uploadId: uploadId,
      url: url,
      width: width,
      height: height,
      status: status,
      createdAt: createdAt,
      isSpoiler: isSpoiler ?? this.isSpoiler,
    );
  }

  static bool _parseSpoiler(Map<String, dynamic> json) {
    for (final key in const ['spoiler', 'isSpoiler', 'is_spoiler']) {
      final value = json[key];
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final lower = value.toLowerCase();
        if (lower == 'true' || lower == '1') return true;
        if (lower == 'false' || lower == '0') return false;
      }
    }
    final upload = json['upload'];
    if (upload is Map<String, dynamic>) return _parseSpoiler(upload);
    return false;
  }

  factory MessageAttachment.fromJson(Map<String, dynamic> json) {
    final upload = json['upload'] as Map<String, dynamic>?;
    return MessageAttachment(
      id: json['id'] as String,
      uploadId: json['uploadId'] as String,
      url:
          (json['url'] as String?) ??
          (upload?['finalUrl'] as String?) ??
          (upload?['final_url'] as String?),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      status: (upload?['status'] as String?) ?? 'PENDING',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isSpoiler: _parseSpoiler(json),
    );
  }
}

/// Meta de anexo para `POST /messages`: id do upload + flag spoiler.
/// Mantém ordem dos slots (índice a índice com os `uploadIds`).
class ChatAttachmentMeta {
  const ChatAttachmentMeta({required this.uploadId, this.spoiler = false});

  final String uploadId;
  final bool spoiler;

  Map<String, Object?> toJson() => {'uploadId': uploadId, 'spoiler': spoiler};
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
    this.attachments = const [],
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
    attachments: (json['attachments'] as List<dynamic>? ?? const [])
        .map((e) => MessageAttachment.fromJson(e as Map<String, dynamic>))
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
  final List<MessageAttachment> attachments;
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
