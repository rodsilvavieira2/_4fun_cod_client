import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/features/chat/link_embed_card.dart';
import 'package:fourfun_cod_client/features/chat/link_utils.dart';
import 'package:fourfun_cod_client/shared/models/link_embed.dart';

void main() {
  test('extractHttpUrls apara pontuação e limita a 3 com dedupe', () {
    expect(
      extractHttpUrls('veja https://www.twitch.tv/rhai_fran. e mais'),
      ['https://www.twitch.tv/rhai_fran'],
    );
    final text = [
      'https://a.com/1',
      'https://a.com/1',
      'https://b.com/2',
      'https://c.com/3',
      'https://d.com/4',
    ].join(' ');
    expect(extractHttpUrls(text), [
      'https://a.com/1',
      'https://b.com/2',
      'https://c.com/3',
    ]);
  });

  test('extractHttpUrls ignora convite interno', () {
    expect(
      extractHttpUrls('entre https://app.4funcod.dev/invite/ABC123 ok'),
      isEmpty,
    );
  });

  test('LinkEmbed.fromJson tolera embed ausente', () {
    const embed = LinkEmbed(
      url: 'https://www.twitch.tv/rhai_fran',
      siteName: 'Twitch',
      title: 'rhai_fran - Live on Twitch',
      description: 'DROPS ON',
      imageUrl: 'https://x.com/thumb.jpg',
    );
    expect(embed.hasTitle, isTrue);
    expect(
      LinkEmbed.fromJson(const {}).hasTitle,
      isFalse,
    );
  });

  test('unfurlImageProxyUrl ancora na origem sem duplicar prefixo', () {
    expect(
      unfurlImageProxyUrl(
        'http://localhost:3000/api/v1',
        'https://cdn.com/a.jpg',
      ),
      'http://localhost:3000/api/v1/unfurl/image?url=https%3A%2F%2Fcdn.com%2Fa.jpg',
    );
  });
}
