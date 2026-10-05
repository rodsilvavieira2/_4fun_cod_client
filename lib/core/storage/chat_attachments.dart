import 'dart:io';
import 'dart:typed_data';

/// Anexos de mensagem (chat): qualquer arquivo até 61 MB.
///
/// Centraliza o que `_ChatComposer`, `ChatAttachmentDropzone` e o futuro
/// composer de DMs usam: teto de tamanho, content-type por extensão e
/// validação com mensagens prontas p/ `SnackBar` (pt-BR, padrão do app).
///
/// Espelha `MAX_MESSAGE_FILE_BYTES` do servidor
/// (`_4fun_cod_server/src/storage/image-file.util.ts`): o client barra
/// antes de ler bytes; o servidor revalida (fronteira de confiança).
const maxMessageFileBytes = 61 * 1024 * 1024;

/// Teto de anexos por mensagem (mesmo do `CreateMessageDto`, 1-10).
const kMaxChatAttachments = 10;

/// Extensões de imagem com preview inline (as demais viram card de arquivo).
const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'gif'};

/// Content-type por extensão (casos comuns; resto cai em
/// `application/octet-stream` — o servidor preserva o que o client mandar,
///
/// mas revalida magic bytes p/ imagens).
String contentTypeForAnyFile(String fileName) {
  final lower = fileName.toLowerCase();
  final dot = lower.lastIndexOf('.');
  final ext = dot >= 0 ? lower.substring(dot + 1) : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'pdf' => 'application/pdf',
    'zip' => 'application/zip',
    'txt' || 'md' => 'text/plain',
    'json' => 'application/json',
    'mp3' => 'audio/mpeg',
    'mp4' => 'video/mp4',
    'wav' => 'audio/wav',
    'ogg' => 'audio/ogg',
    _ => 'application/octet-stream',
  };
}

/// `true` se o arquivo tem preview de imagem inline.
bool isImageFileName(String fileName) {
  final lower = fileName.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot < 0) return false;
  return _imageExtensions.contains(lower.substring(dot + 1));
}

/// Valida um arquivo antes de virar slot do composer.
///
/// Retorna a mensagem de erro (pt-BR) ou `null` se ok. Checa nesta ordem:
/// nome vazio → teto de 10 → tamanho 0 → > 61 MB.
String? validateAttachmentFile({
  required String fileName,
  required int sizeBytes,
  required int currentCount,
}) {
  final trimmed = fileName.trim();
  if (trimmed.isEmpty) return 'Arquivo sem nome não pode ser anexado.';
  if (currentCount >= kMaxChatAttachments) {
    return 'Limite de $kMaxChatAttachments anexos por mensagem.';
  }
  if (sizeBytes <= 0) return '$trimmed: arquivo vazio.';
  if (sizeBytes > maxMessageFileBytes) {
    return '$trimmed: máximo de 61 MB (tem ${formatFileSize(sizeBytes)}).';
  }
  return null;
}

/// `12.4 MB`, `800 KB`, `512 B` — rótulos do card de arquivo e dos erros.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${_trim(bytes / 1024)} KB';
  }
  return '${_trim(bytes / (1024 * 1024))} MB';
}

String _trim(double v) {
  final s = v.toStringAsFixed(v < 10 ? 1 : 0);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Extrai paths de arquivo de um texto colado (fallback do Ctrl+V).
///
/// Quando o gerenciador de arquivos põe só `text/plain` no clipboard (sem
/// URIs — o `Pasteboard.files()` volta vazio mas o TextField cola o path),
/// este parser recupera os arquivos. Só retorna paths se TODAS as linhas
/// não-vazias forem paths absolutos existentes: texto misto nunca é tocado
/// (evita anexar `/etc/hosts` de um snippet colado, por exemplo).
///
/// `exists` é injetável p/ testes (default `File.existsSync`).
List<String> parseFilePathsFromText(
  String text, {
  bool Function(String path)? exists,
}) {
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return [];
  final existsFn = exists ?? (p) => File(p).existsSync();
  final out = <String>[];
  for (var line in lines) {
    // Aspas de paths com espaço (Nautilus/Explorer colam assim às vezes).
    if (line.length > 1 &&
        ((line.startsWith('"') && line.endsWith('"')) ||
            (line.startsWith("'") && line.endsWith("'")))) {
      line = line.substring(1, line.length - 1);
    }
    var path = line;
    if (path.startsWith('file://')) {
      try {
        path = Uri.decodeFull(Uri.parse(path).toFilePath());
      } catch (_) {
        return [];
      }
    }
    if (!_isAbsolutePath(path) || !existsFn(path)) return [];
    out.add(path);
  }
  return out;
}

bool _isAbsolutePath(String p) {
  if (p.startsWith('/')) return true;
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(p)) return true;
  if (p.startsWith(r'\\')) return true;
  return false;
}

/// Remove do texto do composer os paths colados nativamente junto do Ctrl+V.
///
/// Quando o arquivo vem do gerenciador (Ctrl+C no Nautilus/Explorer), o
/// clipboard tem `text/uri-list` além dos arquivos: o TextField cola o path
/// como texto no mesmo evento em que o dropzone anexa os bytes. Só chama
/// quando `paths` não-vazio (cola só-texto nunca é tocada).
///
/// Cobre: path exato, variante `file://`, entre aspas simples/duplas e um
/// por linha. Colapsa linhas em branco resultantes e faz trim das pontas —
/// o cursor o chamador reposiciona (fim do texto limpo).
String stripPastedPaths(String text, List<String> paths) {
  var out = text;
  for (final path in paths) {
    if (path.isEmpty) continue;
    // file:// + path com %20 (Nautilus cola assim em alguns casos).
    // Ordem: variantes mais longas primeiro — o path puro é substring da
    // uri (`file:///home/a/b.png` contém `/home/a/b.png`) e remover ele
    // antes deixaria `file://` residual.
    final uri = Uri.file(path).toString();
    final variants = {path, uri, Uri.decodeFull(uri)}.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final variant in variants) {
      out = out.replaceAll('"$variant"', '');
      out = out.replaceAll("'$variant'", '');
      out = out.replaceAll(variant, '');
    }
  }
  final lines = out
      .split('\n')
      .map((l) => l.trimRight())
      .where((l) => l.trim().isNotEmpty)
      .toList();
  return lines.join('\n');
}

/// Slot genérico do composer (upload-no-enviar): bytes vivem SÓ aqui até
/// o enviar; o `POST /uploads` roda em `ChatController.sendAttachments`.
class PendingAttachment {
  PendingAttachment({
    required this.bytes,
    required this.fileName,
    required this.contentType,
    this.isSpoiler = false,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
  final bool isSpoiler;

  int get sizeBytes => bytes.length;

  bool get isImage => isImageFileName(fileName);

  PendingAttachment copyWith({String? fileName, bool? isSpoiler}) {
    return PendingAttachment(
      bytes: bytes,
      fileName: fileName ?? this.fileName,
      contentType: contentType,
      isSpoiler: isSpoiler ?? this.isSpoiler,
    );
  }
}
