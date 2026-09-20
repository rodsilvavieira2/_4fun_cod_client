import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'voice_sound_service.dart';

/// Composition root dos sons de voz. Testes sobrescrevem com fake via
/// `voiceSoundServiceProvider.overrideWithValue(...)` — o comportamento
/// default nunca lança (falha de playback é silenciosa no service).
final voiceSoundServiceProvider = Provider<VoiceSoundService>((ref) {
  final service = VoiceSoundService(
    player: AudioplayersVoiceSoundPlayer(),
  );
  ref.onDispose(() {});
  return service;
});
