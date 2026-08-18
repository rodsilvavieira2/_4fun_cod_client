import 'package:dio/dio.dart';

/// Exceção de API com mensagem amigável, extraída do padrão de erro do
/// backend (`{ statusCode, message, error }` — §3 do plano de arquitetura).
class ApiException implements Exception {
  const ApiException({required this.message, this.statusCode, this.error});

  /// Converte um [DioException] em [ApiException], extraindo `message` do
  /// corpo de erro do backend quando disponível (string ou lista de strings).
  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      return ApiException(
        message: switch (message) {
          final String m => m,
          final List<dynamic> list => list.join('\n'),
          _ => 'Erro inesperado no servidor.',
        },
        statusCode: e.response?.statusCode,
        error: data['error'] as String?,
      );
    }
    final isConnectionProblem = e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout;
    return ApiException(
      message: isConnectionProblem
          ? 'Sem conexão com o servidor. Tente novamente.'
          : (e.message ?? 'Erro inesperado.'),
      statusCode: e.response?.statusCode,
    );
  }

  /// Mensagem amigável para exibição ao usuário.
  final String message;

  /// Código HTTP da resposta (nulo para erros de rede/local).
  final int? statusCode;

  /// Campo `error` do padrão de erro do backend (ex.: "Bad Request").
  final String? error;

  @override
  String toString() => message;
}
