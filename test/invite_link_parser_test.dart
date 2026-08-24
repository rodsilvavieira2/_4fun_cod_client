import 'package:fourfun_cod_client/features/servers/invite_link_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractInviteCode', () {
    test('extrai de URL de produção', () {
      expect(
        extractInviteCode('https://app.4funcod.dev/invite/WyAKHtYnLU'),
        'WyAKHtYnLU',
      );
    });

    test('extrai de URL local da API', () {
      expect(
        extractInviteCode('http://localhost:3000/invite/WyAKHtYnLU'),
        'WyAKHtYnLU',
      );
    });

    test('extrai de URL web com hash routing', () {
      expect(
        extractInviteCode('http://localhost:8090/#/invite/WyAKHtYnLU'),
        'WyAKHtYnLU',
      );
    });

    test('aceita código puro', () {
      expect(extractInviteCode('WyAKHtYnLU'), 'WyAKHtYnLU');
    });

    test('ignora query string e espaços', () {
      expect(
        extractInviteCode('  https://app.4funcod.dev/invite/WyAKHtYnLU?x=1  '),
        'WyAKHtYnLU',
      );
    });

    test('código é case-sensitive (base62)', () {
      expect(extractInviteCode('wyakhTYNLu'), 'wyakhTYNLu');
    });

    test('retorna null para vazio', () {
      expect(extractInviteCode(''), isNull);
      expect(extractInviteCode('   '), isNull);
    });

    test('retorna null para texto sem código', () {
      expect(extractInviteCode('qualquer coisa'), isNull);
      expect(extractInviteCode('http://localhost:8090/#/algumacoisa'), isNull);
      expect(extractInviteCode('https://exemplo.com/'), isNull);
    });
  });
}
