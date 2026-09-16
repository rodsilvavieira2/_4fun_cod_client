#ifndef PLUGINS_FLUTTER_WEBRTC_HXX
#define PLUGINS_FLUTTER_WEBRTC_HXX

#include "flutter_common.h"

#include "flutter_data_channel.h"
#include "flutter_data_packet_cryptor.h"
#include "deep_filter_audio_processor.h"
#include "flutter_frame_cryptor.h"
#include "flutter_media_stream.h"
#include "flutter_peerconnection.h"
#include "flutter_screen_capture.h"
#include "flutter_video_renderer.h"

#include "libwebrtc.h"
#include "rtc_logging.h"

namespace flutter_webrtc_plugin {

using namespace libwebrtc;

class FlutterWebRTCPlugin : public flutter::Plugin {
 public:
  virtual BinaryMessenger* messenger() = 0;

  virtual TextureRegistrar* textures() = 0;

  virtual TaskRunner* task_runner() = 0;
};

class FlutterWebRTC : public FlutterWebRTCBase,
                      public FlutterVideoRendererManager,
                      public FlutterMediaStream,
                      public FlutterPeerConnection,
                      public FlutterScreenCapture,
                      public FlutterDataChannel,
                      public FlutterFrameCryptor,
                      public FlutterDataPacketCryptor {
 public:
  FlutterWebRTC(FlutterWebRTCPlugin* plugin);
  virtual ~FlutterWebRTC();

  void HandleMethodCall(const MethodCallProxy& method_call,
                        std::unique_ptr<MethodResultProxy> result);

 private:
  // Toggles the Studio capture pipeline (DeepFilterNet + own dynamics).
  // The method-channel name stays `setDeepFilterNoiseSuppressionEnabled`
  // for protocol stability with the Dart side.
  bool SetStudioPipelineEnabled(bool enabled);

  // Returns the shared passthrough processor, creating it on first use.
  // Must only be called on the method-channel thread.
  libwebrtc::RTCAudioProcessing::CustomProcessing* ensure_passthrough() {
    if (!passthrough_audio_processor_) {
      passthrough_audio_processor_ =
          std::make_unique<PassthroughAudioProcessor>();
    }
    return passthrough_audio_processor_.get();
  }

  void initLoggerCallback(RTCLoggingSeverity severity);
  RTCLoggingSeverity str2LogSeverity(std::string str);

  std::unique_ptr<AudioEnhancementPipeline> studio_pipeline_;
  // Always-valid "off" target for SetCapturePostProcessing (see
  // PassthroughAudioProcessor). Lazily created by ensure_passthrough().
  std::unique_ptr<PassthroughAudioProcessor> passthrough_audio_processor_;
};

}  // namespace flutter_webrtc_plugin

#endif  // PLUGINS_FLUTTER_WEBRTC_HXX
