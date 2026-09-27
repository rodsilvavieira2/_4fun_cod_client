import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/storage/uploads_client.dart';
import '../../shared/models/profile.dart';
import '../../core/websocket/socket_service.dart';
import '../../core/websocket/realtime_event.dart';
import '../../core/ui/app_file_image.dart';

class ProfileRepository {
  const ProfileRepository(this._dio);
  final Dio _dio;
  static final Set<String> _loadedFontFamilies = {};

  Future<ProfileEditorData> editor([String? serverId]) async {
    try {
      final result = await _dio.get(
        '/profiles/me/editor',
        queryParameters: {'serverId': ?serverId},
      );
      return ProfileEditorData.fromJson(
        (result.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ProfileData> resolved(String userId, [String? serverId]) async {
    try {
      final result = await _dio.get(
        '/profiles/$userId',
        queryParameters: {'serverId': ?serverId},
      );
      return ProfileData.fromJson((result.data as Map).cast<String, dynamic>());
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ProfileEditorData> saveMain(Map<String, dynamic> changes) async {
    try {
      final result = await _dio.patch('/profiles/me/main', data: changes);
      return ProfileEditorData.fromJson(
        (result.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<ProfileEditorData> saveServer(
    String serverId,
    Map<String, dynamic> changes,
  ) async {
    try {
      final result = await _dio.patch(
        '/profiles/me/servers/$serverId',
        data: changes,
      );
      return ProfileEditorData.fromJson(
        (result.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<({bool nicknamePreserved, ProfileEditorData editor})> resetServer(
    String serverId,
  ) async {
    try {
      final result = await _dio.post('/profiles/me/servers/$serverId/reset');
      final data = (result.data as Map).cast<String, dynamic>();
      return (
        nicknamePreserved: data['nicknamePreserved'] as bool? ?? false,
        editor: ProfileEditorData.fromJson(
          (data['editor'] as Map).cast<String, dynamic>(),
        ),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<CosmeticItem>> catalog() async {
    try {
      final result = await _dio.get('/profiles/me/catalog');
      return (result.data as List)
          .map(
            (item) =>
                CosmeticItem.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<CosmeticItem>> visualCatalog() async {
    try {
      final result = await _dio.get('/profiles/catalog');
      return (result.data as List)
          .map(
            (item) =>
                CosmeticItem.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList();
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<ProfileFont>> fonts() async {
    try {
      final response = await _dio.get('/profiles/fonts');
      final fonts = (response.data as List)
          .map(
            (item) =>
                ProfileFont.fromJson((item as Map).cast<String, dynamic>()),
          )
          .toList();
      for (final font in fonts) {
        if (font.assetUrl == null ||
            _loadedFontFamilies.contains(font.family)) {
          continue;
        }
        final url = resolveFileUrl(_dio.options.baseUrl, font.assetUrl!);
        final data = await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = data.data;
        if (bytes == null || bytes.isEmpty) continue;
        final loader = FontLoader(font.family)
          ..addFont(
            Future.value(ByteData.sublistView(Uint8List.fromList(bytes))),
          );
        await loader.load();
        _loadedFontFamilies.add(font.family);
      }
      return fonts;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<String> prepareImage({
    required List<int> bytes,
    required String fileName,
    required String contentType,
    required bool banner,
    String? serverId,
  }) async {
    final kind = serverId == null
        ? (banner ? 'profile-banner' : 'profile-avatar')
        : (banner ? 'server-profile-banner' : 'server-profile-avatar');
    final id = await startImageUpload(
      _dio,
      bytes: bytes,
      fileName: fileName,
      contentType: contentType,
      kind: kind,
      serverId: serverId,
    );
    await waitForUploadReady(_dio, id);
    return id;
  }

  Future<String> setStatus(String status) async {
    try {
      final result = await _dio.patch(
        '/profiles/me/status',
        data: {'status': status},
      );
      return (result.data as Map)['status'] as String;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<({bool valid, bool available, String? reason})> usernameAvailability(
    String value,
  ) async {
    try {
      final response = await _dio.get(
        '/users/username/availability',
        queryParameters: {'value': value},
      );
      final data = (response.data as Map).cast<String, dynamic>();
      return (
        valid: data['valid'] == true,
        available: data['available'] == true,
        reason: data['reason'] as String?,
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> setMemberNickname(
    String serverId,
    String userId,
    String? nickname,
  ) async {
    try {
      await _dio.patch(
        '/profiles/servers/$serverId/members/$userId/nickname',
        data: {'nickname': nickname},
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepository(ref.watch(apiClientProvider)),
);

final profileProvider =
    FutureProvider.family<ProfileData, ({String userId, String? serverId})>((
      ref,
      arg,
    ) {
      final subscription = ref.read(socketServiceProvider).events.listen((
        event,
      ) {
        if (event is ProfileChangedEvent &&
            event.userId == arg.userId &&
            (event.serverId == null || event.serverId == arg.serverId)) {
          ref.invalidateSelf();
        }
      });
      ref.onDispose(subscription.cancel);
      return ref
          .watch(profileRepositoryProvider)
          .resolved(arg.userId, arg.serverId);
    });

final visualCatalogProvider = FutureProvider<List<CosmeticItem>>(
  (ref) => ref.watch(profileRepositoryProvider).visualCatalog(),
);

final profileFontsProvider = FutureProvider<List<ProfileFont>>(
  (ref) => ref.watch(profileRepositoryProvider).fonts(),
);
