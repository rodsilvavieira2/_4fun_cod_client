import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fourfun_cod_client/core/native/native_media_backend.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk.dart';
import 'package:fourfun_cod_client/features/voice/push_to_talk_backend.dart';

const int _hidK = 0x0007000e;
const int _hidJ = 0x0007000d;
const int _hidCtrl = 0x000700e0;
const int _hidAlt = 0x000700e2;
const int _hidDelete = 0x0007004c;
const int _hidBackspace = 0x0007002a;
const int _hidEsc = 0x00070029;

PushToTalkChordKey _key(
  int usage, {
  String label = '',
  bool isModifier = false,
  bool isEscape = false,
  bool isClearKey = false,
}) => PushToTalkChordKey(
  usage: usage,
  label: label,
  isModifier: isModifier,
  isEscape: isEscape,
  isClearKey: isClearKey,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushToTalkBinding v2', () {
    test('migra JSON v1 de teclado preservando o atalho', () {
      final binding = PushToTalkBinding.fromJson({
        'kind': 'keyboard',
        'physicalKeyUsage': 0x00070004,
        'label': 'A',
        'control': true,
        'alt': false,
        'shift': false,
      });

      expect(binding, isNotNull);
      expect(binding!.kind, PushToTalkBindingKind.keyboard);
      expect(binding.physicalKeyUsage, 0x00070004);
      expect(binding.control, isTrue);
      expect(binding.displayLabel, 'Ctrl + A');
      expect(binding.isModifierOnly, isFalse);
    });

    test('migra JSON v1 de mouse sem modificadores', () {
      final binding = PushToTalkBinding.fromJson({
        'kind': 'mouse',
        'mouseButton': 8,
        'label': 'Botão voltar',
      });

      expect(binding, isNotNull);
      expect(binding!.mouseButton, 8);
      expect(binding.hasModifiers, isFalse);
    });

    test('round-trip v2 com modificadores e mouse 4/5', () {
      const keyboard = PushToTalkBinding.keyboard(
        physicalKeyUsage: _hidK,
        label: 'K',
        control: true,
        alt: true,
      );
      const mouse = PushToTalkBinding.mouse(
        mouseButton: 16,
        label: 'Botão avançar',
        shift: true,
      );

      final keyboardBack = PushToTalkBinding.fromJson(keyboard.toJson())!;
      final mouseBack = PushToTalkBinding.fromJson(mouse.toJson())!;

      expect(keyboardBack, keyboard);
      expect(keyboardBack.displayLabel, 'Ctrl + Alt + K');
      expect(mouseBack, mouse);
      expect(mouseBack.displayLabel, 'Shift + Botão avançar');
      expect(keyboard.toJson()['v'], 2);
    });

    test('só-modificadores: Ctrl, Alt e Ctrl+Alt com label derivado', () {
      const ctrl = PushToTalkBinding.keyboard(label: 'Ctrl', control: true);
      const alt = PushToTalkBinding.keyboard(label: 'Alt', alt: true);
      const ctrlAlt = PushToTalkBinding.keyboard(
        label: 'Ctrl + Alt',
        control: true,
        alt: true,
      );

      expect(ctrl.isModifierOnly, isTrue);
      expect(ctrl.displayLabel, 'Ctrl');
      expect(alt.displayLabel, 'Alt');
      expect(ctrlAlt.displayLabel, 'Ctrl + Alt');
      expect(PushToTalkBinding.fromJson(ctrl.toJson()), ctrl);

      // Shift sozinho não é atalho válido.
      expect(
        PushToTalkBinding.fromJson({
          'v': 2,
          'kind': 'keyboard',
          'label': 'Shift',
          'control': false,
          'alt': false,
          'shift': true,
        }),
        isNull,
      );
    });

    test('rejeita JSON inválido ou desconhecido', () {
      expect(PushToTalkBinding.fromJson(null), isNull);
      expect(PushToTalkBinding.fromJson({'kind': 'gamepad'}), isNull);
      expect(
        PushToTalkBinding.fromJson({'kind': 'keyboard', 'label': ''}),
        isNull,
      );
      expect(
        PushToTalkBinding.fromJson({
          'kind': 'mouse',
          'mouseButton': 1,
          'label': 'Primário',
        }),
        isNull,
      );
    });

    test('matchesKey exige modificadores exatos', () {
      const binding = PushToTalkBinding.keyboard(
        physicalKeyUsage: _hidK,
        label: 'K',
        control: true,
      );
      final down = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyK,
        logicalKey: LogicalKeyboardKey.keyK,
        timeStamp: Duration.zero,
      );

      // Sem Ctrl pressionado no HardwareKeyboard do teste: não casa.
      expect(binding.matchesKey(down), isFalse);

      const plain = PushToTalkBinding.keyboard(
        physicalKeyUsage: _hidK,
        label: 'K',
      );
      expect(plain.matchesKey(down), isTrue);

      final other = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyJ,
        logicalKey: LogicalKeyboardKey.keyJ,
        timeStamp: Duration.zero,
      );
      expect(plain.matchesKey(other), isFalse);
    });

    test('matchesPointer compara botão e modificadores', () {
      const binding = PushToTalkBinding.mouse(
        mouseButton: 8,
        label: 'Botão voltar',
      );
      PointerEvent down(int buttons) => PointerDownEvent(buttons: buttons);

      expect(binding.matchesPointer(down(8)), isTrue);
      expect(binding.matchesPointer(down(16)), isFalse);

      const withCtrl = PushToTalkBinding.mouse(
        mouseButton: 8,
        label: 'Botão voltar',
        control: true,
      );
      // HardwareKeyboard do teste não tem Ctrl: não casa.
      expect(withCtrl.matchesPointer(down(8)), isFalse);
    });
  });

  group('PushToTalkChordRecorder', () {
    late PushToTalkChordRecorder recorder;

    setUp(() => recorder = PushToTalkChordRecorder());

    PushToTalkCaptureOutcome releaseAll(
      PushToTalkChordKey key, {
      bool control = false,
      bool alt = false,
      bool shift = false,
    }) => recorder.keyUp(
      key,
      control: control,
      alt: alt,
      shift: shift,
      meta: false,
    );

    test('tecla simples confirma ao soltar', () {
      expect(
        recorder.keyDown(
          _key(_hidK, label: 'k'),
          control: false,
          alt: false,
          shift: false,
          meta: false,
        ),
        isA<PushToTalkCapturePending>(),
      );
      final outcome = releaseAll(_key(_hidK));

      expect(outcome, isA<PushToTalkCaptureReady>());
      final binding = (outcome as PushToTalkCaptureReady).binding;
      expect(binding.physicalKeyUsage, _hidK);
      expect(binding.label, 'K');
      expect(binding.hasModifiers, isFalse);
    });

    test('Ctrl+Alt+K confirma em qualquer ordem', () {
      // Ordem 1: modificadores antes.
      recorder.keyDown(
        _key(_hidCtrl, isModifier: true),
        control: true,
        alt: false,
        shift: false,
        meta: false,
      );
      recorder.keyDown(
        _key(_hidAlt, isModifier: true),
        control: true,
        alt: true,
        shift: false,
        meta: false,
      );
      recorder.keyDown(
        _key(_hidK, label: 'k'),
        control: true,
        alt: true,
        shift: false,
        meta: false,
      );
      var outcome = releaseAll(_key(_hidK), control: true, alt: true);
      expect(outcome, isA<PushToTalkCaptureIgnored>());
      outcome = releaseAll(_key(_hidAlt), control: true);
      expect(outcome, isA<PushToTalkCaptureIgnored>());
      outcome = releaseAll(_key(_hidCtrl));
      expect(outcome, isA<PushToTalkCaptureReady>());
      var binding = (outcome as PushToTalkCaptureReady).binding;
      expect(binding.control, isTrue);
      expect(binding.alt, isTrue);
      expect(binding.physicalKeyUsage, _hidK);

      // Ordem 2: gatilho antes dos modificadores.
      recorder.keyDown(
        _key(_hidK, label: 'k'),
        control: false,
        alt: false,
        shift: false,
        meta: false,
      );
      recorder.keyDown(
        _key(_hidCtrl, isModifier: true),
        control: true,
        alt: false,
        shift: false,
        meta: false,
      );
      outcome = releaseAll(_key(_hidCtrl));
      expect(outcome, isA<PushToTalkCaptureIgnored>());
      outcome = releaseAll(_key(_hidK));
      binding = (outcome as PushToTalkCaptureReady).binding;
      expect(binding.control, isTrue);
      expect(binding.physicalKeyUsage, _hidK);
    });

    test('modificador liberado antes da tecla-base mantém o chord', () {
      recorder.keyDown(
        _key(_hidCtrl, isModifier: true),
        control: true,
        alt: false,
        shift: false,
        meta: false,
      );
      recorder.keyDown(
        _key(_hidK, label: 'k'),
        control: true,
        alt: false,
        shift: false,
        meta: false,
      );
      // Ctrl solto antes do K: latch OU preserva a intenção.
      expect(releaseAll(_key(_hidCtrl)), isA<PushToTalkCaptureIgnored>());
      final outcome = releaseAll(_key(_hidK));
      final binding = (outcome as PushToTalkCaptureReady).binding;
      expect(binding.control, isTrue);
      expect(binding.physicalKeyUsage, _hidK);
    });

    test('Ctrl isolado vira atalho só-modificadores', () {
      recorder.keyDown(
        _key(_hidCtrl, label: '', isModifier: true),
        control: true,
        alt: false,
        shift: false,
        meta: false,
      );
      final outcome = releaseAll(_key(_hidCtrl));

      expect(outcome, isA<PushToTalkCaptureReady>());
      final binding = (outcome as PushToTalkCaptureReady).binding;
      expect(binding.isModifierOnly, isTrue);
      expect(binding.control, isTrue);
      expect(binding.displayLabel, 'Ctrl');
    });

    test('Ctrl+Alt isolados valem; Shift sozinho rejeita', () {
      recorder.keyDown(
        _key(_hidCtrl, isModifier: true),
        control: true,
        alt: false,
        shift: false,
        meta: false,
      );
      recorder.keyDown(
        _key(_hidAlt, isModifier: true),
        control: true,
        alt: true,
        shift: false,
        meta: false,
      );
      releaseAll(_key(_hidAlt), control: true);
      final both = releaseAll(_key(_hidCtrl)) as PushToTalkCaptureReady;
      expect(both.binding.displayLabel, 'Ctrl + Alt');

      const shiftUsage = 0x000700e1;
      recorder.keyDown(
        _key(shiftUsage, isModifier: true),
        control: false,
        alt: false,
        shift: true,
        meta: false,
      );
      final shiftAlone = releaseAll(_key(shiftUsage));
      expect(shiftAlone, isA<PushToTalkCaptureRejected>());
      expect(
        (shiftAlone as PushToTalkCaptureRejected).message,
        contains('Shift'),
      );
    });

    test('Ctrl+Alt+Del rejeita com mensagem específica', () {
      recorder.keyDown(
        _key(_hidCtrl, isModifier: true),
        control: true,
        alt: false,
        shift: false,
        meta: false,
      );
      recorder.keyDown(
        _key(_hidAlt, isModifier: true),
        control: true,
        alt: true,
        shift: false,
        meta: false,
      );
      recorder.keyDown(
        _key(_hidDelete, label: 'Delete', isClearKey: true),
        control: true,
        alt: true,
        shift: false,
        meta: false,
      );
      releaseAll(_key(_hidDelete), control: true, alt: true);
      releaseAll(_key(_hidAlt), control: true);
      final outcome = releaseAll(_key(_hidCtrl));

      expect(outcome, isA<PushToTalkCaptureRejected>());
      expect(
        (outcome as PushToTalkCaptureRejected).message,
        contains('Ctrl+Alt+Del'),
      );
    });

    test('Esc cancela; Backspace isolado limpa', () {
      final cancel = recorder.keyDown(
        _key(_hidEsc, isEscape: true),
        control: false,
        alt: false,
        shift: false,
        meta: false,
      );
      expect(cancel, isA<PushToTalkCaptureCancelled>());

      final clear = recorder.keyDown(
        _key(_hidBackspace, label: 'Backspace', isClearKey: true),
        control: false,
        alt: false,
        shift: false,
        meta: false,
      );
      expect(clear, isA<PushToTalkCaptureClearRequested>());
    });

    test('Backspace com Ctrl vira gatilho normal', () {
      recorder.keyDown(
        _key(_hidCtrl, isModifier: true),
        control: true,
        alt: false,
        shift: false,
        meta: false,
      );
      final down = recorder.keyDown(
        _key(_hidBackspace, label: 'Backspace', isClearKey: true),
        control: true,
        alt: false,
        shift: false,
        meta: false,
      );
      expect(down, isA<PushToTalkCapturePending>());
      releaseAll(_key(_hidBackspace), control: true);
      final outcome = releaseAll(_key(_hidCtrl));
      final binding = (outcome as PushToTalkCaptureReady).binding;
      expect(binding.physicalKeyUsage, _hidBackspace);
      expect(binding.control, isTrue);
    });

    test('dois gatilhos distintos rejeitam', () {
      recorder.keyDown(
        _key(_hidK, label: 'k'),
        control: false,
        alt: false,
        shift: false,
        meta: false,
      );
      recorder.keyDown(
        _key(_hidJ, label: 'j'),
        control: false,
        alt: false,
        shift: false,
        meta: false,
      );
      releaseAll(_key(_hidK));
      final outcome = releaseAll(_key(_hidJ));
      expect(outcome, isA<PushToTalkCaptureRejected>());
    });

    test('liberação órfã e Meta são ignorados', () {
      expect(releaseAll(_key(_hidK)), isA<PushToTalkCaptureIgnored>());
      expect(
        recorder.keyDown(
          _key(_hidK, label: 'k'),
          control: false,
          alt: false,
          shift: false,
          meta: true,
        ),
        isA<PushToTalkCaptureIgnored>(),
      );
    });
  });

  group('backends PTT v2', () {
    test(
      'Linux recusa mouse com modificadores e aceita modifiers-only',
      () async {
        const backend = LinuxPushToTalkBackend();

        final mouseMods = await backend.configure(
          const PushToTalkBinding.mouse(
            mouseButton: 8,
            label: 'Botão voltar',
            control: true,
          ),
        );
        expect(mouseMods.isOk, isFalse);
        expect(mouseMods.error, PushToTalkConfigError.unsupportedKey);
        expect(mouseMods.message, contains('Linux'));

        final modsOnly = await backend.configure(
          const PushToTalkBinding.keyboard(label: 'Ctrl', control: true),
        );
        expect(modsOnly.isOk, isFalse);
        expect(modsOnly.error, PushToTalkConfigError.registrationFailed);

        // Teclado comum e mouse puro passam ao runner nativo (sem plugin no
        // teste, a falha é de registro — não de "não suportado").
        final keyboard = await backend.configure(
          const PushToTalkBinding.keyboard(
            physicalKeyUsage: _hidK,
            label: 'K',
            control: true,
            alt: true,
          ),
        );
        expect(keyboard.error, PushToTalkConfigError.registrationFailed);

        final mouse = await backend.configure(
          const PushToTalkBinding.mouse(mouseButton: 4, label: 'Botão do meio'),
        );
        expect(mouse.error, PushToTalkConfigError.registrationFailed);
      },
    );

    test('resultado tipado expõe erro e mensagem', () {
      const ok = PushToTalkConfigResult.ok();
      expect(ok.isOk, isTrue);
      expect(ok.error, isNull);
      expect(ok.message, isNull);

      const failed = PushToTalkConfigResult.failed(
        PushToTalkConfigError.conflicting,
        'em uso',
      );
      expect(failed.isOk, isFalse);
      expect(failed.error, PushToTalkConfigError.conflicting);
      expect(failed.message, 'em uso');
    });
  });

  test('DefaultPushToTalkBackendFactory cobre linux/windows', () async {
    const factory = DefaultPushToTalkBackendFactory();
    expect(
      factory.create(AppRuntimePlatform.linux),
      isA<LinuxPushToTalkBackend>(),
    );
    expect(
      factory.create(AppRuntimePlatform.windows),
      isA<WindowsPushToTalkBackend>(),
    );
  });
}
