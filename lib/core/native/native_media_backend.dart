import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../rtc/audio_device_normalizer.dart';
import '../rtc/rtc_service.dart';

/// Plataformas suportadas pelo cliente desktop.
///
/// A decisão fica concentrada na factory. Controllers e serviços não devem
/// consultar [Platform] diretamente.
enum AppRuntimePlatform { linux, windows }

enum NativeFailureCode {
  unavailable,
  permissionDenied,
  notSupported,
  deviceLost,
  cancelled,
  invalidBinding,
}

class NativeFailure implements Exception {
  const NativeFailure(this.code, this.message, {this.recoverable = true});

  final NativeFailureCode code;
  final String message;
  final bool recoverable;

  @override
  String toString() => message;
}

AppRuntimePlatform get currentRuntimePlatform {
  if (kIsWeb) {
    throw UnsupportedError(
      'Web não é suportado pelo 4FunCode. Use Linux ou Windows desktop.',
    );
  }
  if (Platform.isLinux) return AppRuntimePlatform.linux;
  if (Platform.isWindows) return AppRuntimePlatform.windows;
  throw UnsupportedError('Plataforma não suportada para mídia nativa.');
}

enum RtcScreenShareSourceKind { window, display }

class RtcScreenShareSelection {
  const RtcScreenShareSelection({
    required this.kind,
    required this.sourceId,
    required this.usesSystemPicker,
  });

  final RtcScreenShareSourceKind kind;
  final String? sourceId;
  final bool usesSystemPicker;
}

class RtcScreenShareSource {
  const RtcScreenShareSource({
    required this.id,
    required this.name,
    required this.kind,
    this.thumbnail,
  });

  final String id;
  final String name;
  final RtcScreenShareSourceKind kind;
  final Uint8List? thumbnail;
}

class ScreenShareCapabilities {
  const ScreenShareCapabilities({
    required this.usesSystemPicker,
    required this.supportsWindowSources,
    required this.supportsSystemAudio,
  });

  final bool usesSystemPicker;
  final bool supportsWindowSources;
  final bool supportsSystemAudio;
}

/// Porta para a seleção de fontes de compartilhamento de tela.
abstract interface class NativeScreenShareBackend {
  ScreenShareCapabilities get capabilities;

  Future<List<RtcScreenShareSource>> loadSources();

  bool canUseKind(RtcScreenShareSourceKind kind);

  String? disabledReasonFor(RtcScreenShareSourceKind kind);
}

/// Porta para a criação de uma track temporária de câmera.
abstract interface class NativeCameraBackend {
  Future<LocalVideoTrack> createCameraTrack(CameraCaptureOptions options);
}

/// Porta para enumeração e seleção de dispositivos fora de uma Room LiveKit.
abstract interface class NativeAudioDevicesBackend {
  Future<List<MediaDevice>> listInputs();

  Future<List<MediaDevice>> listOutputs();

  Future<void> selectInput(MediaDevice device);

  Future<void> selectOutput(MediaDevice device);
}

class NativeMediaServices {
  const NativeMediaServices({
    required this.screenShare,
    required this.camera,
    required this.audioDevices,
  });

  final NativeScreenShareBackend screenShare;
  final NativeCameraBackend camera;
  final NativeAudioDevicesBackend audioDevices;
}

abstract interface class NativeMediaServicesFactory {
  NativeMediaServices create(AppRuntimePlatform platform);
}

class DefaultNativeMediaServicesFactory implements NativeMediaServicesFactory {
  const DefaultNativeMediaServicesFactory();

  @override
  NativeMediaServices create(AppRuntimePlatform platform) {
    return switch (platform) {
      AppRuntimePlatform.linux => const NativeMediaServices(
        screenShare: LinuxScreenShareBackend(),
        camera: LinuxCameraBackend(),
        audioDevices: LinuxAudioDevicesBackend(),
      ),
      AppRuntimePlatform.windows => const NativeMediaServices(
        screenShare: WindowsScreenShareBackend(),
        camera: WindowsCameraBackend(),
        audioDevices: WindowsAudioDevicesBackend(),
      ),
    };
  }
}

abstract class _SystemPickerScreenShareBackend
    implements NativeScreenShareBackend {
  const _SystemPickerScreenShareBackend();

  @override
  bool canUseKind(RtcScreenShareSourceKind kind) => true;

  @override
  String? disabledReasonFor(RtcScreenShareSourceKind kind) => null;

  @override
  Future<List<RtcScreenShareSource>> loadSources() => Future.value(const []);
}

class LinuxScreenShareBackend extends _SystemPickerScreenShareBackend {
  const LinuxScreenShareBackend();

  @override
  ScreenShareCapabilities get capabilities => const ScreenShareCapabilities(
    usesSystemPicker: true,
    supportsWindowSources: true,
    supportsSystemAudio: true,
  );
}

class WindowsScreenShareBackend implements NativeScreenShareBackend {
  const WindowsScreenShareBackend();

  @override
  ScreenShareCapabilities get capabilities => const ScreenShareCapabilities(
    usesSystemPicker: false,
    supportsWindowSources: true,
    supportsSystemAudio: true,
  );

  @override
  bool canUseKind(RtcScreenShareSourceKind kind) => true;

  @override
  String? disabledReasonFor(RtcScreenShareSourceKind kind) => null;

  @override
  Future<List<RtcScreenShareSource>> loadSources() async {
    final sources = await rtc.desktopCapturer.getSources(
      types: const [rtc.SourceType.Window, rtc.SourceType.Screen],
    );
    return sources.map(_screenShareSourceFromWebRtc).toList(growable: false);
  }
}

RtcScreenShareSource _screenShareSourceFromWebRtc(
  rtc.DesktopCapturerSource source,
) {
  final kind = source.type == rtc.SourceType.Window
      ? RtcScreenShareSourceKind.window
      : RtcScreenShareSourceKind.display;
  final fallbackName = kind == RtcScreenShareSourceKind.window
      ? 'Janela'
      : 'Display';
  final thumbnail = source.thumbnail;
  return RtcScreenShareSource(
    id: source.id,
    name: source.name.isEmpty ? fallbackName : source.name,
    kind: kind,
    thumbnail: thumbnail == null || thumbnail.isEmpty ? null : thumbnail,
  );
}

abstract class _LiveKitCameraBackend implements NativeCameraBackend {
  const _LiveKitCameraBackend();

  @override
  Future<LocalVideoTrack> createCameraTrack(CameraCaptureOptions options) =>
      LocalVideoTrack.createCameraTrack(options);
}

class LinuxCameraBackend extends _LiveKitCameraBackend {
  const LinuxCameraBackend();
}

class WindowsCameraBackend extends _LiveKitCameraBackend {
  const WindowsCameraBackend();
}

abstract class _HardwareAudioDevicesBackend
    implements NativeAudioDevicesBackend {
  const _HardwareAudioDevicesBackend();

  @override
  Future<List<MediaDevice>> listInputs() async => _normalize(
    await Hardware.instance.audioInputs(),
    RtcMediaDeviceKind.audioInput,
  );

  @override
  Future<List<MediaDevice>> listOutputs() async => _normalize(
    await Hardware.instance.audioOutputs(),
    RtcMediaDeviceKind.audioOutput,
  );

  @override
  Future<void> selectInput(MediaDevice device) =>
      Hardware.instance.selectAudioInput(device);

  @override
  Future<void> selectOutput(MediaDevice device) =>
      Hardware.instance.selectAudioOutput(device);

  List<MediaDevice> _normalize(
    List<MediaDevice> devices,
    RtcMediaDeviceKind kind,
  ) {
    final normalized = normalizeAudioDevices(
      devices.map(
        (device) => RtcAudioDevice(
          id: device.deviceId,
          label: device.label,
          kind: kind,
        ),
      ),
    );
    final ids = normalized.map((device) => device.id).toSet();
    return devices.where((device) => ids.contains(device.deviceId)).toList();
  }
}

class LinuxAudioDevicesBackend extends _HardwareAudioDevicesBackend {
  const LinuxAudioDevicesBackend();
}

class WindowsAudioDevicesBackend extends _HardwareAudioDevicesBackend {
  const WindowsAudioDevicesBackend();
}
