import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../logging/dio_logging_interceptor.dart';

/// Provider do cliente HTTP compartilhado (dio).
///
/// O interceptor de auth (refresh single-flight, §7.3) é anexado pelo
/// [AuthRepository] ao ser construído (bootstrap da sessão), evitando a
/// dependência circular apiClient ↔ repository. O [DioLoggingInterceptor]
/// é anexado aqui (primeiro da cadeia) para logar TODAS as requisições.
final apiClientProvider = Provider<Dio>((ref) {
  final dio = Dio(_apiBaseOptions(ref.watch(appConfigProvider)));
  dio.interceptors.add(DioLoggingInterceptor(ref.watch(appLoggerProvider)));
  ref.onDispose(dio.close);
  return dio;
});

/// Dio "nu" — SEM o [AuthInterceptor] (e sem filas do QueuedInterceptor) —
/// para operações de auth que não podem re-entrar na cadeia que originou um
/// erro (refresh/logout/retry do onError). Uma request aninhada dentro do
/// `onError` que FALHE entraria na `_errorQueue` ATRÁS do erro original em
/// processamento → espera circular (deadlock permanente, spinner infinito:
/// fila de interceptor não tem timeout). Também logado (sem headers).
final apiBareClientProvider = Provider<Dio>((ref) {
  final dio = Dio(_apiBaseOptions(ref.watch(appConfigProvider)));
  dio.interceptors.add(DioLoggingInterceptor(ref.watch(appLoggerProvider)));
  ref.onDispose(dio.close);
  return dio;
});

BaseOptions _apiBaseOptions(AppConfig config) => BaseOptions(
      baseUrl: config.apiRestBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {'Content-Type': 'application/json'},
    );
