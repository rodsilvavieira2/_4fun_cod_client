import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/features/chat/mention_utils.dart';

void main() {
  const ana = MentionTarget(userId: 'u1', name: 'Ana Silva', username: 'ana');
  const bia = MentionTarget(userId: 'u2', name: 'Bia Costa', username: 'bia_2');
  const caio = MentionTarget(userId: 'u3', name: 'Caio', username: 'caio');

  TextEditingValue valueAtEnd(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  test('findActiveMention detecta a menção no token atual', () {
    final mention = findActiveMention(valueAtEnd('oi @an'));

    expect(mention, isNotNull);
    expect(mention!.start, 3);
    expect(mention.end, 6);
    expect(mention.query, 'an');
  });

  test('findActiveMention ignora e-mail e seleção não colapsada', () {
    expect(findActiveMention(valueAtEnd('ana@test.dev')), isNull);
    expect(
      findActiveMention(
        const TextEditingValue(
          text: '@ana',
          selection: TextSelection(baseOffset: 0, extentOffset: 4),
        ),
      ),
      isNull,
    );
  });

  test('rankMentionTargets prioriza username exato e prefixos', () {
    final ranked = rankMentionTargets([caio, bia, ana], 'bi');

    expect(ranked.map((target) => target.username), ['bia_2']);
  });

  test('buildMentionTextParts destaca apenas usernames conhecidos', () {
    final parts = buildMentionTextParts('fala @ana e @ninguem', [ana, bia]);

    expect(parts.map((part) => part.text), ['fala ', '@ana', ' e @ninguem']);
    expect(parts[1].target?.userId, 'u1');
    expect(parts.last.isMention, isFalse);
  });
}
