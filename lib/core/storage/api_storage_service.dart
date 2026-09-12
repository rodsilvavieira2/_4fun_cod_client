import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import 'uploads_client.dart';

/// Serviço de object storage — avatares via fila async do backend (§5.2).
///
/// O client envia o arquivo (`POST /uploads`, kind `avatar`) e aguarda o
/// `READY`; o backend gera a chave no R2 e persiste o `avatarUrl`.
abstract class StorageService {
  /// Faz upload do avatar (async: enqueue + polling até `READY`) a partir
  /// de bytes, o que funciona tanto em browser quanto em desktop.
  Future<String> uploadAvatar({
    required List<int> bytes,
    required String fileName,
    required String contentType,
  });

  /// Remove o avatar (`DELETE /users/me/avatar`) — o backend deriva a chave
  /// do objeto a partir do token; sem uid/fileName no client.
  Future<void> deleteAvatar();
}

/// Implementação via fila async de uploads do backend NestJS.
class ApiStorageService implements StorageService {
  ApiStorageService(this._dio);

  final Dio _dio;

  @override
  Future<String> uploadAvatar({
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
        kind: 'avatar',
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  @override
  Future<void> deleteAvatar() async {
    try {
      await _dio.delete('/users/me/avatar');
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

/// Provider do serviço de storage (API multipart do backend).
final storageServiceProvider = Provider<StorageService>(
  (ref) => ApiStorageService(ref.watch(apiClientProvider)),
);
