/// Extração do código de convite a partir de um link colado ou código puro.
///
/// Cobre os formatos aceitos:
/// - `https://app.4funcod.dev/invite/<code>` (produção)
/// - `http://localhost:3000/invite/<code>` (API local)
/// - `http://localhost:8090/#/invite/<code>` (client web, hash routing)
/// - `<code>` puro (base62 de 10 chars)
/// - com `?query` / `#hash` (ignorados)
///
/// O código é base62 **case-sensitive** — a regex não usa `caseSensitive`.
final _invitePathPattern = RegExp(r'/invite/([A-Za-z0-9]+)');
final _codePattern = RegExp(r'^[A-Za-z0-9]+$');

/// Retorna o código extraído, ou null se a entrada não parecer um convite.
String? extractInviteCode(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return null;

  final match = _invitePathPattern.firstMatch(input);
  if (match != null) return match.group(1);

  // Fallback: último segmento de path (sem query/hash) parecido com código.
  final withoutQuery = input.split('?').first.split('#').first;
  final lastSegment = withoutQuery.split('/').last;
  if (_codePattern.hasMatch(lastSegment)) return lastSegment;

  // Fallback final: a entrada inteira é um código puro.
  return _codePattern.hasMatch(input) ? input : null;
}
