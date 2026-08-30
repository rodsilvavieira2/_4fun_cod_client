import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/rtc/rtc_providers.dart';

/// Preferências globais dos controles de voz do rodapé.
///
/// [isMuted] representa a decisão explícita do usuário. Ensurdecer não a
/// altera: apenas desliga efetivamente o microfone enquanto estiver ativo.
/// Isso permite restaurar corretamente o estado anterior mesmo depois de
/// reiniciar o aplicativo.
class VoiceControlsState {
  const VoiceControlsState({
    this.isMuted = false,
    this.isDeafened = false,
    this.isApplying = false,
    this.errorMessage,
  });

  final bool isMuted;
  final bool isDeafened;
  final bool isApplying;
  final String? errorMessage;

  /// Estado efetivo da publicação local. Ensurdecer sempre vence o unmute.
  bool get isMicrophoneEnabled => !isMuted && !isDeafened;

  VoiceControlsState copyWith({
    bool? isMuted,
    bool? isDeafened,
    bool? isApplying,
    Object? errorMessage = _unset,
  }) {
    return VoiceControlsState(
      isMuted: isMuted ?? this.isMuted,
      isDeafened: isDeafened ?? this.isDeafened,
      isApplying: isApplying ?? this.isApplying,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const Object _unset = Object();

/// Fonte de verdade persistida para mute e ensurdecer, dentro e fora de uma
/// chamada. O [RtcService] aceita essas operações sem sala e as aplica no
/// próximo connect.
class VoiceControlsController extends Notifier<VoiceControlsState> {
  static const _mutedKey = 'voice.microphone_muted';
  static const _deafenedKey = 'voice.deafened';

  SharedPreferences? _preferences;
  Future<void>? _initialization;
  bool _disposed = false;

  @override
  VoiceControlsState build() {
    ref.onDispose(() => _disposed = true);
    _initialization = _initialize();
    unawaited(_initialization!);
    return const VoiceControlsState();
  }

  /// Garante a restauração e a aplicação no RTC antes de entrar numa sala.
  Future<void> ensureInitialized() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final isMuted = preferences.getBool(_mutedKey) ?? false;
      final isDeafened = preferences.getBool(_deafenedKey) ?? false;
      if (_disposed) return;
      _preferences = preferences;
      state = state.copyWith(
        isMuted: isMuted,
        isDeafened: isDeafened,
        errorMessage: null,
      );
      await _applyToRtc(isMuted: isMuted, isDeafened: isDeafened);
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        errorMessage: 'Não foi possível restaurar os controles de voz.',
      );
    }
  }

  Future<bool> toggleMicrophone() async {
    await ensureInitialized();
    final current = state;
    if (current.isApplying || current.isDeafened) return false;
    return _change(isMuted: !current.isMuted, isDeafened: current.isDeafened);
  }

  Future<bool> toggleDeafen() async {
    await ensureInitialized();
    final current = state;
    if (current.isApplying) return false;
    return _change(isMuted: current.isMuted, isDeafened: !current.isDeafened);
  }

  Future<bool> _change({
    required bool isMuted,
    required bool isDeafened,
  }) async {
    final previous = state;
    state = previous.copyWith(isApplying: true, errorMessage: null);
    try {
      await _applyToRtc(isMuted: isMuted, isDeafened: isDeafened);
    } catch (_) {
      // A operação pode ter falhado após alterar só uma parte (por exemplo,
      // mic desligado mas track remota não parada). Restaura o estado anterior
      // em best-effort antes de manter a preferência visível inalterada.
      try {
        await _applyToRtc(
          isMuted: previous.isMuted,
          isDeafened: previous.isDeafened,
        );
      } catch (_) {}
      if (!_disposed) {
        state = previous.copyWith(
          isApplying: false,
          errorMessage: isDeafened != previous.isDeafened
              ? 'Não foi possível alterar o ensurdecer.'
              : 'Não foi possível alternar o microfone.',
        );
      }
      return false;
    }

    final preferences = _preferences;
    if (preferences != null) {
      try {
        await preferences.setBool(_mutedKey, isMuted);
        await preferences.setBool(_deafenedKey, isDeafened);
      } catch (_) {
        // A chamada já foi aplicada; sinaliza apenas que ela não sobreviverá
        // a uma reinicialização, sem desfazer a sessão em andamento.
        if (!_disposed) {
          state = VoiceControlsState(
            isMuted: isMuted,
            isDeafened: isDeafened,
            errorMessage: 'Não foi possível salvar os controles de voz.',
          );
        }
        return true;
      }
    }
    if (!_disposed) {
      state = VoiceControlsState(isMuted: isMuted, isDeafened: isDeafened);
    }
    return true;
  }

  Future<void> _applyToRtc({
    required bool isMuted,
    required bool isDeafened,
  }) async {
    final rtc = ref.read(rtcServiceProvider);
    if (isDeafened) {
      await rtc.disableMicrophone();
      await rtc.setRemoteAudioEnabled(false);
      return;
    }
    await rtc.setRemoteAudioEnabled(true);
    if (isMuted) {
      await rtc.disableMicrophone();
    } else {
      await rtc.enableMicrophone();
    }
  }
}

final voiceControlsProvider =
    NotifierProvider<VoiceControlsController, VoiceControlsState>(
      VoiceControlsController.new,
    );
