import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/features/chat/emoji_catalog.dart';

void main() {
  test('emojiCatalogEntries contém catálogo Unicode amplo', () {
    expect(emojiCatalogEntries.length, greaterThanOrEqualTo(3900));
    expect(emojiCatalogEntries.map((entry) => entry.value), contains('😀'));
    expect(emojiCatalogEntries.map((entry) => entry.value), contains('❤️'));
    expect(emojiCatalogEntries.map((entry) => entry.value), contains('🏳️‍🌈'));
  });

  test('EmojiCatalogEntry.matches busca por nome, keyword e glyph', () {
    const entry = EmojiCatalogEntry(
      '🚀',
      'rocket',
      'rocket travel places transport sky air',
    );

    expect(entry.matches('rocket'), isTrue);
    expect(entry.matches(':transport:'), isTrue);
    expect(entry.matches('🚀'), isTrue);
    expect(entry.matches('banana'), isFalse);
  });
}
