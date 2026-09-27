/// Embed efêmero de link (OpenGraph via `GET /unfurl`).
///
/// Não persiste no banco: o server emite via `message.updated` com
/// `{ ...message, embeds }` e o client refaz via `GET /unfurl?url=` para o
/// histórico. `null` (desconhecido) = ainda resolvendo; `[]` = sem cards.
class LinkEmbed {
  const LinkEmbed({
    required this.url,
    required this.siteName,
    required this.title,
    required this.description,
    this.imageUrl,
  });

  factory LinkEmbed.fromJson(Map<String, dynamic> json) => LinkEmbed(
    url: json['url'] as String? ?? '',
    siteName: json['siteName'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    imageUrl: json['imageUrl'] as String?,
  );

  final String url;
  final String siteName;
  final String title;
  final String description;
  final String? imageUrl;

  bool get hasTitle => title.trim().isNotEmpty;
}
