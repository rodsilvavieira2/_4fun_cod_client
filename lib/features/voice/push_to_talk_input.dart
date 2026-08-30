import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'push_to_talk.dart';

/// Ponte para os listeners globais dos runners desktop.
///
/// No web o listener raiz do Flutter é a implementação; em Linux/Windows o
/// runner emite somente press/release do binding já filtrado, sem expor o
/// fluxo completo de teclas ao Dart.
class PushToTalkInputService {
  static const _methods = MethodChannel('fourfun_cod/push_to_talk');
  static const _events = EventChannel('fourfun_cod/push_to_talk_events');

  Stream<PushToTalkInputEvent>? _eventStream;

  Stream<PushToTalkInputEvent> get events =>
      _eventStream ??= _events.receiveBroadcastStream().map((event) {
        final value = Map<Object?, Object?>.from(event as Map);
        return switch (value['state']) {
          'pressed' => PushToTalkInputEvent.pressed,
          'released' => PushToTalkInputEvent.released,
          _ => PushToTalkInputEvent.failed,
        };
      });

  /// `true` significa que o runner registrou um listener global. Web não
  /// possui registro nativo, mas o fallback em foco continua disponível.
  Future<bool> configure(PushToTalkBinding? binding) async {
    if (kIsWeb) return binding != null;
    try {
      return await _methods.invokeMethod<bool>(
            'configure',
            binding?.toJson(),
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

enum PushToTalkInputEvent { pressed, released, failed }

final pushToTalkInputServiceProvider = Provider<PushToTalkInputService>(
  (ref) => PushToTalkInputService(),
);
