import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/native_media_backend.dart';
import 'push_to_talk_backend.dart';
import 'push_to_talk.dart';

/// Ponte para os listeners globais dos runners desktop.
///
/// No web o listener raiz do Flutter é a implementação; em Linux/Windows o
/// runner emite somente press/release do binding já filtrado, sem expor o
/// fluxo completo de teclas ao Dart.
class PushToTalkInputService {
  PushToTalkInputService({PushToTalkBackend? backend})
    : _backend =
          backend ??
          const DefaultPushToTalkBackendFactory().create(
            currentRuntimePlatform,
          );

  final PushToTalkBackend _backend;

  Stream<PushToTalkInputEvent> get events => _backend.events;

  /// `ok` significa que o runner registrou um listener global. Web não
  /// possui registro nativo, mas o fallback em foco continua disponível.
  Future<PushToTalkConfigResult> configure(PushToTalkBinding? binding) =>
      _backend.configure(binding);
}

final pushToTalkInputServiceProvider = Provider<PushToTalkInputService>(
  (ref) => PushToTalkInputService(backend: ref.read(pushToTalkBackendProvider)),
);
