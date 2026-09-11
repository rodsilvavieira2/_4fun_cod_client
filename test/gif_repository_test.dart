import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/features/chat/gif_repository.dart';

void main() {
  test('parseGifSnapGifs lê o formato público do GifSnap', () {
    final gifs = parseGifSnapGifs({
      'data': [
        {
          'id': 'giphy_abc123',
          'title': 'Funny Cats Compilation',
          'url': 'https://gifsnap.com/api/v1/media/full.gif',
          'preview_url': 'https://gifsnap.com/api/v1/media/preview.gif',
          'width': 480,
          'height': 270,
          'type': 'gif',
          'source': 'giphy',
        },
      ],
      'pagination': {'page': 1, 'limit': 10},
    });

    expect(gifs, hasLength(1));
    expect(gifs.single.id, 'giphy_abc123');
    expect(gifs.single.title, 'Funny Cats Compilation');
    expect(gifs.single.imageUrl, 'https://gifsnap.com/api/v1/media/full.gif');
    expect(
      gifs.single.previewUrl,
      'https://gifsnap.com/api/v1/media/preview.gif',
    );
    expect(gifs.single.width, 480);
    expect(gifs.single.height, 270);
    expect(gifs.single.source, 'giphy');
  });

  test('parseGifSnapGifs ignora itens que não são GIFs', () {
    final gifs = parseGifSnapGifs({
      'data': [
        {
          'id': 'sticker_123',
          'title': 'Sticker',
          'url': 'https://gifsnap.com/api/v1/media/sticker.gif',
          'type': 'sticker',
        },
      ],
    });

    expect(gifs, isEmpty);
  });
}
