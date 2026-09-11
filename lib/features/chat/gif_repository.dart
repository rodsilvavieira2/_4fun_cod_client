import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';

final gifRepositoryProvider = Provider<GifRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: _withTrailingSlash(config.gifSnapBaseUrl),
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      headers: const {'Content-Type': 'application/json'},
    ),
  );
  ref.onDispose(dio.close);
  return GifRepository(dio);
});

class GifRepository {
  const GifRepository(this._dio);

  final Dio _dio;

  String get searchHint => 'Buscar GIFs';

  Future<List<GifResult>> trending({int page = 1, int perPage = 18}) {
    return _fetch(
      path: 'gifs/trending',
      queryParameters: {'page': page, 'limit': perPage},
    );
  }

  Future<List<GifResult>> search({
    required String query,
    int page = 1,
    int perPage = 18,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return trending(page: page, perPage: perPage);
    }
    return _fetch(
      path: 'gifs/search',
      queryParameters: {'q': trimmed, 'page': page, 'limit': perPage},
    );
  }

  Future<List<GifResult>> _fetch({
    required String path,
    required Map<String, Object?> queryParameters,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        path,
        queryParameters: queryParameters,
      );
      return parseGifSnapGifs(response.data);
    } on DioException catch (error) {
      throw GifRepositoryException(
        error.response?.statusMessage ??
            'Não foi possível carregar GIFs do provider gratuito.',
      );
    }
  }
}

class GifRepositoryException implements Exception {
  const GifRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GifResult {
  const GifResult({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.previewUrl,
    required this.source,
    this.width,
    this.height,
    this.pageUrl,
  });

  final String id;
  final String title;
  final String imageUrl;
  final String previewUrl;
  final String source;
  final int? width;
  final int? height;
  final String? pageUrl;
}

List<GifResult> parseGifSnapGifs(Object? payload) {
  if (payload is! Map<String, dynamic>) return const [];
  final data = payload['data'];
  if (data is! List) return const [];
  return [for (final item in _mapsFrom(data)) ?_parseGifSnapGif(item)];
}

List<Map<String, dynamic>> _mapsFrom(List<Object?> values) {
  return [for (final value in values) ?_stringMap(value)];
}

Map<String, dynamic>? _stringMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is! Map) return null;
  final entries = <String, dynamic>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String) entries[key] = entry.value;
  }
  return entries;
}

GifResult? _parseGifSnapGif(Map<String, dynamic> item) {
  final type = _string(item['type']);
  if (type != null && type != 'gif') return null;
  final imageUrl = _string(item['url']);
  if (imageUrl == null) return null;

  return GifResult(
    id: _string(item['id']) ?? imageUrl,
    title: _string(item['title']) ?? 'GIF',
    imageUrl: imageUrl,
    previewUrl: _string(item['preview_url']) ?? imageUrl,
    source: _string(item['source']) ?? 'gifsnap',
    width: _int(item['width']),
    height: _int(item['height']),
    pageUrl: _string(item['page_url']) ?? _string(item['itemurl']),
  );
}

String? _string(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value;
  if (value is num) return value.toString();
  return null;
}

int? _int(Object? value) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

String _withTrailingSlash(String value) {
  return value.endsWith('/') ? value : '$value/';
}
