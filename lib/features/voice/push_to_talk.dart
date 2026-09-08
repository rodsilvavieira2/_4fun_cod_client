import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Tipo de entrada aceito pelo Push to Talk.
enum PushToTalkBindingKind { keyboard, mouse }

enum PushToTalkInputEvent { pressed, released, failed }

/// Resultado da configuração do atalho global no backend da plataforma.
///
/// Substitui o `bool` opaco: backends que não suportam um tipo de binding
/// (ex.: mouse com modificadores no Linux) recusam explicitamente em vez de
/// fingir um registro que nunca dispararia.
enum PushToTalkConfigError {
  /// Tecla/botão não suportado pelo backend (ex.: sem mapeamento físico).
  unsupportedKey,

  /// Atalho já em uso por outro aplicativo/sessão.
  conflicting,

  /// Falha genérica de registro (hook, portal, permissão).
  registrationFailed,
}

/// Resultado tipado de [PushToTalkBackend.configure].
sealed class PushToTalkConfigResult {
  const PushToTalkConfigResult();

  bool get isOk => this is PushToTalkConfigOk;

  PushToTalkConfigError? get error => switch (this) {
    PushToTalkConfigOk() => null,
    PushToTalkConfigFailed(:final error) => error,
  };

  String? get message => switch (this) {
    PushToTalkConfigOk() => null,
    PushToTalkConfigFailed(:final message) => message,
  };

  const factory PushToTalkConfigResult.ok() = PushToTalkConfigOk;

  const factory PushToTalkConfigResult.failed(
    PushToTalkConfigError error, [
    String? message,
  ]) = PushToTalkConfigFailed;
}

class PushToTalkConfigOk extends PushToTalkConfigResult {
  const PushToTalkConfigOk();
}

class PushToTalkConfigFailed extends PushToTalkConfigResult {
  const PushToTalkConfigFailed(this.error, [this.message]);

  @override
  final PushToTalkConfigError error;

  @override
  final String? message;
}

/// Atalho persistível e independente da UI para Push to Talk (modelo v2).
///
/// - `kind == keyboard` com [physicalKeyUsage] não-nulo: tecla física (uso USB
///   HID com página, ex. `0x00070004`) + modificadores `Ctrl`/`Alt`/`Shift`.
///   Qualquer ordem de pressionamento vale; a confirmação acontece ao soltar.
/// - `kind == keyboard` com [physicalKeyUsage] nulo: SÓ modificadores
///   (`Ctrl`, `Alt` ou `Ctrl+Alt` isolados — `Shift` sozinho é rejeitado na
///   captura). Suporte real depende do backend (Windows + fallback em foco).
/// - `kind == mouse`: botão do meio/voltar/avançar, opcionalmente com
///   modificadores (Windows; o Linux recusa com erro explícito).
///
/// Teclas são identificadas pelo uso USB HID para não mudarem quando o layout
/// do teclado muda. Os botões de mouse são deliberadamente limitados aos que
/// não interferem com cliques normais da aplicação.
class PushToTalkBinding {
  const PushToTalkBinding.keyboard({
    this.physicalKeyUsage,
    required this.label,
    this.control = false,
    this.alt = false,
    this.shift = false,
  }) : kind = PushToTalkBindingKind.keyboard,
       mouseButton = null;

  const PushToTalkBinding.mouse({
    required this.mouseButton,
    required this.label,
    this.control = false,
    this.alt = false,
    this.shift = false,
  }) : kind = PushToTalkBindingKind.mouse,
       physicalKeyUsage = null;

  final PushToTalkBindingKind kind;

  /// Uso HID com página da tecla-gatilho, ou `null` para atalho só de
  /// modificadores (teclado). Nunca nulo em bindings persistidos v1.
  final int? physicalKeyUsage;
  final int? mouseButton;
  final String label;
  final bool control;
  final bool alt;
  final bool shift;

  /// Atalho só de modificadores: sem tecla-gatilho (ex.: `Ctrl` isolado).
  bool get isModifierOnly =>
      kind == PushToTalkBindingKind.keyboard && physicalKeyUsage == null;

  bool get hasModifiers => control || alt || shift;

  /// Uso HID sem a página (comparação com valores legados sem página).
  int? get triggerUsagePageLess {
    final usage = physicalKeyUsage;
    if (usage == null) return null;
    return (usage & 0xffff0000) == 0 ? usage : usage & 0xffff;
  }

  Map<String, Object> toJson() => {
    'v': 2,
    'kind': kind.name,
    'physicalKeyUsage': ?physicalKeyUsage,
    'mouseButton': ?mouseButton,
    'label': label,
    'control': control,
    'alt': alt,
    'shift': shift,
  };

  /// Lê v2 e migra v1 automaticamente (v1 não tem `v`; mouse v1 não tem
  /// modificadores; teclado v1 sempre tem `physicalKeyUsage > 0`).
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
    final control = json['control'] == true;
    final alt = json['alt'] == true;
    final shift = json['shift'] == true;
    if (kind == PushToTalkBindingKind.keyboard) {
      final usage = json['physicalKeyUsage'];
      if (usage == null) {
        // v2 só-modificadores: exige Ctrl e/ou Alt (nunca Shift sozinho).
        if (!(control || alt) || shift) return null;
        return PushToTalkBinding.keyboard(
          label: label,
          control: control,
          alt: alt,
        );
      }
      if (usage is! int || usage <= 0) return null;
      return PushToTalkBinding.keyboard(
        physicalKeyUsage: usage,
        label: label,
        control: control,
        alt: alt,
        shift: shift,
      );
    }
    final button = json['mouseButton'];
    if (!isRecordableMouseButton(button)) return null;
    return PushToTalkBinding.mouse(
      mouseButton: button as int,
      label: label,
      control: control,
      alt: alt,
      shift: shift,
    );
  }

  /// Retorna o nome apresentado no modal e nas tooltips.
  String get displayLabel {
    if (kind == PushToTalkBindingKind.mouse) {
      final modifiers = <String>[
        if (control) 'Ctrl',
        if (alt) 'Alt',
        if (shift) 'Shift',
      ];
      return [...modifiers, label].join(' + ');
    }
    final modifiers = <String>[
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
    ];
    if (isModifierOnly) return modifiers.join(' + ');
    return [...modifiers, label].join(' + ');
  }

  bool _modifiersMatch({
    required bool controlPressed,
    required bool altPressed,
    required bool shiftPressed,
    required bool metaPressed,
  }) {
    if (metaPressed) return false;
    return controlPressed == control &&
        altPressed == alt &&
        shiftPressed == shift;
  }

  bool matchesKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (isModifierOnly) {
      // Gatilho é o próprio modificador: o evento precisa ser down/up de um
      // modificador membro, com o estado exato (sem Shift extra, sem Meta).
      if (event is KeyRepeatEvent) return false;
      if (event is! KeyDownEvent && event is! KeyUpEvent) return false;
      if (!_isMemberModifier(event.logicalKey)) return false;
      return _modifiersMatch(
        controlPressed: keyboard.isControlPressed,
        altPressed: keyboard.isAltPressed,
        shiftPressed: keyboard.isShiftPressed,
        metaPressed: keyboard.isMetaPressed,
      );
    }
    if (kind != PushToTalkBindingKind.keyboard ||
        event.physicalKey.usbHidUsage != physicalKeyUsage) {
      return false;
    }
    return _modifiersMatch(
      controlPressed: keyboard.isControlPressed,
      altPressed: keyboard.isAltPressed,
      shiftPressed: keyboard.isShiftPressed,
      metaPressed: keyboard.isMetaPressed,
    );
  }

  bool _isMemberModifier(LogicalKeyboardKey key) {
    if (control &&
        (key == LogicalKeyboardKey.control ||
            key == LogicalKeyboardKey.controlLeft ||
            key == LogicalKeyboardKey.controlRight)) {
      return true;
    }
    if (alt &&
        (key == LogicalKeyboardKey.alt ||
            key == LogicalKeyboardKey.altLeft ||
            key == LogicalKeyboardKey.altRight)) {
      return true;
    }
    return false;
  }

  bool matchesPointer(PointerEvent event) {
    if (kind != PushToTalkBindingKind.mouse || event.buttons != mouseButton) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    return keyboard.isControlPressed == control &&
        keyboard.isAltPressed == alt &&
        keyboard.isShiftPressed == shift;
  }

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

PushToTalkBinding? bindingFromMouseButton(
  int buttons, {
  bool control = false,
  bool alt = false,
  bool shift = false,
}) {
  if (!isRecordableMouseButton(buttons)) return null;
  final base = switch (buttons) {
    kMiddleMouseButton => 'Botão do meio',
    kBackMouseButton => 'Botão voltar',
    kForwardMouseButton => 'Botão avançar',
    _ => 'Botão do mouse',
  };
  final modifiers = <String>[
    if (control) 'Ctrl',
    if (alt) 'Alt',
    if (shift) 'Shift',
  ];
  return PushToTalkBinding.mouse(
    mouseButton: buttons,
    label: [...modifiers, base].join(' + '),
    control: control,
    alt: alt,
    shift: shift,
  );
}

bool isRecordableMouseButton(Object? buttons) =>
    buttons == kMiddleMouseButton ||
    buttons == kBackMouseButton ||
    buttons == kForwardMouseButton;

bool isModifierKey(LogicalKeyboardKey key) =>
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

/// Nome de exibição/portal para teclas físicas cujo `keyLabel` lógico vem
/// vazio (setas, navegação, numpad). Numpad usa nomes XKB (`KP_1`), que o
/// portal Linux entende direto; `Page Up`/`Page Down`/`Caps Lock` são
/// traduzidos no runner Linux.
String? pttFallbackKeyLabel(int pageLessUsage) => switch (pageLessUsage) {
  0x39 => 'Caps Lock',
  0x49 => 'Insert',
  0x4a => 'Home',
  0x4b => 'Page Up',
  0x4c => 'Delete',
  0x4d => 'End',
  0x4e => 'Page Down',
  0x4f => 'Right',
  0x50 => 'Left',
  0x51 => 'Down',
  0x52 => 'Up',
  0x59 => 'KP_1',
  0x5a => 'KP_2',
  0x5b => 'KP_3',
  0x5c => 'KP_4',
  0x5d => 'KP_5',
  0x5e => 'KP_6',
  0x5f => 'KP_7',
  0x60 => 'KP_8',
  0x61 => 'KP_9',
  0x62 => 'KP_0',
  0x63 => 'KP_Decimal',
  _ => null,
};

// ---------------------------------------------------------------------------
// Captura por chord (v2)
// ---------------------------------------------------------------------------

/// Tecla observada durante a gravação do atalho.
class PushToTalkChordKey {
  const PushToTalkChordKey({
    required this.usage,
    required this.label,
    this.isModifier = false,
    this.isEscape = false,
    this.isClearKey = false,
  });

  /// Uso HID com página (`physicalKey.usbHidUsage`).
  final int usage;

  /// `logicalKey.keyLabel` no momento do pressionamento (pode ser vazio).
  final String label;
  final bool isModifier;
  final bool isEscape;
  final bool isClearKey;
}

/// Resultado de alimentar o [PushToTalkChordRecorder].
sealed class PushToTalkCaptureOutcome {
  const PushToTalkCaptureOutcome();
}

/// Chord em andamento — aguardando o restante das teclas ou a liberação.
class PushToTalkCapturePending extends PushToTalkCaptureOutcome {
  const PushToTalkCapturePending();
}

/// Chord liberado e válido — pronto para salvar e registrar.
class PushToTalkCaptureReady extends PushToTalkCaptureOutcome {
  const PushToTalkCaptureReady(this.binding);

  final PushToTalkBinding binding;
}

/// Esc pressionado — gravação cancelada.
class PushToTalkCaptureCancelled extends PushToTalkCaptureOutcome {
  const PushToTalkCaptureCancelled();
}

/// Backspace/Delete isolado — limpar o atalho atual.
class PushToTalkCaptureClearRequested extends PushToTalkCaptureOutcome {
  const PushToTalkCaptureClearRequested();
}

/// Combinação impossível (ex.: Ctrl+Alt+Del, Shift sozinho) — mostra
/// [message] e MANTÉM a gravação aberta para nova tentativa.
class PushToTalkCaptureRejected extends PushToTalkCaptureOutcome {
  const PushToTalkCaptureRejected(this.message);

  final String message;
}

/// Evento irrelevante (repetição, Meta, liberação órfã) — ignorar.
class PushToTalkCaptureIgnored extends PushToTalkCaptureOutcome {
  const PushToTalkCaptureIgnored();
}

/// Acumula o conjunto de teclas pressionadas durante a gravação e só confirma
/// o binding quando o chord é LIBERADO.
///
/// - Qualquer ordem entre modificadores e gatilho vale (modificadores são
///   latchados por OU durante o chord).
/// - `Ctrl`, `Alt` e `Ctrl+Alt` isolados formam atalho só-modificadores.
/// - `Esc` cancela; `Backspace`/`Delete` isolados pedem limpeza (com
///   modificadores ou outras teclas, viram gatilho normal).
/// - `Ctrl+Alt+Del` é rejeitado com mensagem específica (sequência de atenção
///   segura do SO — nenhum hook a intercepta).
///
/// Classe pura (sem Flutter além dos tipos de entrada) para teste unitário; o
/// listener traduz `KeyEvent` → [PushToTalkChordKey] + snapshot de
/// modificadores.
class PushToTalkChordRecorder {
  /// Usos HID (sem página) das teclas físicas atualmente pressionadas.
  final Set<int> pressedUsages = {};

  /// Gatilhos não-modificadores distintos pressionados neste chord.
  final Set<int> _triggers = {};

  int? _triggerUsage;
  String _triggerLabel = '';

  bool _controlLatched = false;
  bool _altLatched = false;
  bool _shiftLatched = false;
  bool _metaSeen = false;
  bool _hadKey = false;

  void reset() {
    pressedUsages.clear();
    _triggers.clear();
    _triggerUsage = null;
    _triggerLabel = '';
    _controlLatched = false;
    _altLatched = false;
    _shiftLatched = false;
    _metaSeen = false;
    _hadKey = false;
  }

  void _latch({
    required bool control,
    required bool alt,
    required bool shift,
    required bool meta,
  }) {
    _controlLatched = _controlLatched || control;
    _altLatched = _altLatched || alt;
    _shiftLatched = _shiftLatched || shift;
    _metaSeen = _metaSeen || meta;
  }

  /// Uso sem página para comparação com a tabela HID.
  static int pageLess(int usage) =>
      (usage & 0xffff0000) == 0 ? usage : usage & 0xffff;

  PushToTalkCaptureOutcome keyDown(
    PushToTalkChordKey key, {
    required bool control,
    required bool alt,
    required bool shift,
    required bool meta,
  }) {
    if (meta) {
      _metaSeen = true;
      return const PushToTalkCaptureIgnored();
    }
    if (key.isEscape) {
      reset();
      return const PushToTalkCaptureCancelled();
    }
    if (key.isClearKey && pressedUsages.isEmpty && !control && !alt && !shift) {
      reset();
      return const PushToTalkCaptureClearRequested();
    }
    _latch(control: control, alt: alt, shift: shift, meta: false);
    final pageLessUsage = pageLess(key.usage);
    pressedUsages.add(pageLessUsage);
    _hadKey = true;
    if (!key.isModifier) {
      _triggers.add(pageLessUsage);
      // Primeiro gatilho nomeia o binding; múltiplos distintos rejeitam na
      // liberação.
      if (_triggerUsage == null) {
        _triggerUsage = key.usage;
        final fallback = pttFallbackKeyLabel(pageLessUsage);
        final trimmed = key.label.trim();
        _triggerLabel = trimmed.isNotEmpty
            ? trimmed.toUpperCase()
            : (fallback ?? 'TECLA $pageLessUsage');
      }
    }
    return const PushToTalkCapturePending();
  }

  PushToTalkCaptureOutcome keyUp(
    PushToTalkChordKey key, {
    required bool control,
    required bool alt,
    required bool shift,
    required bool meta,
  }) {
    _latch(control: control, alt: alt, shift: shift, meta: meta);
    pressedUsages.remove(pageLess(key.usage));
    if (pressedUsages.isNotEmpty || !_hadKey) {
      return const PushToTalkCaptureIgnored();
    }
    // Chord liberado: confirma agora.
    final outcome = _finish();
    reset();
    return outcome;
  }

  PushToTalkCaptureOutcome _finish() {
    if (_metaSeen) return const PushToTalkCaptureIgnored();
    final trigger = _triggerUsage;
    if (trigger == null) {
      // Só modificadores: permite Ctrl, Alt e Ctrl+Alt isolados.
      if (_shiftLatched || !(_controlLatched || _altLatched)) {
        return const PushToTalkCaptureRejected(
          'Shift sozinho não serve como atalho. Segure Ctrl e/ou Alt com uma tecla — ou use Ctrl, Alt ou Ctrl+Alt isolados.',
        );
      }
      final names = <String>[
        if (_controlLatched) 'Ctrl',
        if (_altLatched) 'Alt',
      ];
      return PushToTalkCaptureReady(
        PushToTalkBinding.keyboard(
          label: names.join(' + '),
          control: _controlLatched,
          alt: _altLatched,
        ),
      );
    }
    if (_triggers.length > 1) {
      return const PushToTalkCaptureRejected(
        'Pressione apenas uma tecla de gatilho além dos modificadores.',
      );
    }
    if (_controlLatched && _altLatched && pageLess(trigger) == _hidDelete) {
      return const PushToTalkCaptureRejected(
        'Ctrl+Alt+Del é reservado pelo sistema e não pode ser usado. Escolha outro atalho.',
      );
    }
    return PushToTalkCaptureReady(
      PushToTalkBinding.keyboard(
        physicalKeyUsage: trigger,
        label: _triggerLabel,
        control: _controlLatched,
        alt: _altLatched,
        shift: _shiftLatched,
      ),
    );
  }

  /// HID sem página da tecla Delete (0x4C).
  static const int _hidDelete = 0x4c;
}
