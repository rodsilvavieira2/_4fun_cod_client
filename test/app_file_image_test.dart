import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/core/ui/app_file_image.dart';

void main() {
  const rest = 'https://api.exemplo.com/api/v1';

  test('path relativo vira URL absoluta (nunca file://)', () {
    final url = resolveFileUrl(rest, '/api/v1/files/avatars/u/a.webp');

    expect(url, '$rest/api/v1/files/avatars/u/a.webp');
    expect(url.startsWith('https://'), isTrue);
  });

  test('URL absoluta passa intacta', () {
    const absolute = 'https://cdn.exemplo.com/a.webp';

    expect(resolveFileUrl(rest, absolute), absolute);
  });

  test('tolera barra final na base e path sem barra inicial', () {
    expect(
      resolveFileUrl('$rest/', 'api/v1/files/a.webp'),
      '$rest/api/v1/files/a.webp',
    );
  });
}
