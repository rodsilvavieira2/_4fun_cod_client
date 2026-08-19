import 'user.dart';

/// Tipo de canal de servidor (espelho do enum do backend).
enum ChannelType { text, voice }

/// Canal de texto/voz de um servidor.
class ServerChannel {
  const ServerChannel({
    required this.id,
    required this.name,
    required this.type,
  });

  factory ServerChannel.fromJson(Map<String, dynamic> json) => ServerChannel(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] == 'VOICE' ? ChannelType.voice : ChannelType.text,
      );

  final String id;
  final String name;
  final ChannelType type;

  String get icon => type == ChannelType.voice ? '🔊' : '#';
}

/// Servidor espelhado da API — `GET /servers` inclui `channels` e
/// `myRole`; `POST /servers` retorna apenas o servidor criado (campos
/// opcionais cobrem ambos os formatos).
class Server {
  const Server({
    required this.id,
    required this.name,
    this.iconUrl,
    this.createdAt,
    this.channels = const [],
    this.myRole,
  });

  factory Server.fromJson(Map<String, dynamic> json) => Server(
        id: json['id'] as String,
        name: json['name'] as String,
        iconUrl: json['iconUrl'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
        channels: (json['channels'] as List<dynamic>? ?? const [])
            .map((e) => ServerChannel.fromJson(e as Map<String, dynamic>))
            .toList(),
        myRole: json['myRole'] as String?,
      );

  final String id;
  final String name;
  final String? iconUrl;
  final DateTime? createdAt;

  /// Canais embutidos na listagem (`GET /servers`).
  final List<ServerChannel> channels;

  /// Papel do usuário atual ('OWNER' | 'MEMBER') — ausente em respostas de
  /// criação.
  final String? myRole;

  bool get isOwner => myRole == 'OWNER';
}

/// Membro de servidor — `GET /servers/:id/members`.
class ServerMember {
  const ServerMember({
    required this.id,
    required this.userId,
    required this.role,
    required this.joinedAt,
    required this.user,
  });

  factory ServerMember.fromJson(Map<String, dynamic> json) => ServerMember(
        id: json['id'] as String,
        userId: json['userId'] as String,
        role: json['role'] as String,
        joinedAt: DateTime.tryParse(json['joinedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        user: User.fromJson(json['user'] as Map<String, dynamic>),
      );

  final String id;
  final String userId;
  final String role;
  final DateTime joinedAt;
  final User user;

  bool get isOwner => role == 'OWNER';
}

/// Convite criado — `POST /servers/:id/invites`.
class InviteInfo {
  const InviteInfo({
    required this.code,
    required this.url,
    this.expiresAt,
    this.maxUses,
    this.uses,
  });

  factory InviteInfo.fromJson(Map<String, dynamic> json) => InviteInfo(
        code: json['code'] as String,
        url: json['url'] as String,
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
        maxUses: json['maxUses'] as int?,
        uses: json['uses'] as int?,
      );

  final String code;
  final String url;
  final DateTime? expiresAt;
  final int? maxUses;
  final int? uses;
}

/// Servidor público embutido na resolução de convite —
/// `GET /invites/:code` (`server.memberCount`).
class InviteServer {
  const InviteServer({
    required this.id,
    required this.name,
    this.iconUrl,
    this.memberCount = 0,
  });

  factory InviteServer.fromJson(Map<String, dynamic> json) => InviteServer(
        id: json['id'] as String,
        name: json['name'] as String,
        iconUrl: json['iconUrl'] as String?,
        memberCount: json['memberCount'] as int? ?? 0,
      );

  final String id;
  final String name;
  final String? iconUrl;
  final int memberCount;
}

/// Resposta de `GET /invites/:code`.
class InviteDetail {
  const InviteDetail({required this.invite, required this.server});

  factory InviteDetail.fromJson(Map<String, dynamic> json) => InviteDetail(
        invite: InviteInfo.fromJson(json['invite'] as Map<String, dynamic>),
        server: InviteServer.fromJson(json['server'] as Map<String, dynamic>),
      );

  final InviteInfo invite;
  final InviteServer server;
}

/// Detalhe de servidor — `GET /servers/:id` → `{server, channels,
/// members, myRole}`.
class ServerDetail {
  const ServerDetail({
    required this.server,
    required this.channels,
    required this.members,
    this.myRole,
  });

  factory ServerDetail.fromJson(Map<String, dynamic> json) => ServerDetail(
        server: Server.fromJson(json['server'] as Map<String, dynamic>),
        channels: (json['channels'] as List<dynamic>? ?? const [])
            .map((e) => ServerChannel.fromJson(e as Map<String, dynamic>))
            .toList(),
        members: (json['members'] as List<dynamic>? ?? const [])
            .map((e) => ServerMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        myRole: json['myRole'] as String?,
      );

  final Server server;
  final List<ServerChannel> channels;
  final List<ServerMember> members;
  final String? myRole;

  bool get isOwner => myRole == 'OWNER';
}

/// Presença do servidor — `GET /servers/:id/presence` →
/// `{ online: string[], voiceByChannel: { channelId: string[] } }`.
/// Estado efêmero (Redis, TTL 60s), NUNCA persistido.
class ServerPresence {
  const ServerPresence({
    required this.online,
    this.voiceByChannel = const {},
  });

  factory ServerPresence.fromJson(Map<String, dynamic> json) => ServerPresence(
        online: {
          ...(json['online'] as List<dynamic>? ?? const []).cast<String>(),
        },
        voiceByChannel: (json['voiceByChannel'] as Map<String, dynamic>? ??
                const {})
            .map(
              (channelId, userIds) => MapEntry(
                channelId,
                (userIds as List<dynamic>).cast<String>(),
              ),
            ),
      );

  /// Ids dos usuários online no servidor.
  final Set<String> online;

  /// Ids dos usuários em voz, agrupados por canal (usado na Fase 4).
  final Map<String, List<String>> voiceByChannel;
}
