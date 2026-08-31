import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/rtc/rtc_providers.dart';
import 'push_to_talk.dart';
import 'push_to_talk_input.dart';

class VoiceControlsState {
  const VoiceControlsState({
    this.isMuted = false,
    this.isDeafened = false,
    this.isPushToTalkEnabled = false,
    this.pushToTalkBinding,
    this.pushToTalkReleaseDelayMs = 20,
    this.isPushToTalkPressed = false,
    this.isPushToTalkRegistered = false,
    this.isRecordingPushToTalk = false,
    this.isApplying = false,
    this.errorMessage,
  });

  final bool isMuted;
  final bool isDeafened;
  final bool isPushToTalkEnabled;
  final PushToTalkBinding? pushToTalkBinding;
  final int pushToTalkReleaseDelayMs;
  final bool isPushToTalkPressed;
  final bool isPushToTalkRegistered;
  final bool isRecordingPushToTalk;
  final bool isApplying;
  final String? errorMessage;

  bool get isMicrophoneEnabled =>
      !isMuted && !isDeafened && (!isPushToTalkEnabled || isPushToTalkPressed);

  VoiceControlsState copyWith({
    bool? isMuted,
    bool? isDeafened,
    bool? isPushToTalkEnabled,
    Object? pushToTalkBinding = _unset,
    int? pushToTalkReleaseDelayMs,
    bool? isPushToTalkPressed,
    bool? isPushToTalkRegistered,
    bool? isRecordingPushToTalk,
    bool? isApplying,
    Object? errorMessage = _unset,
  }) => VoiceControlsState(
    isMuted: isMuted ?? this.isMuted,
    isDeafened: isDeafened ?? this.isDeafened,
    isPushToTalkEnabled: isPushToTalkEnabled ?? this.isPushToTalkEnabled,
    pushToTalkBinding: identical(pushToTalkBinding, _unset)
        ? this.pushToTalkBinding
        : pushToTalkBinding as PushToTalkBinding?,
    pushToTalkReleaseDelayMs:
        pushToTalkReleaseDelayMs ?? this.pushToTalkReleaseDelayMs,
    isPushToTalkPressed: isPushToTalkPressed ?? this.isPushToTalkPressed,
    isPushToTalkRegistered:
        isPushToTalkRegistered ?? this.isPushToTalkRegistered,
    isRecordingPushToTalk:
        isRecordingPushToTalk ?? this.isRecordingPushToTalk,
    isApplying: isApplying ?? this.isApplying,
    errorMessage: identical(errorMessage, _unset)
        ? this.errorMessage
        : errorMessage as String?,
  );
}

const Object _unset = Object();

/// Persiste o mute manual, ensurdecer e Push to Talk. PTT é uma porta extra:
/// ele nunca desfaz mute/ensurdecer e só abre o microfone enquanto pressionado.
class VoiceControlsController extends Notifier<VoiceControlsState> {
  static const _mutedKey = 'voice.microphone_muted';
  static const _deafenedKey = 'voice.deafened';
  static const _pttEnabledKey = 'voice.push_to_talk.enabled';
  static const _pttBindingKey = 'voice.push_to_talk.binding';
  static const _pttReleaseDelayKey = 'voice.push_to_talk.release_delay_ms';

  SharedPreferences? _preferences;
  Future<void>? _initialization;
  Timer? _releaseTimer;
  late PushToTalkInputService _inputService;
  bool _enableAfterRecording = false;
  bool _disposed = false;

  @override
  VoiceControlsState build() {
    _inputService = ref.read(pushToTalkInputServiceProvider);
    ref.onDispose(() {
      _disposed = true;
      _releaseTimer?.cancel();
    });
    _initialization = _initialize();
    unawaited(_initialization!);
    return const VoiceControlsState();
  }

  Future<void> ensureInitialized() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final binding = _decodeBinding(preferences.getString(_pttBindingKey));
      final wasEnabled = preferences.getBool(_pttEnabledKey) ?? false;
      final delay = (preferences.getInt(_pttReleaseDelayKey) ?? 20).clamp(
        0,
        2000,
      );
      if (_disposed) return;
      _preferences = preferences;
      state = state.copyWith(
        isMuted: preferences.getBool(_mutedKey) ?? false,
        isDeafened: preferences.getBool(_deafenedKey) ?? false,
        isPushToTalkEnabled: wasEnabled && binding != null,
        pushToTalkBinding: binding,
        pushToTalkReleaseDelayMs: delay,
        errorMessage: wasEnabled && binding == null
            ? 'Push to Talk precisa de um atalho configurado.'
            : null,
      );
      if (state.isPushToTalkEnabled) await _registerPushToTalk(binding!);
      await _applyToRtc();
    } catch (_) {
      if (!_disposed) {
        state = state.copyWith(
          errorMessage: 'Não foi possível restaurar os controles de voz.',
        );
      }
    }
  }

  PushToTalkBinding? _decodeBinding(String? encoded) {
    if (encoded == null) return null;
    try {
      return PushToTalkBinding.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> toggleMicrophone() async {
    await ensureInitialized();
    if (state.isApplying || state.isDeafened) return false;
    return _change(isMuted: !state.isMuted, isDeafened: state.isDeafened);
  }

  Future<bool> toggleDeafen() async {
    await ensureInitialized();
    if (state.isApplying) return false;
    if (!state.isDeafened) _cancelPress();
    return _change(isMuted: state.isMuted, isDeafened: !state.isDeafened);
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
    await _saveManual(isMuted: isMuted, isDeafened: isDeafened);
    if (!_disposed) {
      state = state.copyWith(
        isMuted: isMuted,
        isDeafened: isDeafened,
        isApplying: false,
        errorMessage: null,
      );
    }
    return true;
  }

  Future<void> _saveManual({
    required bool isMuted,
    required bool isDeafened,
  }) async {
    final preferences = _preferences;
    if (preferences == null) return;
    try {
      await preferences.setBool(_mutedKey, isMuted);
      await preferences.setBool(_deafenedKey, isDeafened);
    } catch (_) {
      if (!_disposed) {
        state = state.copyWith(
          errorMessage: 'Não foi possível salvar os controles de voz.',
        );
      }
    }
  }

  Future<bool> setPushToTalkEnabled(bool enabled) async {
    await ensureInitialized();
    if (!enabled) {
      _enableAfterRecording = false;
      await resetPushToTalkPress();
      await _inputService.configure(null);
      state = state.copyWith(
        isPushToTalkEnabled: false,
        isPushToTalkRegistered: false,
        isRecordingPushToTalk: false,
        errorMessage: null,
      );
      await _savePushToTalk();
      await _applyToRtc();
      return true;
    }
    if (state.pushToTalkBinding == null) {
      _enableAfterRecording = true;
      startPushToTalkRecording();
      return false;
    }
    state = state.copyWith(
      isPushToTalkEnabled: true,
      isPushToTalkPressed: false,
      errorMessage: null,
    );
    if (!await _registerPushToTalk(state.pushToTalkBinding!)) return false;
    await _savePushToTalk();
    await _applyToRtc();
    return true;
  }

  void startPushToTalkRecording() {
    _cancelPress();
    state = state.copyWith(
      isRecordingPushToTalk: true,
      isPushToTalkPressed: false,
      errorMessage: null,
    );
    unawaited(_applyToRtc());
  }

  void cancelPushToTalkRecording() {
    _enableAfterRecording = false;
    state = state.copyWith(isRecordingPushToTalk: false);
  }

  Future<void> recordPushToTalkKey(KeyEvent event) async {
    final binding = bindingFromKeyEvent(event);
    if (binding != null) await _setPushToTalkBinding(binding);
  }

  Future<void> recordPushToTalkMouse(int buttons) async {
    final binding = bindingFromMouseButton(buttons);
    if (binding != null) await _setPushToTalkBinding(binding);
  }

  Future<void> _setPushToTalkBinding(PushToTalkBinding binding) async {
    await ensureInitialized();
    await resetPushToTalkPress();
    final shouldEnable = _enableAfterRecording || state.isPushToTalkEnabled;
    _enableAfterRecording = false;
    await _inputService.configure(null);
    state = state.copyWith(
      pushToTalkBinding: binding,
      isRecordingPushToTalk: false,
      isPushToTalkEnabled: shouldEnable,
      isPushToTalkRegistered: false,
      errorMessage: null,
    );
    if (shouldEnable && !await _registerPushToTalk(binding)) return;
    await _savePushToTalk();
    await _applyToRtc();
  }

  Future<void> clearPushToTalkBinding() async {
    await ensureInitialized();
    _enableAfterRecording = false;
    await resetPushToTalkPress();
    await _inputService.configure(null);
    state = state.copyWith(
      isPushToTalkEnabled: false,
      pushToTalkBinding: null,
      isPushToTalkRegistered: false,
      isRecordingPushToTalk: false,
      errorMessage: null,
    );
    await _savePushToTalk();
    await _applyToRtc();
  }

  Future<void> setPushToTalkReleaseDelay(int value) async {
    await ensureInitialized();
    state = state.copyWith(pushToTalkReleaseDelayMs: value.clamp(0, 2000));
    await _savePushToTalk();
  }

  Future<void> setPushToTalkPressed(bool pressed) async {
    if (!state.isPushToTalkEnabled || !state.isPushToTalkRegistered) return;
    if (pressed) {
      _cancelPress();
      if (state.isPushToTalkPressed) return;
      state = state.copyWith(isPushToTalkPressed: true, errorMessage: null);
      await _applyToRtc();
      return;
    }
    if (!state.isPushToTalkPressed) return;
    _releaseTimer?.cancel();
    if (state.pushToTalkReleaseDelayMs == 0) {
      state = state.copyWith(isPushToTalkPressed: false);
      await _applyToRtc();
      return;
    }
    _releaseTimer = Timer(
      Duration(milliseconds: state.pushToTalkReleaseDelayMs),
      () {
        if (_disposed || !state.isPushToTalkEnabled) return;
        state = state.copyWith(isPushToTalkPressed: false);
        unawaited(_applyToRtc());
      },
    );
  }

  Future<void> resetPushToTalkPress() async {
    _cancelPress();
    if (!state.isPushToTalkPressed) return;
    state = state.copyWith(isPushToTalkPressed: false);
    await _applyToRtc();
  }

  /// O runner informa esta condição quando uma permissão de atalho global é
  /// recusada depois da configuração inicial (por exemplo, pelo portal Linux).
  /// Mantemos o microfone fechado e preservamos a configuração para que ela
  /// possa ser registrada novamente quando a permissão for corrigida.
  Future<void> handlePushToTalkRegistrationFailure() async {
    await ensureInitialized();
    _cancelPress();
    state = state.copyWith(
      isPushToTalkPressed: false,
      isPushToTalkRegistered: false,
      errorMessage:
          'O atalho global foi recusado ou não está disponível. O microfone permaneceu fechado.',
    );
    await _savePushToTalk();
    await _applyToRtc();
  }

  void _cancelPress() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
  }

  Future<bool> _registerPushToTalk(PushToTalkBinding binding) async {
    state = state.copyWith(isPushToTalkRegistered: false);
    final registered = await _inputService.configure(binding);
    if (_disposed) return false;
    if (!registered) {
      state = state.copyWith(
        isPushToTalkRegistered: false,
        errorMessage:
            'Não foi possível registrar o atalho global. O microfone permaneceu fechado.',
      );
      await _savePushToTalk();
      await _applyToRtc();
      return false;
    }
    state = state.copyWith(isPushToTalkRegistered: true, errorMessage: null);
    return true;
  }

  Future<void> _savePushToTalk() async {
    final preferences = _preferences;
    if (preferences == null) return;
    try {
      await preferences.setBool(_pttEnabledKey, state.isPushToTalkEnabled);
      await preferences.setInt(
        _pttReleaseDelayKey,
        state.pushToTalkReleaseDelayMs,
      );
      final binding = state.pushToTalkBinding;
      if (binding == null) {
        await preferences.remove(_pttBindingKey);
      } else {
        await preferences.setString(_pttBindingKey, jsonEncode(binding.toJson()));
      }
    } catch (_) {
      if (!_disposed) {
        state = state.copyWith(errorMessage: 'Não foi possível salvar o Push to Talk.');
      }
    }
  }

  Future<void> _applyToRtc({bool? isMuted, bool? isDeafened}) async {
    final muted = isMuted ?? state.isMuted;
    final deafened = isDeafened ?? state.isDeafened;
    final microphoneEnabled =
        !muted &&
        !deafened &&
        (!state.isPushToTalkEnabled || state.isPushToTalkPressed);
    final rtc = ref.read(rtcServiceProvider);
    if (deafened) {
      await rtc.disableMicrophone();
      await rtc.setRemoteAudioEnabled(false);
      return;
    }
    await rtc.setRemoteAudioEnabled(true);
    if (microphoneEnabled) {
      await rtc.enableMicrophone();
    } else {
      await rtc.disableMicrophone();
    }
  }
}

final voiceControlsProvider =
    NotifierProvider<VoiceControlsController, VoiceControlsState>(
      VoiceControlsController.new,
    );
