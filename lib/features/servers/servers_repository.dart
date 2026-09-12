import 'package:dio/dio.dart';

import '../../core/api/api_exception.dart';
import '../../core/storage/uploads_client.dart';
import '../../shared/models/message.dart';
import '../../shared/models/servers.dart';
import '../../shared/models/voice.dart';

/// Repositório de servidores/canais/convites (§6.2 do plano) — único lugar
/// que fala com o backend via dio (a UI usa apenas [ServersRepository] e os
/// providers de `features/servers`).
class ServersRepository {
  ServersRepository(this._dio);

  final Dio _dio;

  Future<List<Server>> fetchServers() async {
    try {
      final response = await _dio.get('/servers');
      final list = response.data as List<dynamic>;
      return list
          .map((e) => Server.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `POST /servers { name }` → 201 com o servidor criado.
  Future<Server> createServer(String name) async {
    try {
      final response = await _dio.post('/servers', data: {'name': name});
      return Server.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `GET /servers/:id` → detalhe com canais, membros e papel do usuário.
  Future<ServerDetail> fetchServerDetail(String serverId) async {
    try {
      final response = await _dio.get('/servers/$serverId');
      return ServerDetail.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `PATCH /servers/:id { name }` → 200 com o servidor.
  Future<Server> updateServer(String serverId, {required String name}) async {
    try {
      final response = await _dio.patch(
        '/servers/$serverId',
        data: {'name': name},
      );
      return Server.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `POST /uploads` (kind `server-icon`, async) + polling até `READY` →
  /// URL do ícone persistido.
  Future<String> uploadServerIcon(
    String serverId, {
    required List<int> bytes,
    required String fileName,
    required String contentType,
  }) async {
    try {
      return await enqueueImageUpload(
        _dio,
        bytes: bytes,
        fileName: fileName,
        contentType: contentType,
        kind: 'server-icon',
        serverId: serverId,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `DELETE /servers/:id/icon` → 204.
  Future<void> deleteServerIcon(String serverId) async {
    try {
      await _dio.delete('/servers/$serverId/icon');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `DELETE /servers/:id` → 204 (apenas OWNER).
  Future<void> deleteServer(String serverId) async {
    try {
      await _dio.delete('/servers/$serverId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `POST /servers/:id/leave` → 204 (apenas não-OWNER).
  Future<void> leaveServer(String serverId) async {
    try {
      await _dio.post('/servers/$serverId/leave');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `GET /servers/:id/members`.
  Future<List<ServerMember>> fetchMembers(String serverId) async {
    try {
      final response = await _dio.get('/servers/$serverId/members');
      final list = response.data as List<dynamic>;
      return list
          .map((e) => ServerMember.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `DELETE /servers/:id/members/:userId` → 204 (gestão por hierarquia).
  Future<void> removeMember(String serverId, String userId) async {
    try {
      await _dio.delete('/servers/$serverId/members/$userId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Promove/rebaixa ADMIN ↔ MEMBER. Apenas o dono pode alterar cargos.
  Future<ServerMember> updateMemberRole(
    String serverId,
    String userId,
    ServerRole role,
  ) async {
    try {
      final response = await _dio.patch(
        '/servers/$serverId/members/$userId/role',
        data: {'role': role.apiValue},
      );
      return ServerMember.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `POST /servers/:id/invites { expiresAt?, maxUses? }` → 201 (gestores).
  Future<InviteInfo> createInvite(String serverId) async {
    try {
      final response = await _dio.post('/servers/$serverId/invites');
      return InviteInfo.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `GET /invites/:code` — público, sem autenticação.
  Future<InviteDetail> fetchInvite(String code) async {
    try {
      final response = await _dio.get('/invites/$code');
      return InviteDetail.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `POST /invites/:code/accept` → 201/200 idempotente. Retorna o id do
  /// servidor (o payload traz `serverMember.serverId` nos dois casos — 201
  /// primeiro aceite, 200 já era membro).
  Future<String> acceptInvite(String code) async {
    try {
      final response = await _dio.post('/invites/$code/accept');
      final serverMember =
          (response.data as Map<String, dynamic>)['serverMember']
              as Map<String, dynamic>;
      return serverMember['serverId'] as String;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `GET /servers/:id/channels`.
  Future<List<ServerChannel>> fetchChannels(String serverId) async {
    try {
      final response = await _dio.get('/servers/$serverId/channels');
      final list = response.data as List<dynamic>;
      return list
          .map((e) => ServerChannel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `POST /servers/:id/channels { name, type }` → 201 (OWNER).
  Future<ServerChannel> createChannel(
    String serverId, {
    required String name,
    required ChannelType type,
  }) async {
    try {
      final response = await _dio.post(
        '/servers/$serverId/channels',
        data: {'name': name, 'type': type.name.toUpperCase()},
      );
      return ServerChannel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `PATCH /channels/:id { name }` → 200 (OWNER).
  Future<ServerChannel> updateChannel(
    String channelId, {
    required String name,
  }) async {
    try {
      final response = await _dio.patch(
        '/channels/$channelId',
        data: {'name': name},
      );
      return ServerChannel.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `DELETE /channels/:id` → 204 (OWNER).
  Future<void> deleteChannel(String channelId) async {
    try {
      await _dio.delete('/channels/$channelId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `GET /channels/:id/messages?limit=50&before=<messageId>` — página de
  /// mensagens (mais recentes primeiro na API; o client inverte).
  Future<MessagePage> fetchMessages(
    String channelId, {
    int limit = 50,
    String? before,
  }) async {
    try {
      final response = await _dio.get(
        '/channels/$channelId/messages',
        queryParameters: {'limit': limit, 'before': ?before},
      );
      final data = response.data as Map<String, dynamic>;
      return MessagePage(
        messages: (data['messages'] as List<dynamic>)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextCursor: data['nextCursor'] as String?,
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `POST /channels/:id/messages` → 201 com a mensagem criada.
  Future<ChatMessage> sendMessage(
    String channelId,
    String content, {
    ChatMessageKind kind = ChatMessageKind.text,
    String? gifUrl,
    String? replyToId,
    List<String>? uploadIds,
  }) async {
    try {
      final response = await _dio.post(
        '/channels/$channelId/messages',
        data: {
          'content': content,
          'kind': kind.apiValue,
          'gifUrl': ?gifUrl,
          'replyToId': ?replyToId,
          'uploadIds': ?uploadIds,
        },
      );
      return ChatMessage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `POST /messages/:id/reactions { emoji }` → mensagem atualizada.
  Future<ChatMessage> toggleMessageReaction(
    String messageId,
    String emoji,
  ) async {
    try {
      final response = await _dio.post(
        '/messages/$messageId/reactions',
        data: {'emoji': emoji},
      );
      return ChatMessage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `PATCH /messages/:id { content }` → mensagem editada (só autor,
  /// só texto/legenda; anexos usam o PATCH de attachments).
  Future<ChatMessage> editMessage(String messageId, String content) async {
    try {
      final response = await _dio.patch(
        '/messages/$messageId',
        data: {'content': content},
      );
      return ChatMessage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `DELETE /messages/:id` → 204 (só autor; chega via `message.deleted`).
  Future<void> deleteMessage(String messageId) async {
    try {
      await _dio.delete('/messages/$messageId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Retry parcial de anexo FAILED (spec-chat-imagens): novo `POST /uploads`
  /// + `PATCH /messages/:id/attachments { uploadIds }` → mensagem atualizada.
  ///
  /// Usado quando o `POST /uploads` do composer falhou ANTES do envio (bytes
  /// ainda em mãos). Após o envio, o retry usa [retryUpload] (staging no R2).
  Future<ChatMessage> addMessageAttachments(
    String messageId,
    List<String> uploadIds,
  ) async {
    try {
      final response = await _dio.patch(
        '/messages/$messageId/attachments',
        data: {'uploadIds': uploadIds},
      );
      return ChatMessage.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Retry de anexo FAILED já vinculado (spec-chat-imagens):
  /// `POST /uploads/:id/retry` re-enfileira o staging no R2; a imagem chega
  /// via `message.updated` (sem PATCH — o anexo já existe na mensagem).
  Future<void> retryUpload(String uploadId) async {
    try {
      await _dio.post('/uploads/$uploadId/retry');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `GET /servers/:id/presence` → `{ online, voiceByChannel }`.
  Future<ServerPresence> fetchPresence(String serverId) async {
    try {
      final response = await _dio.get('/servers/$serverId/presence');
      return ServerPresence.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `POST /servers/:id/channels/:id/join` → credenciais LiveKit do canal
  /// de voz (Fase 4). O token é emitido SÓ pelo backend (10m de validade).
  Future<VoiceJoinInfo> joinVoice(String serverId, String channelId) async {
    try {
      final response = await _dio.post(
        '/servers/$serverId/channels/$channelId/join',
      );
      return VoiceJoinInfo.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
