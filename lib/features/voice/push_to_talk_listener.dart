import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'push_to_talk_input.dart';
import 'voice_controls_provider.dart';

/// Captura o fallback em foco e os eventos globais vindos dos runners.
class PushToTalkListener extends ConsumerStatefulWidget {
  const PushToTalkListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PushToTalkListener> createState() =>
      _PushToTalkListenerState();
}

class _PushToTalkListenerState extends ConsumerState<PushToTalkListener>
    with WidgetsBindingObserver {
  StreamSubscription<PushToTalkInputEvent>? _nativeEvents;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
    _nativeEvents = ref.read(pushToTalkInputServiceProvider).events.listen(
      (event) {
        final controls = ref.read(voiceControlsProvider.notifier);
        switch (event) {
          case PushToTalkInputEvent.pressed:
            unawaited(controls.setPushToTalkPressed(true));
          case PushToTalkInputEvent.released:
          case PushToTalkInputEvent.failed:
            unawaited(controls.setPushToTalkPressed(false));
        }
      },
    );
  }

  @override
  void dispose() {
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
      unawaited(
        ref.read(voiceControlsProvider.notifier).setPushToTalkPressed(false),
      );
    }
  }

  bool _onKeyEvent(KeyEvent event) {
    final controls = ref.read(voiceControlsProvider.notifier);
    final state = ref.read(voiceControlsProvider);
    if (state.isRecordingPushToTalk) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        controls.cancelPushToTalkRecording();
        return true;
      }
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.backspace ||
              event.logicalKey == LogicalKeyboardKey.delete)) {
        unawaited(controls.clearPushToTalkBinding());
        return true;
      }
      if (event is KeyDownEvent) {
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
    if (event is KeyDownEvent) {
      unawaited(controls.setPushToTalkPressed(true));
    } else if (event is KeyUpEvent) {
      unawaited(controls.setPushToTalkPressed(false));
    }
    // No fallback em foco, não inserir a tecla do PTT no campo de chat.
    return true;
  }

  void _onPointerDown(PointerDownEvent event) {
    final controls = ref.read(voiceControlsProvider.notifier);
    final state = ref.read(voiceControlsProvider);
    if (state.isRecordingPushToTalk) {
      unawaited(controls.recordPushToTalkMouse(event.buttons));
      return;
    }
    final binding = state.pushToTalkBinding;
    if (state.isPushToTalkEnabled &&
        binding != null &&
        binding.matchesPointer(event)) {
      unawaited(controls.setPushToTalkPressed(true));
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    final state = ref.read(voiceControlsProvider);
    final binding = state.pushToTalkBinding;
    if (state.isPushToTalkEnabled &&
        binding != null &&
        binding.mouseButton != null) {
      unawaited(
        ref.read(voiceControlsProvider.notifier).setPushToTalkPressed(false),
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
