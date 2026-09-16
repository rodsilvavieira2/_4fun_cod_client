import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/rtc/rtc_providers.dart';
import '../../core/rtc/rtc_service.dart';

class VoiceAudioProcessingState {
  const VoiceAudioProcessingState({
    this.requestedMode = RtcNoiseSuppressionMode.webrtc,
    this.effectiveMode = RtcNoiseSuppressionMode.webrtc,
    this.deepFilterNetAvailable = false,
    this.isApplying = false,
    this.errorMessage,
  });

  final RtcNoiseSuppressionMode requestedMode;
  final RtcNoiseSuppressionMode effectiveMode;
  final bool deepFilterNetAvailable;
  final bool isApplying;
  final String? errorMessage;

  bool get isNoiseSuppressionEnabled =>
      effectiveMode != RtcNoiseSuppressionMode.off;

  VoiceAudioProcessingState copyWith({
    RtcNoiseSuppressionMode? requestedMode,
    RtcNoiseSuppressionMode? effectiveMode,
    bool? deepFilterNetAvailable,
    bool? isApplying,
    Object? errorMessage = _unset,
  }) => VoiceAudioProcessingState(
    requestedMode: requestedMode ?? this.requestedMode,
    effectiveMode: effectiveMode ?? this.effectiveMode,
    deepFilterNetAvailable:
        deepFilterNetAvailable ?? this.deepFilterNetAvailable,
    isApplying: isApplying ?? this.isApplying,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

const Object _unset = Object();

/// Preferências locais do processamento nativo do WebRTC para o microfone.
///
/// A opção fica fora da sessão: precisa estar pronta antes do primeiro publish
/// e continuar valendo para reconnect, troca de device e unmute.
class VoiceAudioProcessingController
    extends Notifier<VoiceAudioProcessingState> {
  static const noiseSuppressionModeKey =
      'voice.audio_processing.noise_suppression_mode';
  static const noiseSuppressionKey =
      'voice.audio_processing.noise_suppression_enabled';

  SharedPreferences? _preferences;
  Future<void>? _initialization;
  bool _disposed = false;

  @override
  VoiceAudioProcessingState build() {
    ref.onDispose(() {
      _disposed = true;
    });
    _initialization = _initialize();
    unawaited(_initialization!);
    return const VoiceAudioProcessingState();
  }

  Future<void> ensureInitialized() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final mode = _readMode(preferences);
      if (_disposed) return;
      _preferences = preferences;
      final status = await ref
          .read(rtcServiceProvider)
          .setNoiseSuppressionMode(mode);
      if (_disposed) return;
      state = _stateFromStatus(status, isApplying: false);
    } catch (_) {
      if (!_disposed) {
        state = state.copyWith(
          errorMessage: 'Não foi possível restaurar o processamento de áudio.',
        );
      }
    }
  }

  RtcNoiseSuppressionMode _readMode(SharedPreferences preferences) {
    final savedMode = preferences.getString(noiseSuppressionModeKey);
    final parsedMode = _modeFromStorage(savedMode);
    if (parsedMode != null) return parsedMode;

    final legacyEnabled = preferences.getBool(noiseSuppressionKey);
    if (legacyEnabled == null) return RtcNoiseSuppressionMode.webrtc;
    final migrated = legacyEnabled
        ? RtcNoiseSuppressionMode.webrtc
        : RtcNoiseSuppressionMode.off;
    unawaited(preferences.setString(noiseSuppressionModeKey, migrated.name));
    return migrated;
  }

  RtcNoiseSuppressionMode? _modeFromStorage(String? value) {
    if (value == null) return null;
    for (final mode in RtcNoiseSuppressionMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

  VoiceAudioProcessingState _stateFromStatus(
    RtcNoiseSuppressionStatus status, {
    required bool isApplying,
  }) {
    return VoiceAudioProcessingState(
      requestedMode: status.requestedMode,
      effectiveMode: status.effectiveMode,
      deepFilterNetAvailable: status.deepFilterNetAvailable,
      isApplying: isApplying,
      errorMessage: status.message,
    );
  }

  Future<bool> setNoiseSuppressionMode(RtcNoiseSuppressionMode mode) async {
    await ensureInitialized();
    if (state.isApplying || mode == state.requestedMode) {
      return mode == state.requestedMode;
    }

    final previous = state;
    state = previous.copyWith(
      requestedMode: mode,
      isApplying: true,
      errorMessage: null,
    );

    final rtc = ref.read(rtcServiceProvider);
    try {
      final status = await rtc.setNoiseSuppressionMode(mode);
      final preferences = _preferences;
      if (preferences != null) {
        await preferences.setString(noiseSuppressionModeKey, mode.name);
      }
      if (!_disposed) {
        state = _stateFromStatus(status, isApplying: false);
      }
      return true;
    } catch (_) {
      try {
        await rtc.setNoiseSuppressionMode(previous.requestedMode);
      } catch (_) {}
      if (!_disposed) {
        state = previous.copyWith(
          isApplying: false,
          errorMessage: 'Não foi possível alterar a supressão de ruído.',
        );
      }
      return false;
    }
  }

  Future<bool> setNoiseSuppressionEnabled(bool enabled) async {
    return setNoiseSuppressionMode(
      enabled ? RtcNoiseSuppressionMode.webrtc : RtcNoiseSuppressionMode.off,
    );
  }
}

final voiceAudioProcessingProvider =
    NotifierProvider<VoiceAudioProcessingController, VoiceAudioProcessingState>(
      VoiceAudioProcessingController.new,
    );
