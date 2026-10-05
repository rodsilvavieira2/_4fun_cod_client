import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../storage/chat_attachments.dart';
import '../app_icon.dart';
import '../ds_tokens.dart';

/// Dropzone de anexos do chat (linux/windows): envolve o composer e aceita
/// qualquer arquivo até 61 MB via arrastar-e-soltar **e** Ctrl+V.
///
/// - **Drag:** [DropTarget] do `desktop_drop`; enquanto arrasta mostra o
///   overlay tracejado (accent + ícone + texto). No drop lê os paths em
///   background, valida (nome/teto/0 bytes/>61MB) e chama [onFiles] só com
///   os válidos; erros vão p/ [onError] (o chamador mostra `SnackBar`).
/// - **Paste:** [Focus.onKeyEvent] observa Ctrl+V sem consumir: o TextField
///   cola texto nativamente e este handler anexa `Pasteboard.image`
///   (vira `colado-<ts>.png`) + `Pasteboard.files` (paths do clipboard).
///   Quando arquivos são anexados, os paths colados como texto são
///   removidos de [controller] (post-frame, após a cola nativa).
/// - O dono dos slots continua sendo o chamador (ele guarda os bytes e
///   decide quando limpar — igual ao `_attachments` do `_ChatComposer`).
class ChatAttachmentDropzone extends StatefulWidget {
  const ChatAttachmentDropzone({
    super.key,
    required this.child,
    required this.onFiles,
    required this.onError,
    this.controller,
    this.currentCount = 0,
    this.enabled = true,
  });

  final Widget child;

  /// Arquivos válidos já lidos (bytes em mãos), prontos p/ virar slot.
  final ValueChanged<List<PendingAttachment>> onFiles;

  /// Uma mensagem por lote inválido (o chamador exibe via `SnackBar`).
  final ValueChanged<String> onError;

  /// Controller do composer: p/ limpar os paths colados nativamente no
  /// Ctrl+V com arquivos (cola só-texto nunca é tocada).
  final TextEditingController? controller;

  /// Slots já no composer (p/ validar o teto de 10 antes de ler bytes).
  final int currentCount;

  final bool enabled;

  @override
  State<ChatAttachmentDropzone> createState() => ChatAttachmentDropzoneState();
}

/// Estado público p/ o composer disparar a cola via `GlobalKey`
/// (o `Focus` ancestral do dropzone pode não ver a tecla em algumas
/// cadeias de foco; o hook `onPasteKey` do `AppChatInput` sempre vê).
class ChatAttachmentDropzoneState extends State<ChatAttachmentDropzone> {
  bool _dragging = false;
  bool _reading = false;

  Future<void> _addPaths(List<String> paths) async {
    if (!widget.enabled || _reading || paths.isEmpty) return;
    setState(() => _reading = true);
    try {
      final ok = <PendingAttachment>[];
      var count = widget.currentCount;
      for (final path in paths) {
        final file = File(path);
        final name = path.split(Platform.pathSeparator).last;
        int size;
        try {
          size = await file.length();
        } catch (_) {
          widget.onError('$name: não foi possível ler o arquivo.');
          continue;
        }
        final error = validateAttachmentFile(
          fileName: name,
          sizeBytes: size,
          currentCount: count,
        );
        if (error != null) {
          widget.onError(error);
          continue;
        }
        // 61 MB em RAM por arquivo: leitura única aqui; o slot guarda os
        // bytes até o enviar (mesmo padrão do `_pickImages` anterior).
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        final capped = validateAttachmentFile(
          fileName: name,
          sizeBytes: bytes.length,
          currentCount: count,
        );
        if (capped != null) {
          widget.onError(capped);
          continue;
        }
        ok.add(
          PendingAttachment(
            bytes: bytes,
            fileName: name,
            contentType: contentTypeForAnyFile(name),
          ),
        );
        count++;
      }
      if (ok.isNotEmpty && mounted) widget.onFiles(ok);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// Ctrl+V: imagem do clipboard vira PNG + arquivos copiados (paths) +
  /// fallback de texto (paths colados como `text/plain` quando o plugin
  /// nativo não enxerga URIs). Silencioso quando não há arquivo/imagem
  /// (o TextField cola o texto normalmente — nunca consome a tecla).
  /// Chamadas concorrentes são ignoradas via [_reading].
  Future<void> triggerPaste() async {
    if (!widget.enabled || _reading) return;
    setState(() => _reading = true);
    try {
      final ok = <PendingAttachment>[];
      final attachedPaths = <String>[];
      var count = widget.currentCount;
      // Imagem (screenshot/print): sem nome — gera `colado-<ts>.png`.
      final image = await Pasteboard.image;
      if (image != null && image.isNotEmpty) {
        final name =
            'colado-${DateTime.now().millisecondsSinceEpoch}.png';
        final error = validateAttachmentFile(
          fileName: name,
          sizeBytes: image.length,
          currentCount: count,
        );
        if (error != null) {
          widget.onError(error);
        } else {
          ok.add(
            PendingAttachment(
              bytes: image,
              fileName: name,
              contentType: 'image/png',
            ),
          );
          count++;
        }
      }
      // Arquivos copiados no gerenciador (Ctrl+C no Explorer/Nautilus).
      final paths = await Pasteboard.files();
      for (final path in paths) {
        if (attachedPaths.contains(path)) continue;
        if (count >= kMaxChatAttachments) {
          widget.onError(
            'Limite de $kMaxChatAttachments anexos por mensagem.',
          );
          break;
        }
        final pending = await _readPathFile(path, count);
        if (pending == null) continue;
        if (!mounted) return;
        ok.add(pending);
        attachedPaths.add(path);
        count++;
      }
      // Fallback: clipboard só com texto que são paths existentes.
      // `parseFilePathsFromText` exige TODAS as linhas como arquivos —
      // texto misto nunca é tocado.
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final clipText = clip?.text ?? '';
      if (clipText.trim().isNotEmpty) {
        for (final path in parseFilePathsFromText(clipText)) {
          if (attachedPaths.contains(path)) continue;
          if (count >= kMaxChatAttachments) {
            widget.onError(
              'Limite de $kMaxChatAttachments anexos por mensagem.',
            );
            break;
          }
          final pending = await _readPathFile(path, count);
          if (pending == null) continue;
          if (!mounted) return;
          ok.add(pending);
          attachedPaths.add(path);
          count++;
        }
      }
      // Clipboard só com texto (ou vazio): silêncio — o TextField já
      // colou o texto nativamente; sem SnackBar espúrio.
      if (ok.isEmpty) return;
      final pastedPaths = List<String>.of(attachedPaths);
      if (mounted) widget.onFiles(ok);
      // Paths de gerenciador colados como texto no mesmo Ctrl+V: limpa do
      // input em post-frame (a cola nativa já aconteceu — a leitura dos
      // bytes é mais lenta que o paste do TextField).
      if (pastedPaths.isNotEmpty) _stripPathsPostFrame(pastedPaths);
    } catch (_) {
      if (mounted) widget.onError('Não foi possível colar o arquivo.');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  /// Lê/valida um path do disco. `null` = ilegível ou inválido (erro de
  /// validação já reportado via [onError]; ilegível é silencioso p/ não
  /// spammar quando o clipboard tem paths estranhos).
  Future<PendingAttachment?> _readPathFile(
    String path,
    int currentCount,
  ) async {
    final file = File(path);
    final name = path.split(Platform.pathSeparator).last;
    int size;
    try {
      size = await file.length();
    } catch (_) {
      return null;
    }
    final error = validateAttachmentFile(
      fileName: name,
      sizeBytes: size,
      currentCount: currentCount,
    );
    if (error != null) {
      widget.onError(error);
      return null;
    }
    final bytes = await file.readAsBytes();
    return PendingAttachment(
      bytes: bytes,
      fileName: name,
      contentType: contentTypeForAnyFile(name),
    );
  }

  void _stripPathsPostFrame(List<String> paths) {
    final controller = widget.controller;
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cleaned = stripPastedPaths(controller.text, paths);
      if (cleaned == controller.text) return;
      controller.value = controller.value.copyWith(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
        composing: TextRange.empty,
      );
    });
  }

  /// Observa Ctrl+V sem consumir: o TextField cola texto nativamente e
  /// este handler anexa arquivos/imagens em paralelo (mesmo evento).
  /// O composer também dispara [triggerPaste] via `onPasteKey` do
  /// `AppChatInput` (cadeia de foco garantida); concorrência dedupada por
  /// [_reading].
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.keyV) {
      return KeyEventResult.ignored;
    }
    if (!HardwareKeyboard.instance.isControlPressed) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    triggerPaste();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKey,
      child: DropTarget(
        enable: widget.enabled,
        onDragEntered: (_) {
          if (!widget.enabled) return;
          setState(() => _dragging = true);
        },
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          _addPaths(details.files.map((f) => f.path).toList());
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            if (_dragging)
              Positioned.fill(child: _DropOverlay(reading: _reading)),
            if (_reading && !_dragging)
              const Positioned(
                right: 12,
                bottom: 12,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Feedback visual durante o arrasto: véu accent + borda tracejada +
/// ícone e texto (padrão dark do app, fonte Geist).
class _DropOverlay extends StatelessWidget {
  const _DropOverlay({this.reading = false});

  final bool reading;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          color: AppTokens.accentVercel.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: AppTokens.accentVercel.withValues(alpha: 0.8),
            width: 1.5,
          ),
        ),
        alignment: Alignment.center,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.image,
                  size: 28,
                  color: AppTokens.textPrimary,
                ),
                const SizedBox(height: 10),
                Text(
                  reading ? 'Lendo arquivos…' : 'Solte para anexar',
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Qualquer arquivo até 61 MB • máx. 10 por mensagem',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    color: AppTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
