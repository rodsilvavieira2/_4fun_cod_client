import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/rtc/rtc_providers.dart';

/// Estado do volume de voz: saída geral + mapa por participante remoto.
///
/// Percentuais de `0` a `200` (`100` = ganho unitário). O mapa guarda apenas
/// entradas diferentes de `100` (identities estáveis do LiveKit
/// `user_<userId>`, globais — valem para qualquer sala).
class VoiceVolumeState {
  const VoiceVolumeState({
    this.outputPercent = VoiceVolumeDefaults.outputPercent,
    this.participantPercent = const {},
  });

  final int outputPercent;

  /// identity → percent. Nunca contém `100` (normalizado na escrita).
  final Map<String, int> participantPercent;

  int percentOf(String identity) => participantPercent[identity] ?? 100;

  /// Ganho efetivo de um participante: saída × individual, em `0.0..4.0`.
  double effectiveGainOf(String identity) =>
      VoiceVolumeMath.effectiveGain(outputPercent, percentOf(identity));

  VoiceVolumeState copyWith({
    int? outputPercent,
    Map<String, int>? participantPercent,
  }) => VoiceVolumeState(
    outputPercent: outputPercent ?? this.outputPercent,
    participantPercent: participantPercent ?? this.participantPercent,
  );
}

/// Matemática pura do volume (testável sem Flutter).
abstract final class VoiceVolumeMath {
  static const int minPercent = 0;
  static const int maxPercent = 200;
  static const int defaultPercent = 100;

  static int clampPercent(int percent) => percent.clamp(minPercent, maxPercent);

  /// Percent → ganho (`100` → `1.0`, `200` → `2.0`).
  static double gainOf(int percent) => clampPercent(percent) / 100.0;

  /// Ganho efetivo: `saída × individual`, teto `4.0` (`200% × 200%`).
  static double effectiveGain(int outputPercent, int participantPercent) =>
      (gainOf(outputPercent) * gainOf(participantPercent)).clamp(0.0, 4.0);

  /// Ganho público `0.0..2.0` → percent `0..200`.
  static int percentOfGain(double gain) =>
      clampPercent((gain.clamp(0.0, 2.0) * 100).round());
}

abstract final class VoiceVolumeDefaults {
  static const int outputPercent = 100;
}

/// Controller global do volume de voz, separado do estado da chamada.
///
/// - Persiste em `SharedPreferences` com debounce de 250ms.
/// - Encaminha para o [RtcService] a cada mudança (o serviço serializa e
///   aplica só o valor mais recente por participante).
class VoiceVolumeController extends Notifier<VoiceVolumeState> {
  static const outputKey = 'voice.volume.output';
  static const participantsKey = 'voice.volume.participants';
  static const persistDebounce = Duration(milliseconds: 250);

  SharedPreferences? _prefs;
  Timer? _persistTimer;
  bool _disposed = false;

  /// Verdade quando a UI já mutou o estado antes do restore terminar: o
  /// restore adota o storage mas NÃO sobrescreve o estado em memória.
  bool _mutated = false;

  @override
  VoiceVolumeState build() {
    ref.onDispose(() {
      _disposed = true;
      _persistTimer?.cancel();
    });
    unawaited(_restore());
    return const VoiceVolumeState();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      _prefs = prefs;
      if (_mutated) {
        // Mudanças da UI venceram o restore: persiste o estado em memória
        // em vez de ressuscitar o default do storage.
        await _persistNow();
        return;
      }
      final output = VoiceVolumeMath.clampPercent(
        prefs.getInt(outputKey) ?? 100,
      );
      final raw = prefs.getString(participantsKey);
      final map = <String, int>{};
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            decoded.forEach((key, value) {
              if (key is! String || key.isEmpty) return;
              final percent = value is int
                  ? value
                  : value is double
                  ? value.round()
                  : null;
              if (percent == null) return;
              final clamped = VoiceVolumeMath.clampPercent(percent);
              if (clamped != 100) map[key] = clamped;
            });
          }
        } catch (_) {
          // JSON corrompido: começa do default, sobrescrito no próximo save.
        }
      }
      state = VoiceVolumeState(
        outputPercent: output,
        participantPercent: Map.unmodifiable(map),
      );
      _applyToService();
    } catch (_) {
      // Sem storage (ex.: widget test sem mock): mantém os defaults em
      // memória. A persistência tenta de novo no próximo save.
    }
  }

  /// Override de teste: injeta prefs sem tocar no plugin real.
  void debugInjectPreferences(SharedPreferences prefs) => _prefs = prefs;

  void setOutputPercent(int percent) {
    final clamped = VoiceVolumeMath.clampPercent(percent);
    if (clamped == state.outputPercent) return;
    _mutated = true;
    state = state.copyWith(outputPercent: clamped);
    _schedulePersist();
    _applyToService();
  }

  void setParticipantPercent(String identity, int percent) {
    if (identity.isEmpty) return;
    final clamped = VoiceVolumeMath.clampPercent(percent);
    final next = Map<String, int>.of(state.participantPercent);
    if (clamped == 100) {
      if (!next.containsKey(identity)) return;
      next.remove(identity);
    } else {
      if (next[identity] == clamped) return;
      next[identity] = clamped;
    }
    _mutated = true;
    state = state.copyWith(participantPercent: Map.unmodifiable(next));
    _schedulePersist();
    _applyToService();
  }

  void resetOutput() => setOutputPercent(100);

  void resetParticipant(String identity) =>
      setParticipantPercent(identity, 100);

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDebounce, () => unawaited(_persistNow()));
  }

  Future<void> _persistNow() async {
    try {
      final prefs = _prefs ??= await SharedPreferences.getInstance();
      await prefs.setInt(outputKey, state.outputPercent);
      await prefs.setString(
        participantsKey,
        jsonEncode(state.participantPercent),
      );
    } catch (_) {
      // Persistência é best-effort: o estado em memória segue valendo.
    }
  }

  void _applyToService() {
    final service = ref.read(rtcServiceProvider);
    unawaited(
      service.setOutputVolume(VoiceVolumeMath.gainOf(state.outputPercent)),
    );
    for (final entry in state.participantPercent.entries) {
      unawaited(
        service.setParticipantVolume(
          entry.key,
          VoiceVolumeMath.gainOf(entry.value),
        ),
      );
    }
  }
}

final voiceVolumeProvider =
    NotifierProvider<VoiceVolumeController, VoiceVolumeState>(
      VoiceVolumeController.new,
    );
