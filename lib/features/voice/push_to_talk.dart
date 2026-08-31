import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Tipo de entrada aceito pelo Push to Talk.
enum PushToTalkBindingKind { keyboard, mouse }

enum PushToTalkInputEvent { pressed, released, failed }

/// Atalho persistível e independente da UI para Push to Talk.
///
/// Teclas são identificadas pelo uso USB HID para não mudarem quando o layout
/// do teclado muda. Os botões de mouse são deliberadamente limitados aos que
/// não interferem com cliques normais da aplicação.
class PushToTalkBinding {
  const PushToTalkBinding.keyboard({
    required this.physicalKeyUsage,
    required this.label,
    this.control = false,
    this.alt = false,
    this.shift = false,
  }) : kind = PushToTalkBindingKind.keyboard,
       mouseButton = null;

  const PushToTalkBinding.mouse({
    required this.mouseButton,
    required this.label,
  }) : kind = PushToTalkBindingKind.mouse,
       physicalKeyUsage = null,
       control = false,
       alt = false,
       shift = false;

  final PushToTalkBindingKind kind;
  final int? physicalKeyUsage;
  final int? mouseButton;
  final String label;
  final bool control;
  final bool alt;
  final bool shift;

  Map<String, Object> toJson() => {
    'kind': kind.name,
    'physicalKeyUsage': ?physicalKeyUsage,
    'mouseButton': ?mouseButton,
    'label': label,
    'control': control,
    'alt': alt,
    'shift': shift,
  };

  static PushToTalkBinding? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final kind = switch (json['kind']) {
      'keyboard' => PushToTalkBindingKind.keyboard,
      'mouse' => PushToTalkBindingKind.mouse,
      _ => null,
    };
    if (kind == null) return null;
    final label = json['label'];
    if (label is! String || label.isEmpty) return null;
    if (kind == PushToTalkBindingKind.keyboard) {
      final usage = json['physicalKeyUsage'];
      if (usage is! int || usage <= 0) return null;
      return PushToTalkBinding.keyboard(
        physicalKeyUsage: usage,
        label: label,
        control: json['control'] == true,
        alt: json['alt'] == true,
        shift: json['shift'] == true,
      );
    }
    final button = json['mouseButton'];
    if (!isRecordableMouseButton(button)) return null;
    return PushToTalkBinding.mouse(mouseButton: button, label: label);
  }

  /// Retorna o nome apresentado no modal e nas tooltips.
  String get displayLabel {
    if (kind == PushToTalkBindingKind.mouse) return label;
    final modifiers = <String>[
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
    ];
    return [...modifiers, label].join(' + ');
  }

  bool matchesKey(KeyEvent event) {
    if (kind != PushToTalkBindingKind.keyboard ||
        event.physicalKey.usbHidUsage != physicalKeyUsage) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isControlPressed == control &&
        keyboard.isAltPressed == alt &&
        keyboard.isShiftPressed == shift &&
        !keyboard.isMetaPressed;
  }

  bool matchesPointer(PointerEvent event) =>
      kind == PushToTalkBindingKind.mouse && event.buttons == mouseButton;

  @override
  bool operator ==(Object other) =>
      other is PushToTalkBinding &&
      other.kind == kind &&
      other.physicalKeyUsage == physicalKeyUsage &&
      other.mouseButton == mouseButton &&
      other.control == control &&
      other.alt == alt &&
      other.shift == shift;

  @override
  int get hashCode =>
      Object.hash(kind, physicalKeyUsage, mouseButton, control, alt, shift);
}

PushToTalkBinding? bindingFromKeyEvent(KeyEvent event) {
  if (event is! KeyDownEvent || event is KeyRepeatEvent) return null;
  if (_isModifier(event.logicalKey) ||
      HardwareKeyboard.instance.isMetaPressed) {
    return null;
  }
  final label = event.logicalKey.keyLabel;
  if (label.isEmpty || event.physicalKey.usbHidUsage == 0) return null;
  return PushToTalkBinding.keyboard(
    physicalKeyUsage: event.physicalKey.usbHidUsage,
    label: label.toUpperCase(),
    control: HardwareKeyboard.instance.isControlPressed,
    alt: HardwareKeyboard.instance.isAltPressed,
    shift: HardwareKeyboard.instance.isShiftPressed,
  );
}

PushToTalkBinding? bindingFromMouseButton(int buttons) {
  if (!isRecordableMouseButton(buttons)) return null;
  return PushToTalkBinding.mouse(
    mouseButton: buttons,
    label: switch (buttons) {
      kMiddleMouseButton => 'Botão do meio',
      kBackMouseButton => 'Botão voltar',
      kForwardMouseButton => 'Botão avançar',
      _ => 'Botão do mouse',
    },
  );
}

bool isRecordableMouseButton(Object? buttons) =>
    buttons == kMiddleMouseButton ||
    buttons == kBackMouseButton ||
    buttons == kForwardMouseButton;

bool _isModifier(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.control ||
    key == LogicalKeyboardKey.controlLeft ||
    key == LogicalKeyboardKey.controlRight ||
    key == LogicalKeyboardKey.alt ||
    key == LogicalKeyboardKey.altLeft ||
    key == LogicalKeyboardKey.altRight ||
    key == LogicalKeyboardKey.shift ||
    key == LogicalKeyboardKey.shiftLeft ||
    key == LogicalKeyboardKey.shiftRight ||
    key == LogicalKeyboardKey.meta ||
    key == LogicalKeyboardKey.metaLeft ||
    key == LogicalKeyboardKey.metaRight;
