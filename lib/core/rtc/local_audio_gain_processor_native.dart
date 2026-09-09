import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart'
    show AudioProcessorOptions, Room, TrackProcessor;

LocalAudioGainProcessor createLocalAudioGainProcessor(double gain) =>
    LocalAudioGainProcessor(gain);

class LocalAudioGainProcessor implements TrackProcessor<AudioProcessorOptions> {
  LocalAudioGainProcessor(double gain) : _gain = _normalize(gain);

  double _gain;
  rtc.MediaStreamTrack? _track;

  @override
  String get name => '4fun-input-gain';

  @override
  rtc.MediaStreamTrack? get processedTrack => null;

  Future<void> setGain(double gain) async {
    _gain = _normalize(gain);
    await _apply();
  }

  @override
  Future<void> init(AudioProcessorOptions options) async {
    _track = options.track;
    await _apply();
  }

  @override
  Future<void> restart(AudioProcessorOptions options) => init(options);

  @override
  Future<void> destroy() async {
    _track = null;
  }

  @override
  Future<void> onPublish(Room room) async {}

  @override
  Future<void> onUnpublish() async {}

  Future<void> _apply() async {
    final track = _track;
    if (track == null) return;
    await rtc.Helper.setVolume(_gain, track);
  }

  static double _normalize(double gain) =>
      gain.isNaN ? 1.0 : gain.clamp(0.0, 1.0);
}
