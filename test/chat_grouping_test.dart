import 'package:flutter_test/flutter_test.dart';
import 'package:fourfun_cod_client/features/chat/chat_grouping.dart';
import 'package:fourfun_cod_client/shared/models/message.dart';
import 'package:fourfun_cod_client/shared/models/user.dart';

const _ana = User(id: 'u1', name: 'Ana', username: 'ana');
const _bia = User(id: 'u2', name: 'Bia', username: 'bia');

ChatMessage _msg(String id, User author, DateTime createdAt) => ChatMessage(
  id: id,
  channelId: 'c1',
  content: 'msg $id',
  kind: ChatMessageKind.text,
  author: author,
  createdAt: createdAt,
);

void main() {
  final base = DateTime(2026, 9, 4, 21, 0);

  group('shouldStartNewGroup', () {
    test('primeira mensagem sempre abre grupo', () {
      expect(
        ChatGrouping.shouldStartNewGroup(
          current: _msg('m1', _ana, base),
          previous: null,
        ),
        isTrue,
      );
    });

    test('mesmo autor dentro da janela mantém o grupo', () {
      expect(
        ChatGrouping.shouldStartNewGroup(
          current: _msg('m2', _ana, base.add(const Duration(minutes: 3))),
          previous: _msg('m1', _ana, base),
        ),
        isFalse,
      );
    });

    test('autor diferente abre novo grupo', () {
      expect(
        ChatGrouping.shouldStartNewGroup(
          current: _msg('m2', _bia, base.add(const Duration(seconds: 10))),
          previous: _msg('m1', _ana, base),
        ),
        isTrue,
      );
    });

    test('mesmo autor além de 7 minutos abre novo grupo', () {
      expect(
        ChatGrouping.shouldStartNewGroup(
          current: _msg('m2', _ana, base.add(const Duration(minutes: 8))),
          previous: _msg('m1', _ana, base),
        ),
        isTrue,
      );
    });

    test('virada de dia abre novo grupo mesmo dentro da janela', () {
      final late = DateTime(2026, 9, 4, 23, 59);
      final early = DateTime(2026, 9, 5, 0, 2);
      expect(
        ChatGrouping.shouldStartNewGroup(
          current: _msg('m2', _ana, early),
          previous: _msg('m1', _ana, late),
        ),
        isTrue,
      );
    });

    test('ordem temporal inconsistente abre novo grupo', () {
      expect(
        ChatGrouping.shouldStartNewGroup(
          current: _msg('m2', _ana, base),
          previous: _msg('m1', _ana, base.add(const Duration(minutes: 1))),
        ),
        isTrue,
      );
    });
  });

  group('shouldShowDayDivider', () {
    test('primeira mensagem mostra divisor', () {
      expect(
        ChatGrouping.shouldShowDayDivider(
          current: _msg('m1', _ana, base),
          previous: null,
        ),
        isTrue,
      );
    });

    test('mesmo dia não mostra divisor', () {
      expect(
        ChatGrouping.shouldShowDayDivider(
          current: _msg('m2', _ana, base.add(const Duration(hours: 2))),
          previous: _msg('m1', _ana, base),
        ),
        isFalse,
      );
    });

    test('dia diferente mostra divisor', () {
      expect(
        ChatGrouping.shouldShowDayDivider(
          current: _msg('m2', _ana, base.add(const Duration(days: 1))),
          previous: _msg('m1', _ana, base),
        ),
        isTrue,
      );
    });
  });

  group('compare (ordenação determinística)', () {
    test('ordena por createdAt crescente', () {
      final newer = _msg('m2', _ana, base.add(const Duration(minutes: 1)));
      final older = _msg('m1', _ana, base);
      final sorted = [newer, older]..sort(ChatGrouping.compare);
      expect(sorted.map((m) => m.id), ['m1', 'm2']);
    });

    test('realtime fora de ordem cai na posição cronológica', () {
      final m1 = _msg('m1', _ana, base);
      final m3 = _msg('m3', _ana, base.add(const Duration(minutes: 2)));
      // Evento atrasado com timestamp entre m1 e m3.
      final late = _msg('m2', _ana, base.add(const Duration(minutes: 1)));
      final merged = [m1, m3, late]..sort(ChatGrouping.compare);
      expect(merged.map((m) => m.id), ['m1', 'm2', 'm3']);
    });

    test('desempata createdAt igual por id', () {
      final a = _msg('a', _ana, base);
      final b = _msg('b', _ana, base);
      expect(ChatGrouping.compare(a, b), lessThan(0));
      expect(ChatGrouping.compare(b, a), greaterThan(0));
    });
  });
}
