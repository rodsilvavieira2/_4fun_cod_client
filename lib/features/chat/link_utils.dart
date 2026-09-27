/// Detecção de URLs para link embeds (espelho do server
/// `link-extract.util.ts`: só `http(s)`, max 3, dedupe, sem `/invite/`).
const maxLinksPerMessage = 3;
final _urlRegex = RegExp('https?://[^\\s<>"\')\\]]+');
final _trailingPunct = RegExp(r'[.,;:!?)\]}>]+$');
const _inviteSegment = '/invite/';

/// URLs http(s) do texto, na ordem de aparição (max 3, sem duplicadas).
List<String> extractHttpUrls(String text) {
  if (text.isEmpty) return const [];
  final found = <String>[];
  final seen = <String>{};
  for (final match in _urlRegex.allMatches(text)) {
    var url = match.group(0)!;
    url = url.replaceAll(_trailingPunct, '');
    if (url.isEmpty || url.length > 2048) continue;
    final uri = Uri.tryParse(url);
    if (uri == null) continue;
    if (uri.scheme != 'http' && uri.scheme != 'https') continue;
    if (uri.host.isEmpty) continue;
    if (url.contains(_inviteSegment)) continue;
    if (!seen.add(url)) continue;
    found.add(url);
    if (found.length >= maxLinksPerMessage) break;
  }
  return found;
}

/// A mensagem tem ao menos um link unfurlável?
bool hasUnfurlableLink(String text) => extractHttpUrls(text).isNotEmpty;

/// Parte do texto: menção, link ou texto puro (para o rich text do chat).
class LinkTextPart {
  const LinkTextPart({required this.text, this.isMention = false, this.linkUrl});

  final String text;
  final bool isMention;
  final String? linkUrl;

  bool get isLink => linkUrl != null;
}
