import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Master on/off dos sons de voz/stream estilo Discord.
///
/// Separado de `NotificationPreferences.sounds` (notificação de mensagem):
/// semântica diferente, default diferente (voz liga por padrão).
const voiceSoundsEnabledKey = 'voice.sounds_enabled';

class VoiceSoundPreferencesController extends Notifier<bool> {
  SharedPreferences? _preferences;
  Future<void>? _initialization;

  @override
  bool build() {
    _initialization = _load();
    return true;
  }

  Future<void> ensureInitialized() => _initialization ??= _load();

  Future<void> _load() async {
    try {
      final preferences = _preferences ??= await SharedPreferences.getInstance();
      state = preferences.getBool(voiceSoundsEnabledKey) ?? true;
    } catch (_) {
      // Falha de leitura: mantém o default ligado.
    }
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    try {
      final preferences = _preferences ??= await SharedPreferences.getInstance();
      await preferences.setBool(voiceSoundsEnabledKey, value);
    } catch (_) {
      // Persistência é best-effort; o estado em memória já vale.
    }
  }
}

final voiceSoundPreferencesProvider =
    NotifierProvider<VoiceSoundPreferencesController, bool>(
      VoiceSoundPreferencesController.new,
    );
