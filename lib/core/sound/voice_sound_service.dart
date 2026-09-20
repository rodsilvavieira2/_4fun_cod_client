// ignore_for_file: prefer_initializing_formals
// Motivo: param público `player` vs campo privado `_player` — initializing
// formal exigiria renomear a API pública do serviço.
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

/// Sons de UI estilo Discord para voz/stream.
///
/// Arquivos originais sintetizados por `tools/synth_voice_sounds.py`
/// (nunca copiar os .ogg do Discord — licença). `AudioCache` usa o prefixo
/// default `assets/`, então o path aqui é relativo a `assets/`.
enum VoiceSound {
  join('sounds/voice_join.wav'),
  leave('sounds/voice_leave.wav'),
  streamStart('sounds/stream_start.wav'),
  streamStop('sounds/stream_stop.wav');

  const VoiceSound(this.assetPath);

  /// Path relativo ao prefixo `assets/` do `AudioCache`.
  final String assetPath;
}

/// Adaptação mínima do player para testes (sem MethodChannel).
abstract class VoiceSoundPlayer {
  Future<void> play(String assetPath, {required double volume});
}

/// Player real via `audioplayers` com pool de 2 instâncias para permitir
/// sobreposição (ex.: join remoto + stream start no mesmo frame).
///
/// Uso de output: dispositivo default do SO. Não roteia para o output
/// selecionado em `audioDevicesProvider` (limitação documentada da v1).
class AudioplayersVoiceSoundPlayer implements VoiceSoundPlayer {
  AudioplayersVoiceSoundPlayer({AudioPlayer Function()? playerFactory})
    : _playerFactory = playerFactory ?? AudioPlayer.new;

  final AudioPlayer Function() _playerFactory;
  final List<AudioPlayer> _pool = [];
  int _next = 0;

  @override
  Future<void> play(String assetPath, {required double volume}) async {
    // Sem binding do Flutter (testes unitários puros) não há saída de áudio:
    // construir `AudioPlayer` aqui agenda trabalho async no plugin que escapa
    // de try/catch como unhandled error e quebra a suite. Pula antes.
    if (!_bindingReady) return;
    try {
      final player = _pooled();
      await player.setVolume(volume);
      await player.play(AssetSource(assetPath));
    } catch (_) {
      // Som de UI nunca pode derrubar voz/notificação: falha silenciosa.
    }
  }

  /// True quando há binding (app real / widget tests). Getter síncrono e
  /// seguro: sem binding o acesso a `WidgetsBinding.instance` lança StateError.
  bool get _bindingReady {
    try {
      WidgetsBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  AudioPlayer _pooled() {
    while (_pool.length < 2) {
      _pool.add(_playerFactory());
    }
    final player = _pool[_next];
    _next = (_next + 1) % _pool.length;
    return player;
  }
}

/// Serviço de sons de voz: decide SE toca e com qual volume.
///
/// - `enabled`: master `voice.sounds_enabled` (default true).
/// - `deafened`: ensurdecido estilo Discord = mudo total de UI sounds.
/// - `remote`: eventos de outros participantes tocam 3dB mais baixo.
/// - Debounce de 500ms por som remoto (rajada de snapshot/reconnect vira 1 som).
class VoiceSoundService {
  VoiceSoundService({
    required VoiceSoundPlayer player,
    DateTime Function()? clock,
  }) : _player = player,
       _clock = clock ?? DateTime.now;

  final VoiceSoundPlayer _player;
  final DateTime Function() _clock;

  static const remoteDebounce = Duration(milliseconds: 500);

  /// Cooldown de sinais recebidos (ADR-0001): rajada entra/sai vira 1 som e
  /// amortece spam sem precisar de moderação por papel nesta v1.
  static const signalCooldown = Duration(seconds: 2);

  /// Janela em que um sinal suprime o fallback por diff do mesmo tipo
  /// (evita som duplo entre clients novos e antigos).
  static const signalSuppressWindow = Duration(seconds: 2);
  static const double _localVolume = 1.0;
  static const double _remoteVolume = 0.7;

  final Map<VoiceSound, DateTime> _lastRemotePlay = {};
  final Map<VoiceSound, DateTime> _lastSignalPlay = {};
  final Map<VoiceSound, DateTime> _lastSignalSeen = {};

  Future<void> play(
    VoiceSound sound, {
    bool remote = false,
    required bool enabled,
    required bool deafened,
  }) async {
    if (!enabled || deafened) return;
    if (remote) {
      final now = _clock();
      final last = _lastRemotePlay[sound];
      if (last != null && now.difference(last) < remoteDebounce) return;
      _lastRemotePlay[sound] = now;
    }
    await _player.play(
      sound.assetPath,
      volume: remote ? _remoteVolume : _localVolume,
    );
  }

  /// Trata um sinal recebido da sala (ADR-0001): registra a hora SEMPRE
  /// (para [shouldSuppressRemoteDiff]) e toca com volume remoto se o
  /// cooldown permitir, habilitado e não ensurdecido.
  Future<void> playSignal(
    VoiceSound sound, {
    required bool enabled,
    required bool deafened,
  }) async {
    _lastSignalSeen[sound] = _clock();
    if (!enabled || deafened) return;
    final now = _clock();
    final last = _lastSignalPlay[sound];
    if (last != null && now.difference(last) < signalCooldown) return;
    _lastSignalPlay[sound] = now;
    await _player.play(sound.assetPath, volume: _remoteVolume);
  }

  /// Se um sinal do mesmo tipo chegou há menos de [signalSuppressWindow]:
  /// o fallback por diff deve pular (o sinal já cobriu o evento).
  bool shouldSuppressRemoteDiff(VoiceSound sound) {
    final seen = _lastSignalSeen[sound];
    if (seen == null) return false;
    return _clock().difference(seen) < signalSuppressWindow;
  }

  /// Apenas testes: limpa o debounce entre casos.
  void resetDebounceForTest() {
    _lastRemotePlay.clear();
    _lastSignalPlay.clear();
    _lastSignalSeen.clear();
  }
}
