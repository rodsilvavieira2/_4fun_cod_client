import 'package:dio/dio.dart';

import '../../shared/models/servers.dart';
import '../../core/api/api_exception.dart';

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

  /// `PATCH /servers/:id { name?, iconUrl? }` → 200 com o servidor.
  Future<Server> updateServer(
    String serverId, {
    String? name,
    String? iconUrl,
  }) async {
    try {
      final response = await _dio.patch(
        '/servers/$serverId',
        data: {'name': ?name, 'iconUrl': ?iconUrl},
      );
      return Server.fromJson(response.data as Map<String, dynamic>);
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

  /// `DELETE /servers/:id/members/:userId` → 204 (apenas OWNER).
  Future<void> removeMember(String serverId, String userId) async {
    try {
      await _dio.delete('/servers/$serverId/members/$userId');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// `POST /servers/:id/invites { expiresAt?, maxUses? }` → 201 (OWNER).
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

  /// `POST /invites/:code/accept` → 201 (idempotente: 200 se já membro).
  /// A navegação pós-aceite usa o servidor vindo de [fetchInvite].
  Future<void> acceptInvite(String code) async {
    try {
      await _dio.post('/invites/$code/accept');
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
  Future<ServerChannel> updateChannel(String channelId, {required String name}) async {
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
}
