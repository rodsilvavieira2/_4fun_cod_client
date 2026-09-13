import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../theme/appearance_theme.dart';
import 'app_file_image.dart';
import 'ds_tokens.dart';
import 'menus/app_menu.dart';

/// Menu de botão direito das imagens do chat (inline e lightbox).
///
/// - Copiar imagem: baixa os bytes pelo proxy autenticado, grava num
///   temporário e coloca o **arquivo** na área de transferência
///   (`Pasteboard.writeFiles`) — `Clipboard.setData` do framework só
///   carrega texto, não bytes de imagem.
/// - Salvar imagem: mesmos bytes, diálogo nativo (`file_selector`).
Future<void> showChatImageMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Offset globalPosition,
  required String url,
  String? suggestedName,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  final colors = context.appColors;
  final selection = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    // Padrão compacto do app (AppMenu): mesma superfície/itens dos demais
    // menus, em vez dos defaults espaçosos do Material.
    color: colors.surface2,
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: BorderSide(color: colors.borderSubtle, width: 1),
    ),
    menuPadding: AppMenu.menuPadding,
    constraints: const BoxConstraints(
      minWidth: AppMenu.minWidth,
      maxWidth: AppMenu.maxWidth,
    ),
    items: [
      AppMenuItem.labeled(
        value: 'copy',
        label: 'Copiar imagem',
        icon: Icons.copy_outlined,
      ),
      AppMenuItem.labeled(
        value: 'save',
        label: 'Salvar imagem',
        icon: Icons.download_outlined,
      ),
    ],
  );
  if (!context.mounted) return;
  switch (selection) {
    case 'copy':
      await copyChatImage(context: context, ref: ref, url: url);
    case 'save':
      await saveChatImage(
        context: context,
        ref: ref,
        url: url,
        suggestedName: suggestedName,
      );
  }
}

/// Baixa os bytes da imagem (proxy autenticado) para copiar/salvar.
Future<Uint8List?> _chatImageBytes(WidgetRef ref, String url) async {
  final absolute = resolveFileUrl(
    ref.read(appConfigProvider).apiRestBaseUrl,
    url,
  );
  try {
    return await ref.read(fileImageBytesProvider(absolute).future);
  } catch (_) {
    return null;
  }
}

void _snack(ScaffoldMessengerState messenger, String text) {
  messenger.showSnackBar(SnackBar(content: Text(text)));
}

/// Extensão honesta para o arquivo temporário/salvo (sniff de magic bytes).
String _extensionFor(Uint8List bytes, String fallbackName) {
  final dot = fallbackName.lastIndexOf('.');
  if (dot > 0 && fallbackName.length - dot <= 6) {
    return fallbackName.substring(dot);
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return '.jpg';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return '.gif';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return '.webp';
  }
  return '.png';
}

/// Copia os bytes da imagem via arquivo temporário.
Future<void> copyChatImage({
  required BuildContext context,
  required WidgetRef ref,
  required String url,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final bytes = await _chatImageBytes(ref, url);
  if (bytes == null || bytes.isEmpty) {
    _snack(messenger, 'Falha ao copiar imagem.');
    return;
  }
  try {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/chat-imagem-${DateTime.now().millisecondsSinceEpoch}'
      '${_extensionFor(bytes, url)}',
    );
    await file.writeAsBytes(bytes, flush: true);
    await Pasteboard.writeFiles([file.path]);
    _snack(messenger, 'Imagem copiada.');
  } catch (_) {
    _snack(messenger, 'Falha ao copiar imagem.');
  }
}

/// Salva os bytes da imagem com diálogo nativo (linux/windows).
Future<void> saveChatImage({
  required BuildContext context,
  required WidgetRef ref,
  required String url,
  String? suggestedName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final bytes = await _chatImageBytes(ref, url);
  if (bytes == null || bytes.isEmpty) {
    _snack(messenger, 'Falha ao salvar imagem.');
    return;
  }
  final ext = _extensionFor(bytes, suggestedName ?? url);
  final name = suggestedName ?? 'imagem';
  final withExt = name.endsWith(ext) ? name : '$name$ext';
  try {
    final location = await getSaveLocation(suggestedName: withExt);
    if (location == null) return;
    await File(location.path).writeAsBytes(bytes, flush: true);
    _snack(messenger, 'Imagem salva.');
  } catch (_) {
    _snack(messenger, 'Falha ao salvar imagem.');
  }
}
