import '../../shared/models/message.dart';
import '../../shared/models/servers.dart';

/// Evento de tempo real tipado, recebido do gateway Socket.IO do servidor.
///
/// [RealtimeEvent.fromJson] cobre apenas os eventos conhecidos do contrato
/// (Fase 3); tipos desconhecidos retornam `null` e são ignorados pelo
/// [SocketService] (nunca quebram o stream).
sealed class RealtimeEvent {
  const RealtimeEvent();

  static RealtimeEvent? fromJson(String type, Map<String, dynamic> json) {
    return switch (type) {
      'message.created' => MessageCreatedEvent.fromJson(json),
      'message.updated' => MessageUpdatedEvent.fromJson(json),
      'message.deleted' => MessageDeletedEvent.fromJson(json),
      'channel.created' => ChannelCreatedEvent.fromJson(json),
      'channel.updated' => ChannelUpdatedEvent.fromJson(json),
      'channel.deleted' => ChannelDeletedEvent.fromJson(json),
      'member.removed' => MemberRemovedEvent.fromJson(json),
      'member.left' => MemberRemovedEvent.fromJson(json),
      'member.role_updated' => MemberRoleUpdatedEvent.fromJson(json),
      'presence.changed' => PresenceChangedEvent.fromJson(json),
      'voice.presence.changed' => VoicePresenceChangedEvent.fromJson(json),
      _ => null,
    };
  }
}

/// `message.created { channelId, message }` — mensagem nova no canal.
class MessageCreatedEvent extends RealtimeEvent {
  const MessageCreatedEvent({required this.channelId, required this.message});

  factory MessageCreatedEvent.fromJson(Map<String, dynamic> json) =>
      MessageCreatedEvent(
        channelId: json['channelId'] as String,
        message: ChatMessage.fromJson(json['message'] as Map<String, dynamic>),
      );

  final String channelId;
  final ChatMessage message;
}

/// `message.updated { channelId, message }` — mensagem editada.
class MessageUpdatedEvent extends RealtimeEvent {
  const MessageUpdatedEvent({required this.channelId, required this.message});

  factory MessageUpdatedEvent.fromJson(Map<String, dynamic> json) =>
      MessageUpdatedEvent(
        channelId: json['channelId'] as String,
        message: ChatMessage.fromJson(json['message'] as Map<String, dynamic>),
      );

  final String channelId;
  final ChatMessage message;
}

/// `message.deleted { channelId, messageId }` — mensagem removida.
class MessageDeletedEvent extends RealtimeEvent {
  const MessageDeletedEvent({required this.channelId, required this.messageId});

  factory MessageDeletedEvent.fromJson(Map<String, dynamic> json) =>
      MessageDeletedEvent(
        channelId: json['channelId'] as String,
        messageId: json['messageId'] as String,
      );

  final String channelId;
  final String messageId;
}

/// `channel.created { serverId, channel }`.
class ChannelCreatedEvent extends RealtimeEvent {
  const ChannelCreatedEvent({required this.serverId, required this.channel});

  factory ChannelCreatedEvent.fromJson(Map<String, dynamic> json) =>
      ChannelCreatedEvent(
        serverId: json['serverId'] as String,
        channel: ServerChannel.fromJson(
          json['channel'] as Map<String, dynamic>,
        ),
      );

  final String serverId;
  final ServerChannel channel;
}

/// `channel.updated { serverId, channel }`.
class ChannelUpdatedEvent extends RealtimeEvent {
  const ChannelUpdatedEvent({required this.serverId, required this.channel});

  factory ChannelUpdatedEvent.fromJson(Map<String, dynamic> json) =>
      ChannelUpdatedEvent(
        serverId: json['serverId'] as String,
        channel: ServerChannel.fromJson(
          json['channel'] as Map<String, dynamic>,
        ),
      );

  final String serverId;
  final ServerChannel channel;
}

/// `channel.deleted { serverId, channelId }`.
class ChannelDeletedEvent extends RealtimeEvent {
  const ChannelDeletedEvent({required this.serverId, required this.channelId});

  factory ChannelDeletedEvent.fromJson(Map<String, dynamic> json) =>
      ChannelDeletedEvent(
        serverId: json['serverId'] as String,
        channelId: json['channelId'] as String,
      );

  final String serverId;
  final String channelId;
}

/// `member.removed { serverId, userId }` — membro removido do servidor.
class MemberRemovedEvent extends RealtimeEvent {
  const MemberRemovedEvent({required this.serverId, required this.userId});

  factory MemberRemovedEvent.fromJson(Map<String, dynamic> json) =>
      MemberRemovedEvent(
        serverId: json['serverId'] as String,
        userId: json['userId'] as String,
      );

  final String serverId;
  final String userId;
}

/// `member.role_updated { serverId, userId, role }`.
class MemberRoleUpdatedEvent extends RealtimeEvent {
  const MemberRoleUpdatedEvent({
    required this.serverId,
    required this.userId,
    required this.role,
  });

  factory MemberRoleUpdatedEvent.fromJson(Map<String, dynamic> json) =>
      MemberRoleUpdatedEvent(
        serverId: json['serverId'] as String,
        userId: json['userId'] as String,
        role: ServerRole.fromApi(json['role']) ?? ServerRole.member,
      );

  final String serverId;
  final String userId;
  final ServerRole role;
}

/// Status de presença de um usuário (espelho do enum do backend).
enum PresenceStatus { online, offline }

/// `presence.changed { userId, status: ONLINE|OFFLINE }` — presença efêmera
/// do servidor (Redis, TTL 60s + heartbeat).
class PresenceChangedEvent extends RealtimeEvent {
  const PresenceChangedEvent({required this.userId, required this.status});

  factory PresenceChangedEvent.fromJson(Map<String, dynamic> json) =>
      PresenceChangedEvent(
        userId: json['userId'] as String,
        status: json['status'] == 'ONLINE'
            ? PresenceStatus.online
            : PresenceStatus.offline,
      );

  final String userId;
  final PresenceStatus status;
}

/// `voice.presence.changed` mantém os ocupantes dos canais de voz da
/// sidebar sincronizados com o mirror LiveKit do servidor.
class VoicePresenceChangedEvent extends RealtimeEvent {
  const VoicePresenceChangedEvent({
    required this.serverId,
    required this.channelId,
    required this.userId,
    required this.connected,
  });

  factory VoicePresenceChangedEvent.fromJson(Map<String, dynamic> json) =>
      VoicePresenceChangedEvent(
        serverId: json['serverId'] as String,
        channelId: json['channelId'] as String,
        userId: json['userId'] as String,
        connected: json['connected'] == true,
      );

  final String serverId;
  final String channelId;
  final String userId;
  final bool connected;
}
