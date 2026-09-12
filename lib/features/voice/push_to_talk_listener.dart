import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import 'push_to_talk.dart';
import 'push_to_talk_input.dart';
import 'voice_controls_provider.dart';

/// Captura o fallback em foco e os eventos globais vindos dos runners.
class PushToTalkListener extends ConsumerStatefulWidget {
  const PushToTalkListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushToTalkListener> createState() => _PushToTalkListenerState();
}

class _PushToTalkListenerState extends ConsumerState<PushToTalkListener>
    with WidgetsBindingObserver {
  StreamSubscription<PushToTalkInputEvent>? _nativeEvents;

  void _logPtt(String message) {
    try {
      ref.read(appLoggerProvider).d('listener: $message', tag: 'ptt');
    } catch (_) {
      debugPrint('[ptt] listener: $message');
    }
  }

  static String _keyEventName(KeyEvent event) {
    if (event is KeyDownEvent) return 'down';
    if (event is KeyUpEvent) return 'up';
    if (event is KeyRepeatEvent) return 'repeat';
    return event.runtimeType.toString();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _logPtt('ativo para eventos nativos e fallback focado');
    _nativeEvents = ref.read(pushToTalkInputServiceProvider).events.listen((
      event,
    ) {
      final controls = ref.read(voiceControlsProvider.notifier);
      final state = ref.read(voiceControlsProvider);
      _logPtt(
        'evento nativo=${event.name} recording=${state.isRecordingPushToTalk} '
        'enabled=${state.isPushToTalkEnabled} '
        'registered=${state.isPushToTalkRegistered}',
      );
      if (state.isRecordingPushToTalk) {
        _logPtt('evento nativo ignorado durante gravação de atalho');
        return;
      }
      switch (event) {
        case PushToTalkInputEvent.pressed:
          unawaited(controls.setPushToTalkPressed(true, source: 'native'));
        case PushToTalkInputEvent.released:
          unawaited(controls.setPushToTalkPressed(false, source: 'native'));
        case PushToTalkInputEvent.failed:
          unawaited(controls.handlePushToTalkRegistrationFailure());
      }
    });
  }

  @override
  void dispose() {
    _logPtt('dispose: removendo listeners');
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _nativeEvents?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // O browser pode perder o KeyUp quando a aba muda. Desktop recebe a
    // liberação pelo listener nativo e não deve ser fechado ao perder foco.
    if (kIsWeb && state != AppLifecycleState.resumed) {
      _logPtt('lifecycle web=$state: liberando PTT por segurança');
      unawaited(
        ref
            .read(voiceControlsProvider.notifier)
            .setPushToTalkPressed(false, source: 'lifecycle'),
      );
    }
  }

  bool _onKeyEvent(KeyEvent event) {
    final controls = ref.read(voiceControlsProvider.notifier);
    final state = ref.read(voiceControlsProvider);
    if (state.isRecordingPushToTalk) {
      // Gravação por chord (v2): o recorder acumula o conjunto pressionado
      // em qualquer ordem e confirma ao soltar. Esc cancela e
      // Backspace/Delete isolado limpa — tudo dentro do recorder.
      if (event is KeyDownEvent || event is KeyUpEvent) {
        _logPtt(
          'tecla para gravação event=${_keyEventName(event)} '
          'label=${event.logicalKey.keyLabel} '
          'usage=${event.physicalKey.usbHidUsage}',
        );
        unawaited(controls.recordPushToTalkKey(event));
      }
      return true;
    }
    final binding = state.pushToTalkBinding;
    if (!state.isPushToTalkEnabled ||
        binding == null ||
        !binding.matchesKey(event)) {
      return false;
    }
    // Mesmo no desktop, manter o fallback focado ativo. Alguns ambientes
    // registram o atalho global com sucesso, mas o hook/portal não entrega os
    // eventos; quando a janela está focada, isso ainda deve abrir o microfone.
    _logPtt(
      'fallback teclado matched event=${_keyEventName(event)} '
      'binding=${binding.displayLabel} registered=${state.isPushToTalkRegistered}',
    );
    if (event is KeyDownEvent) {
      unawaited(controls.setPushToTalkPressed(true, source: 'focused-key'));
    } else if (event is KeyUpEvent) {
      unawaited(controls.setPushToTalkPressed(false, source: 'focused-key'));
    }
    // No fallback em foco, não inserir a tecla do PTT no campo de chat.
    return true;
  }

  void _onPointerDown(PointerDownEvent event) {
    final controls = ref.read(voiceControlsProvider.notifier);
    final state = ref.read(voiceControlsProvider);
    if (state.isRecordingPushToTalk) {
      final keyboard = HardwareKeyboard.instance;
      _logPtt(
        'mouse para gravação buttons=${event.buttons} '
        'ctrl=${keyboard.isControlPressed} alt=${keyboard.isAltPressed} '
        'shift=${keyboard.isShiftPressed}',
      );
      unawaited(
        controls.recordPushToTalkMouse(
          event.buttons,
          control: keyboard.isControlPressed,
          alt: keyboard.isAltPressed,
          shift: keyboard.isShiftPressed,
        ),
      );
      return;
    }
    final binding = state.pushToTalkBinding;
    if (state.isPushToTalkEnabled &&
        binding != null &&
        binding.matchesPointer(event)) {
      _logPtt(
        'fallback mouse matched buttons=${event.buttons} '
        'binding=${binding.displayLabel}',
      );
      unawaited(controls.setPushToTalkPressed(true, source: 'focused-pointer'));
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final state = ref.read(voiceControlsProvider);
    final binding = state.pushToTalkBinding;
    if (state.isPushToTalkEnabled &&
        binding != null &&
        binding.mouseButton != null) {
      _logPtt(
        'fallback mouse release buttons=${event.buttons} '
        'binding=${binding.displayLabel}',
      );
      unawaited(
        ref
            .read(voiceControlsProvider.notifier)
            .setPushToTalkPressed(false, source: 'focused-pointer'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      child: widget.child,
    );
  }
}
