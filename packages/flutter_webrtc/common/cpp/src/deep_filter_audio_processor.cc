#include "deep_filter_audio_processor.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <vector>

extern "C" {
bool fourfun_deepfilter_runtime_available();
void* fourfun_deepfilter_create(uint32_t sample_rate_hz,
                                uintptr_t channels,
                                char* error_buffer,
                                uintptr_t error_buffer_len);
bool fourfun_deepfilter_process(void* state,
                                float* interleaved_samples,
                                uintptr_t frames,
                                uintptr_t channels,
                                char* error_buffer,
                                uintptr_t error_buffer_len);
void fourfun_deepfilter_destroy(void* state);
}

namespace flutter_webrtc_plugin {
namespace {

constexpr int kDeepFilterSampleRate = 48000;
constexpr size_t kErrorBufferLen = 256;

std::string ReadError(char* buffer) {
  return buffer[0] == '\0' ? "DeepFilterNet indisponível" : std::string(buffer);
}

}  // namespace

DeepFilterAudioProcessor::DeepFilterAudioProcessor() = default;

DeepFilterAudioProcessor::~DeepFilterAudioProcessor() {
  destroy_state();
}

bool DeepFilterAudioProcessor::runtime_available() const {
  return fourfun_deepfilter_runtime_available();
}

void DeepFilterAudioProcessor::StateDeleter::operator()(void* state) const {
  if (state != nullptr) {
    fourfun_deepfilter_destroy(state);
  }
}

void DeepFilterAudioProcessor::Initialize(int sample_rate_hz,
                                          int num_channels) {
  ensure_state(sample_rate_hz, num_channels);
}

void DeepFilterAudioProcessor::Process(int num_bands,
                                       int num_frames,
                                       int buffer_size,
                                       float* buffer) {
  if (buffer == nullptr || failed_ || num_frames <= 0 || buffer_size <= 0) {
    return;
  }
  const int inferred_channels = std::max(
      1, std::min(num_bands > 0 ? num_bands : 1, buffer_size / num_frames));
  if (!ensure_state(sample_rate_hz_, inferred_channels)) {
    return;
  }

  char error[kErrorBufferLen] = {};
  const bool ok = fourfun_deepfilter_process(
      state_.get(), buffer, static_cast<uintptr_t>(num_frames),
      static_cast<uintptr_t>(inferred_channels), error, kErrorBufferLen);
  if (!ok) {
    failed_ = true;
    last_error_ = ReadError(error);
    destroy_state();
  }
}

void DeepFilterAudioProcessor::Reset(int new_rate) {
  destroy_state();
  sample_rate_hz_ = new_rate;
  failed_ = false;
  last_error_.clear();
}

void DeepFilterAudioProcessor::Release() {
  destroy_state();
}

bool DeepFilterAudioProcessor::ensure_state(int sample_rate_hz,
                                            int num_channels) {
  if (failed_) return false;
  if (sample_rate_hz <= 0) sample_rate_hz = kDeepFilterSampleRate;
  if (num_channels <= 0) num_channels = 1;
  if (sample_rate_hz != kDeepFilterSampleRate) {
    failed_ = true;
    last_error_ = "DeepFilterNet requer captura em 48 kHz";
    destroy_state();
    return false;
  }
  if (state_ != nullptr && sample_rate_hz_ == sample_rate_hz &&
      num_channels_ == num_channels) {
    return true;
  }

  destroy_state();
  char error[kErrorBufferLen] = {};
  void* state = fourfun_deepfilter_create(
      static_cast<uint32_t>(sample_rate_hz), static_cast<uintptr_t>(num_channels),
      error, kErrorBufferLen);
  if (state == nullptr) {
    failed_ = true;
    last_error_ = ReadError(error);
    return false;
  }
  state_.reset(state);
  sample_rate_hz_ = sample_rate_hz;
  num_channels_ = num_channels;
  last_error_.clear();
  return true;
}

void DeepFilterAudioProcessor::destroy_state() {
  state_.reset();
}

}  // namespace flutter_webrtc_plugin
