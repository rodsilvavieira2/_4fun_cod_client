import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/native_media_backend.dart';
import 'push_to_talk.dart';

abstract interface class PushToTalkBackend {
  Stream<PushToTalkInputEvent> get events;

  Future<PushToTalkConfigResult> configure(PushToTalkBinding? binding);
}

abstract interface class PushToTalkBackendFactory {
  PushToTalkBackend create(AppRuntimePlatform platform);
}

class DefaultPushToTalkBackendFactory implements PushToTalkBackendFactory {
  const DefaultPushToTalkBackendFactory();

  @override
  PushToTalkBackend create(AppRuntimePlatform platform) => switch (platform) {
    AppRuntimePlatform.linux => const LinuxPushToTalkBackend(),
    AppRuntimePlatform.windows => const WindowsPushToTalkBackend(),
    AppRuntimePlatform.web => const WebPushToTalkBackend(),
  };
}

abstract class _MethodChannelPushToTalkBackend implements PushToTalkBackend {
  const _MethodChannelPushToTalkBackend();

  static const _methods = MethodChannel('fourfun_cod/push_to_talk');
  static const _events = EventChannel('fourfun_cod/push_to_talk_events');

  @override
  Stream<PushToTalkInputEvent> get events =>
      _events.receiveBroadcastStream().map((event) {
        final value = Map<Object?, Object?>.from(event as Map);
        return switch (value['state']) {
          'pressed' => PushToTalkInputEvent.pressed,
          'released' => PushToTalkInputEvent.released,
          _ => PushToTalkInputEvent.failed,
        };
      });

  @override
  Future<PushToTalkConfigResult> configure(PushToTalkBinding? binding) async {
    try {
      final ok =
          await _methods.invokeMethod<bool>('configure', binding?.toJson()) ??
          false;
      return ok
          ? const PushToTalkConfigResult.ok()
          : const PushToTalkConfigResult.failed(
              PushToTalkConfigError.registrationFailed,
            );
    } on MissingPluginException {
      return const PushToTalkConfigResult.failed(
        PushToTalkConfigError.registrationFailed,
        'Backend de atalho global indisponível nesta plataforma.',
      );
    } on PlatformException catch (e) {
      return PushToTalkConfigResult.failed(switch (e.code) {
        'unsupported_key' => PushToTalkConfigError.unsupportedKey,
        'conflict' => PushToTalkConfigError.conflicting,
        _ => PushToTalkConfigError.registrationFailed,
      }, e.message);
    }
  }
}

class LinuxPushToTalkBackend extends _MethodChannelPushToTalkBackend {
  const LinuxPushToTalkBackend();

  /// Limitações explícitas do backend Linux (portal GlobalShortcuts + evdev):
  /// sem mouse com modificadores (o leitor evdev não enxerga modificadores)
  /// e sem atalhos só-modificadores (o portal exige uma tecla principal).
  /// Recusar aqui impede salvar um atalho que nunca dispararia.
  @override
  Future<PushToTalkConfigResult> configure(PushToTalkBinding? binding) {
    final mouseWithMods =
        binding != null &&
        binding.kind == PushToTalkBindingKind.mouse &&
        binding.hasModifiers;
    if (binding != null && (mouseWithMods || binding.isModifierOnly)) {
      final which = mouseWithMods
          ? 'Botões do mouse com modificadores não são suportados no Linux'
          : 'Atalhos só de modificadores (Ctrl/Alt isolados) não são suportados no Linux';
      return Future.value(
        PushToTalkConfigResult.failed(
          PushToTalkConfigError.unsupportedKey,
          '$which. Escolha uma tecla com modificadores.',
        ),
      );
    }
    return super.configure(binding);
  }
}

class WindowsPushToTalkBackend extends _MethodChannelPushToTalkBackend {
  const WindowsPushToTalkBackend();
}

class WebPushToTalkBackend implements PushToTalkBackend {
  const WebPushToTalkBackend();

  @override
  Stream<PushToTalkInputEvent> get events => const Stream.empty();

  /// Web não tem registro nativo: o fallback em foco entende todos os
  /// bindings v2 (teclado com qualquer ordem, só-modificadores e mouse com
  /// modificadores), então todo binding não-nulo é "registrável".
  @override
  Future<PushToTalkConfigResult> configure(PushToTalkBinding? binding) async =>
      binding != null
      ? const PushToTalkConfigResult.ok()
      : const PushToTalkConfigResult.failed(
          PushToTalkConfigError.registrationFailed,
          'Push to Talk precisa de um atalho configurado.',
        );
}

final pushToTalkBackendProvider = Provider<PushToTalkBackend>((ref) {
  return const DefaultPushToTalkBackendFactory().create(currentRuntimePlatform);
});
