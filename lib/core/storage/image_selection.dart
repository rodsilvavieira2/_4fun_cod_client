import 'package:file_selector/file_selector.dart';

/// Seleção de imagens do chat (linux/windows via `file_selector`).
///
/// Centraliza o trio que avatar/ícone duplicam (`XTypeGroup` + content-type
/// por extensão + teto de 5MB, igual ao `MAX_IMAGE_BYTES` do servidor):
/// novas telas usam daqui; as existentes migram quando tocadas.
const imageTypeGroup = XTypeGroup(
  label: 'images',
  extensions: ['jpg', 'jpeg', 'png', 'webp'],
  mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
);

/// Teto por arquivo (alinha com `MAX_IMAGE_BYTES` do servidor).
const maxImageBytes = 5 * 1024 * 1024;

/// Content-type pelos 3 formatos do pipeline (rejeita o resto).
String? contentTypeForFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return null;
}
