import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';

/// Serviço de object storage — avatares via multipart para o backend (§5.2).
///
/// O client envia o arquivo e o backend gera a chave no R2 e persiste o
/// `avatarUrl`; o client nunca constrói URLs nem conhece a chave do objeto.
abstract class StorageService {
  /// Faz upload do avatar (`PATCH /users/me/avatar`, multipart `file`) a
  /// partir de bytes, o que funciona tanto em browser quanto em desktop.
  Future<String> uploadAvatar({
    required List<int> bytes,
    required String fileName,
    required String contentType,
  });

  /// Remove o avatar (`DELETE /users/me/avatar`) — o backend deriva a chave
  /// do objeto a partir do token; sem uid/fileName no client.
  Future<void> deleteAvatar();
}

/// Implementação via dio multipart (`FormData`) para o backend NestJS.
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
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: fileName,
          contentType: DioMediaType.parse(contentType),
        ),
      });
      final response = await _dio.patch('/users/me/avatar', data: formData);
      final data = response.data as Map<String, dynamic>;
      return data['avatarUrl'] as String;
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
