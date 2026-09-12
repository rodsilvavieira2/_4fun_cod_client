import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../config/app_config.dart';

/// Resolve um path de arquivo do servidor (`/api/v1/files/...`, como vem em
/// `User.avatarUrl` / `Server.iconUrl`) para URL absoluta.
///
/// URLs já absolutas passam intactas. O `finalUrl` do servidor já carrega o
/// prefixo da API (`/api/v1/files/...`), então é ancorado na **origem** de
/// [restBase] para não duplicar o prefixo. Paths sem esse prefixo são
/// ancorados em [restBase]. Nunca em `Uri.base`, que no desktop é `file://`
/// e quebrava todas as imagens (`No host specified in URI file:///api/...`).
String resolveFileUrl(String restBase, String path) {
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme) {
    return path;
  }
  final base = Uri.parse(restBase);
  if (base.path.isNotEmpty && base.path != '/' && path.startsWith(base.path)) {
    return '${base.origin}$path';
  }
  final b = restBase.endsWith('/')
      ? restBase.substring(0, restBase.length - 1)
      : restBase;
  return path.startsWith('/') ? '$b$path' : '$b/$path';
}

/// Bytes de uma imagem do proxy autenticado `GET /api/v1/files/*`,
/// indexados pela URL absoluta (cache do próprio provider por sessão).
///
/// Baixa pelo [apiClientProvider] (dio com auth + refresh) em vez de
/// `Image.network`/`NetworkImage`, que não enviariam o JWT e resolveriam
/// o path relativo contra `Uri.base` (`file://` no desktop).
final fileImageBytesProvider = FutureProvider.family<Uint8List, String>((
  ref,
  url,
) async {
  final res = await ref.watch(apiClientProvider).get<List<int>>(
    url,
    options: Options(responseType: ResponseType.bytes),
  );
  final data = res.data;
  if (data == null || data.isEmpty) {
    throw StateError('Resposta vazia ao baixar imagem: $url');
  }
  return Uint8List.fromList(data);
});

/// Imagem hospedada no proxy de arquivos do servidor.
///
/// Enquanto carrega, em erro ou com [path] nulo/vazio, mostra [fallback].
class AppFileImage extends ConsumerWidget {
  const AppFileImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback = const SizedBox.shrink(),
  });

  /// Path relativo (`/api/v1/files/...`) ou URL absoluta. Nulo = [fallback].
  final String? path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = path;
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    final url = resolveFileUrl(
      ref.watch(appConfigProvider).apiRestBaseUrl,
      raw,
    );
    return ref
        .watch(fileImageBytesProvider(url))
        .when(
          data: (bytes) => Image.memory(
            bytes,
            width: width,
            height: height,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback,
          ),
          loading: () => fallback,
          error: (_, _) => fallback,
        );
  }
}
