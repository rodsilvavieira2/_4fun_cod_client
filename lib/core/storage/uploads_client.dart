import 'package:dio/dio.dart';

import '../api/api_exception.dart';

/// Uploads assíncronos de imagem (contrato único do app).
///
/// `POST /uploads` (multipart `file` + `kind`) responde `202 {uploadId}`;
/// o chamador aguarda `GET /uploads/:id` até `READY` (`finalUrl`) ou
/// `FAILED` (erro). O client nunca constrói chaves nem URLs do storage.
Future<String> enqueueImageUpload(
  Dio dio, {
  required List<int> bytes,
  required String fileName,
  required String contentType,
  required String kind,
  String? serverId,
  String? channelId,
}) async {
  try {
    final formData = FormData.fromMap({
      'kind': kind,
      ...?_optionalField('serverId', serverId),
      ...?_optionalField('channelId', channelId),
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType.parse(contentType),
      ),
    });
    final response = await dio.post('/uploads', data: formData);
    final data = response.data as Map<String, dynamic>;
    return await waitForUploadReady(dio, data['uploadId'] as String);
  } on ApiException {
    rethrow;
  } on DioException catch (e) {
    throw ApiException.fromDio(e);
  }
}

/// Campo opcional de formulário (`null` some do mapa via spread null-aware).
Map<String, String>? _optionalField(String name, String? value) =>
    value == null ? null : {name: value};

/// Polling de `GET /uploads/:id` até estado final (backoff fixo de 1s,
/// timeout de 60s). `FAILED` vira [ApiException] com o `lastError` do job.
Future<String> waitForUploadReady(
  Dio dio,
  String uploadId, {
  Duration timeout = const Duration(seconds: 60),
  Duration interval = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    try {
      final response = await dio.get('/uploads/$uploadId');
      final data = response.data as Map<String, dynamic>;
      switch (data['status'] as String) {
        case 'READY':
          return data['finalUrl'] as String;
        case 'FAILED':
          throw ApiException(
            message:
                (data['error'] as String?) ?? 'Falha ao processar a imagem.',
          );
      }
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
    if (DateTime.now().isAfter(deadline)) {
      throw const ApiException(
        message: 'O envio demorou demais. Tente novamente.',
      );
    }
    await Future.delayed(interval);
  }
}
