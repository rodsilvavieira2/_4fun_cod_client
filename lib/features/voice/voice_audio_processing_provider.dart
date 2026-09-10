import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/rtc/rtc_providers.dart';

class VoiceAudioProcessingState {
  const VoiceAudioProcessingState({
    this.isNoiseSuppressionEnabled = true,
    this.isApplying = false,
    this.errorMessage,
  });

  final bool isNoiseSuppressionEnabled;
  final bool isApplying;
  final String? errorMessage;

  VoiceAudioProcessingState copyWith({
    bool? isNoiseSuppressionEnabled,
    bool? isApplying,
    Object? errorMessage = _unset,
  }) => VoiceAudioProcessingState(
    isNoiseSuppressionEnabled:
        isNoiseSuppressionEnabled ?? this.isNoiseSuppressionEnabled,
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
      final enabled = preferences.getBool(noiseSuppressionKey) ?? true;
      if (_disposed) return;
      _preferences = preferences;
      state = state.copyWith(
        isNoiseSuppressionEnabled: enabled,
        errorMessage: null,
      );
      await ref.read(rtcServiceProvider).setNoiseSuppressionEnabled(enabled);
    } catch (_) {
      if (!_disposed) {
        state = state.copyWith(
          errorMessage: 'Não foi possível restaurar o processamento de áudio.',
        );
      }
    }
  }

  Future<bool> setNoiseSuppressionEnabled(bool enabled) async {
    await ensureInitialized();
    if (state.isApplying || enabled == state.isNoiseSuppressionEnabled) {
      return enabled == state.isNoiseSuppressionEnabled;
    }

    final previous = state;
    state = previous.copyWith(
      isNoiseSuppressionEnabled: enabled,
      isApplying: true,
      errorMessage: null,
    );

    final rtc = ref.read(rtcServiceProvider);
    try {
      await rtc.setNoiseSuppressionEnabled(enabled);
      final preferences = _preferences;
      if (preferences != null) {
        await preferences.setBool(noiseSuppressionKey, enabled);
      }
    } catch (_) {
      try {
        await rtc.setNoiseSuppressionEnabled(
          previous.isNoiseSuppressionEnabled,
        );
      } catch (_) {}
      if (!_disposed) {
        state = previous.copyWith(
          isApplying: false,
          errorMessage: 'Não foi possível alterar a supressão de ruído.',
        );
      }
      return false;
    }

    if (!_disposed) {
      state = state.copyWith(isApplying: false, errorMessage: null);
    }
    return true;
  }
}

final voiceAudioProcessingProvider =
    NotifierProvider<VoiceAudioProcessingController, VoiceAudioProcessingState>(
      VoiceAudioProcessingController.new,
    );
