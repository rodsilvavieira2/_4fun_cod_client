import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// Provider do cliente HTTP compartilhado (dio).
///
/// O interceptor de auth (refresh single-flight, §7.3) é anexado pelo
/// [AuthRepository] ao ser construído (bootstrap da sessão), evitando a
/// dependência circular apiClient ↔ repository.
final apiClientProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(appConfigProvider).apiBaseUrl;
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: const {'Content-Type': 'application/json'},
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});
