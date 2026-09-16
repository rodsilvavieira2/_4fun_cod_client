#ifndef FLUTTER_WEBRTC_DEEP_FILTER_AUDIO_PROCESSOR_HXX
#define FLUTTER_WEBRTC_DEEP_FILTER_AUDIO_PROCESSOR_HXX

#include <memory>
#include <string>

#include "rtc_audio_processing.h"

namespace flutter_webrtc_plugin {

class DeepFilterAudioProcessor
    : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  DeepFilterAudioProcessor();
  ~DeepFilterAudioProcessor() override;

  bool runtime_available() const;
  bool failed() const { return failed_; }
  std::string last_error() const { return last_error_; }

  void Initialize(int sample_rate_hz, int num_channels) override;
  void Process(int num_bands,
               int num_frames,
               int buffer_size,
               float* buffer) override;
  void Reset(int new_rate) override;
  void Release() override;

 private:
  struct StateDeleter {
    void operator()(void* state) const;
  };

  bool ensure_state(int sample_rate_hz, int num_channels);
  void destroy_state();

  std::unique_ptr<void, StateDeleter> state_;
  int sample_rate_hz_ = 0;
  int num_channels_ = 0;
  bool failed_ = false;
  std::string last_error_;
};

}  // namespace flutter_webrtc_plugin

#endif  // FLUTTER_WEBRTC_DEEP_FILTER_AUDIO_PROCESSOR_HXX
