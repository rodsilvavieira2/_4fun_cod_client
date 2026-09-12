import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_icon_button.dart';
import '../ds_tokens.dart';

/// Composer de chat compartilhado (canais + DMs).
///
/// - **Superfície única:** o [TextField] interno não pinta fill próprio
///   (`filled: false` + bordas `none`), então só o container pinta — sem o
///   tom duplo que o `inputDecorationTheme` + overlays de hover/focus do
///   Material causavam na área digitável.
/// - **Enter envia**, **Shift+Enter** (ou Ctrl/Alt/Meta+Enter) quebra linha.
/// - Expande até [maxLines] e rola a partir daí; o botão de envio nunca
///   rouba o foco ([AppIconButton] é [GestureDetector], não [IconButton]).
class AppChatInput extends StatefulWidget {
  const AppChatInput({
    super.key,
    required this.controller,
    required this.onSend,
    this.hintText = 'Digite sua mensagem…',
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 5,
    this.sendTooltip = 'Enviar mensagem',
    this.sendActiveColor = AppTokens.accentVercel,
    this.leadingActions = const [],
    this.trailingActions = const [],
    this.topPanel,
    this.canSendEmpty = false,
    this.onKeyEvent,
  });

  /// Dono do texto continua sendo o chamador (ele lê via [onSend] e decide
  /// quando limpar — ex: o chat limpa só após o envio ao servidor).
  final TextEditingController controller;

  /// Recebe o texto já aparado.
  final ValueChanged<String> onSend;

  final String hintText;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final String sendTooltip;
  final Color sendActiveColor;
  final List<Widget> leadingActions;
  final List<Widget> trailingActions;
  final Widget? topPanel;
  final bool canSendEmpty;
  final FocusOnKeyEventCallback? onKeyEvent;

  @override
  State<AppChatInput> createState() => _AppChatInputState();
}

class _AppChatInputState extends State<AppChatInput> {
  late final FocusNode _focusNode = FocusNode(onKeyEvent: _handleKey);
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_syncFocus);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_syncFocus)
      ..dispose();
    super.dispose();
  }

  void _syncFocus() => setState(() => _focused = _focusNode.hasFocus);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final externalResult = widget.onKeyEvent?.call(node, event);
    if (externalResult != null && externalResult != KeyEventResult.ignored) {
      return externalResult;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (!widget.enabled) return KeyEventResult.ignored;
    final mods = HardwareKeyboard.instance;
    final onlyShift =
        mods.isShiftPressed &&
        !mods.isControlPressed &&
        !mods.isAltPressed &&
        !mods.isMetaPressed;
    if (onlyShift) {
      // Quebra de linha manual: determinística no app e nos testes
      // (o default do framework para Enter via teclado físico não é
      // garantido fora de dispositivo real).
      _insertNewline();
      return KeyEventResult.handled;
    }
    if (mods.isShiftPressed ||
        mods.isControlPressed ||
        mods.isAltPressed ||
        mods.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    _submit();
    return KeyEventResult.handled;
  }

  void _insertNewline() {
    final value = widget.controller.value;
    final start = value.selection.start >= 0
        ? value.selection.start
        : value.text.length;
    final end = value.selection.end >= 0
        ? value.selection.end
        : value.text.length;
    widget.controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  void _submit() {
    if (!widget.enabled) return;
    final text = widget.controller.text.trim();
    if (text.isEmpty && !widget.canSendEmpty) return;
    widget.onSend(text);
    setState(() {}); // atualiza o estado do botão de envio
    if (_focusNode.canRequestFocus) _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        widget.enabled &&
        (widget.controller.text.trim().isNotEmpty || widget.canSendEmpty);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.topPanel != null) ...[
              widget.topPanel!,
              const SizedBox(height: 8),
            ],
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              constraints: const BoxConstraints(minHeight: 46),
              decoration: BoxDecoration(
                color: AppTokens.surface2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: _focused
                      ? AppTokens.borderFocus
                      : AppTokens.borderStrong,
                  width: _focused ? 1.2 : 1.0,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x44000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (widget.leadingActions.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: widget.leadingActions,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ] else
                      const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        enabled: widget.enabled,
                        autofocus: widget.autofocus,
                        minLines: 1,
                        maxLines: widget.maxLines,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(
                          fontFamily: 'Geist',
                          fontSize: 13.5,
                          color: AppTokens.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          hintStyle: const TextStyle(
                            fontFamily: 'Geist',
                            fontSize: 13.5,
                            color: AppTokens.textMuted,
                          ),
                          // Superfície única: só o container pinta.
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 0,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (widget.trailingActions.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: widget.trailingActions,
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: AppIconButton(
                        icon: Icons.arrow_upward,
                        tooltip: widget.sendTooltip,
                        minSize: 30,
                        iconSize: 16,
                        isActive: canSubmit,
                        activeColor: widget.sendActiveColor,
                        onPressed: canSubmit ? _submit : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
