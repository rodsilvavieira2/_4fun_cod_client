import 'package:flutter/services.dart';

class MentionTarget {
  const MentionTarget({
    required this.userId,
    required this.name,
    required this.username,
    this.avatarUrl,
  });

  final String userId;
  final String name;
  final String username;
  final String? avatarUrl;

  String get label => name.trim().isEmpty ? username : name;
  String get mentionText => '@$username';
}

class ActiveMention {
  const ActiveMention({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;

  @override
  bool operator ==(Object other) =>
      other is ActiveMention &&
      other.start == start &&
      other.end == end &&
      other.query == query;

  @override
  int get hashCode => Object.hash(start, end, query);
}

class MentionTextPart {
  const MentionTextPart({required this.text, this.target});

  final String text;
  final MentionTarget? target;

  bool get isMention => target != null;
}

ActiveMention? findActiveMention(TextEditingValue value) {
  if (!value.selection.isCollapsed) return null;
  final text = value.text;
  final caret = value.selection.extentOffset;
  if (caret < 0 || caret > text.length) return null;

  var tokenStart = caret;
  while (tokenStart > 0 &&
      _isMentionTokenCodeUnit(text.codeUnitAt(tokenStart - 1))) {
    tokenStart--;
  }
  final atIndex = tokenStart - 1;
  if (atIndex < 0 || text.codeUnitAt(atIndex) != _atSign) return null;
  if (atIndex > 0 && _isMentionTokenCodeUnit(text.codeUnitAt(atIndex - 1))) {
    return null;
  }

  return ActiveMention(
    start: atIndex,
    end: caret,
    query: text.substring(tokenStart, caret).toLowerCase(),
  );
}

List<MentionTarget> rankMentionTargets(
  Iterable<MentionTarget> targets,
  String query, {
  int limit = 8,
}) {
  final list = targets.toList(growable: false);
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return list.take(limit).toList(growable: false);

  final scored = <_ScoredMentionTarget>[];
  for (var index = 0; index < list.length; index++) {
    final target = list[index];
    final score = _mentionScore(target, normalized);
    if (score == null) continue;
    scored.add(_ScoredMentionTarget(target, score, index));
  }

  scored.sort((left, right) {
    final score = left.score.compareTo(right.score);
    if (score != 0) return score;
    final username = left.target.username.compareTo(right.target.username);
    if (username != 0) return username;
    return left.index.compareTo(right.index);
  });

  return scored
      .map((entry) => entry.target)
      .take(limit)
      .toList(growable: false);
}

List<MentionTextPart> buildMentionTextParts(
  String text,
  Iterable<MentionTarget> targets,
) {
  if (text.isEmpty) return const [];

  final byUsername = {
    for (final target in targets) target.username.toLowerCase(): target,
  };
  if (byUsername.isEmpty) {
    return [MentionTextPart(text: text)];
  }

  final parts = <MentionTextPart>[];
  var cursor = 0;
  for (final match in _renderMentionPattern.allMatches(text)) {
    if (!_hasMentionBoundary(text, match.start)) continue;
    final username = match.group(1)?.toLowerCase();
    final target = username == null ? null : byUsername[username];
    if (target == null) continue;

    if (match.start > cursor) {
      parts.add(MentionTextPart(text: text.substring(cursor, match.start)));
    }
    parts.add(
      MentionTextPart(
        text: text.substring(match.start, match.end),
        target: target,
      ),
    );
    cursor = match.end;
  }

  if (cursor < text.length) {
    parts.add(MentionTextPart(text: text.substring(cursor)));
  }
  return parts.isEmpty ? [MentionTextPart(text: text)] : parts;
}

int? _mentionScore(MentionTarget target, String query) {
  final username = target.username.toLowerCase();
  final name = target.name.toLowerCase();
  if (username == query) return 0;
  if (username.startsWith(query)) return 1;
  if (name.startsWith(query)) return 2;
  if (username.contains(query)) return 3;
  if (name.contains(query)) return 4;
  return null;
}

bool _hasMentionBoundary(String text, int index) {
  if (index == 0) return true;
  return !_isMentionTokenCodeUnit(text.codeUnitAt(index - 1));
}

bool _isMentionTokenCodeUnit(int codeUnit) {
  return (codeUnit >= _lowerA && codeUnit <= _lowerZ) ||
      (codeUnit >= _upperA && codeUnit <= _upperZ) ||
      (codeUnit >= _zero && codeUnit <= _nine) ||
      codeUnit == _underscore;
}

class _ScoredMentionTarget {
  const _ScoredMentionTarget(this.target, this.score, this.index);

  final MentionTarget target;
  final int score;
  final int index;
}

final _renderMentionPattern = RegExp(r'@([A-Za-z0-9_]{3,20})(?![A-Za-z0-9_])');

const _atSign = 64;
const _underscore = 95;
const _zero = 48;
const _nine = 57;
const _upperA = 65;
const _upperZ = 90;
const _lowerA = 97;
const _lowerZ = 122;
