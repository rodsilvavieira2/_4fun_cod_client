import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/native_media_backend.dart';
import 'push_to_talk.dart';

abstract interface class PushToTalkBackend {
  Stream<PushToTalkInputEvent> get events;

  Future<bool> configure(PushToTalkBinding? binding);
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
  Future<bool> configure(PushToTalkBinding? binding) async {
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

class LinuxPushToTalkBackend extends _MethodChannelPushToTalkBackend {
  const LinuxPushToTalkBackend();
}

class WindowsPushToTalkBackend extends _MethodChannelPushToTalkBackend {
  const WindowsPushToTalkBackend();
}

class WebPushToTalkBackend implements PushToTalkBackend {
  const WebPushToTalkBackend();

  @override
  Stream<PushToTalkInputEvent> get events => const Stream.empty();

  @override
  Future<bool> configure(PushToTalkBinding? binding) async => binding != null;
}

final pushToTalkBackendProvider = Provider<PushToTalkBackend>((ref) {
  final platform = kIsWeb ? AppRuntimePlatform.web : currentRuntimePlatform;
  return const DefaultPushToTalkBackendFactory().create(platform);
});
