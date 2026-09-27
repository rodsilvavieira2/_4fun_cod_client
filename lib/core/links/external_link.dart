import 'package:url_launcher/url_launcher.dart';

/// Abre URL no navegador externo (linux/windows via xdg-open/shell).
/// Retorna `false` quando a URL é inválida ou o SO recusou.
Future<bool> openExternalLink(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null || !uri.hasScheme) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
