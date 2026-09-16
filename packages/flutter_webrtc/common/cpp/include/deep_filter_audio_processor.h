#ifndef FLUTTER_WEBRTC_AUDIO_ENHANCEMENT_PIPELINE_HXX
#define FLUTTER_WEBRTC_AUDIO_ENHANCEMENT_PIPELINE_HXX

#include <cstddef>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "rtc_audio_processing.h"

namespace flutter_webrtc_plugin {

// Runtime counters for the Studio capture path. Read from the
// method-channel thread; updated on the APM audio thread.
struct AudioPipelineStats {
  uint64_t processed_hops = 0;   // 10 ms / 480-sample hops enhanced by the net
  uint64_t bypassed_frames = 0;  // input frames passed through untouched
  uint64_t underruns = 0;        // output-FIFO shortages + FIFO safety resets
  int last_rate_hz = 0;          // sample rate of the most recent Process call
  float agc_gain_db = 0.0f;      // current own-AGC gain (diagnostic snapshot)
  uint64_t limited_frames = 0;   // samples attenuated by the limiter
  float input_peak = 0.0f;   // decaying peak-hold of audio ENTERING Process
  float output_peak = 0.0f;  // decaying peak-hold of audio LEAVING Process
};

// 4fun_cod Studio pipeline, applied to the mic BEFORE Opus encoding:
//
//   WebRTC AEC ─► DeepFilterNet ─► own AGC ─► light compressor ─► limiter
//
// AEC and the high-pass filter stay in the WebRTC APM domain (capture
// constraints). This post-processor runs after them and REPLACES the WebRTC
// noise suppression + AGC stages, which the Dart side disables in Studio
// mode so no stage runs twice (double NS sounds robotic; double AGC
// "breathes"). Order matters: the AGC sees already-denoised audio, and the
// limiter only ever acts as a safety net for residual peaks.
//
// Wire-scale note: the APM hook delivers float samples in int16 range, so
// Process normalizes to ±1 around the DF+dynamics core (AutoScale) and
// restores the wire scale before returning.
class AudioEnhancementPipeline
    : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  AudioEnhancementPipeline();
  ~AudioEnhancementPipeline() override;

  bool runtime_available() const;
  bool failed() const {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    return consecutive_errors_ >= kErrorLatchThreshold;
  }
  std::string last_error() const {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    return last_error_;
  }
  AudioPipelineStats stats() const {
    std::lock_guard<std::recursive_mutex> lock(mutex_);
    return AudioPipelineStats{processed_hops_, bypassed_frames_, underruns_,
                             last_rate_hz_, dynamics_.agc_gain_db(),
                             dynamics_.limited_frames(), input_peak_,
                             output_peak_};
  }

  void Initialize(int sample_rate_hz, int num_channels) override;
  void Process(int num_bands,
               int num_frames,
               int buffer_size,
               float* buffer) override;
  void Reset(int new_rate) override;
  void Release() override;
  // End-of-stream net drain (harness-only): runs one zero hop through the
  // net and writes the 480-sample tail to `out`. Returns false on error.
  bool FlushNetTail(float* out);

 private:
  // Streaming linear resampler. `Process` appends an arbitrary number of
  // outputs (floor semantics); fractional phase and the last input sample
  // carry over between calls so the stream stays continuous. Caller-side
  // FIFOs absorb the +/-1 sample jitter per call.
  class LinearResampler {
   public:
    void Reset();
    // `step` = input samples per output sample (e.g. 320/480 for 32k->48k).
    void Process(const float* input,
                 size_t count,
                 double step,
                 std::vector<float>& output);

   private:
    double pos_ = 0.0;  // next output pos in current-input coordinates
    float prev_ = 0.0;  // last sample of the previous call
  };

  // Own dynamics, applied per 48 kHz hop AFTER DeepFilterNet:
  // slow AGC (comfortable level, no pumping) -> light compressor
  // (shout control) -> limiter (anti-clip safety net at -1 dBFS).
  // All state is per-instance, touched only on the APM audio thread under
  // the pipeline mutex. No allocations in ProcessBlock.
  class StudioDynamics {
   public:
    void Reset();
    // In-place enhancement of `count` mono samples at 48 kHz.
    void ProcessBlock(float* samples, int count);
    float agc_gain_db() const { return agc_gain_db_; }
    uint64_t limited_frames() const { return limited_frames_; }
    // Test-only stage selector (STUDIO_STAGE env, read in Initialize):
    // 0 = full chain (default), 1 = expander only, 2 = expander + AGC.
    // Staged tuning support (round 10): validate one stage at a time.
    void set_stage(int stage) { stage_ = stage; }

   private:
    float agc_gain_db_ = 0.0f;   // slow leveler gain (dB)
    float last_gain_lin_ = 1.0f;  // applied gain at the previous hop end
    float gate_att_db_ = 0.0f;    // current expander attenuation (dB, <= 0)
    float last_gate_lin_ = 1.0f;  // applied gate gain at previous hop end
    int gate_hold_left_ = 0;      // hops of hold remaining before engaging
    float comp_env_ = 0.0f;      // compressor peak envelope (linear)
    float lim_env_ = 0.0f;       // limiter peak envelope (linear)
    uint64_t limited_frames_ = 0;
    int stage_ = 0;  // see set_stage (test-only)
  };

  // Pre-net high-pass, 2nd-order Butterworth (RBJ cookbook, Q = 1/sqrt(2),
  // transposed Direct Form II). Cuts sub-bass rumble BEFORE DeepFilterNet so
  // the net spends its suppression budget on the voice band instead of
  // fighting low-frequency noise (tuning round 1, SPEC 2026-09-16: fan
  // collapse dOVRL -1.34). fc is a tuning constexpr in the .cc. State is
  // per-instance, audio thread only, no allocations in ProcessBlock.
  class Hpf {
   public:
    void Reset();
    // In-place filtering of `count` mono samples at 48 kHz.
    void ProcessBlock(float* samples, int count);

   private:
    float s1_ = 0.0f, s2_ = 0.0f;  // TDF-II delay states
  };

  // RAII input-scale adapter. The vendored APM hook delivers float samples
  // in int16 range (±32768 — measured inputPeak ≈ 30917 on real capture),
  // while DeepFilterNet + StudioDynamics operate normalized (±1). Scales
  // down on entry and restores the exact original scale on scope exit (32768
  // is a power of two, so the round-trip is bit-exact), keeping every early
  // return correct. Detection is per call: peaks above 2.0 can only be
  // S16-scale; anything at/below stays untouched, so a normalized feed is
  // never harmed. The destructor also snapshots the post-scale output peak
  // for telemetry (same wire domain as the input peak).
  class AutoScale {
   public:
    AutoScale(AudioEnhancementPipeline* self,
              float* buffer,
              int frames,
              float in_peak);
    ~AutoScale();

   private:
    AudioEnhancementPipeline* self_;
    float* buffer_;
    int frames_;
    float restore_;  // multiply-back factor (1.0f when passthrough)
  };
  // Creates the 48 kHz mono net state on first use. Never latches: a
  // failure bypasses audio until the next call retries.
  bool ensure_state();
  // Runs exactly one 480-sample hop in place: DeepFilterNet, then the own
  // dynamics. Returns false on FFI error (buffer then still holds the
  // unprocessed input).
  bool process_hop(float* samples);
  void clear_fifos();

  struct StateDeleter {
    void operator()(void* state) const;
  };

  static constexpr int kDeepFilterSampleRate = 48000;
  static constexpr int kDeepFilterHopSize = 480;
  // APM post-processing always delivers 10 ms frames, so the device rate is
  // num_frames * 100. Guard against absurd values before sizing anything.
  static constexpr int kMaxFramesPerCall = 4800;
  // After this many consecutive FFI errors, failed() reports true (used by
  // tests/diagnostics); processing still retries on every call.
  static constexpr uint64_t kErrorLatchThreshold = 100;
  // FIFO safety cap (~20 hops); exceeded only on pathological input.
  static constexpr size_t kMaxFifoSamples = 9600;

  std::unique_ptr<void, StateDeleter> state_;
  int num_channels_ = 0;

  LinearResampler up_;    // device rate -> 48 kHz
  LinearResampler down_;  // 48 kHz -> device rate
  StudioDynamics dynamics_;          // own AGC -> compressor -> limiter
  Hpf hpf_;  // pre-net rumble cut (tuning round 1, SPEC 2026-09-16)
  // Round 7 (SPEC 2026-09-16): STUDIO_BYPASS_NET=1 skips the neural net —
  // HPF + dynamics run alone ("Studio clássico"). Test-only escape hatch
  // for the ear to judge how much voice the net itself eats. Default off.
  bool bypass_net_ = false;
  // Round 7b: STUDIO_NET_ONLY=1 runs the neural net ALONE — no HPF, no
  // dynamics. Test-only: lets the ear hear exactly what the net does to
  // the voice. Default off.
  bool net_only_ = false;
  std::vector<float> in_fifo_;      // 48 kHz samples awaiting the net
  std::vector<float> out_fifo_;     // enhanced 48 kHz samples
  std::vector<float> device_fifo_;  // device-rate samples awaiting output
  int last_rate_hz_ = 0;
  // Decaying peak-holds (≈seconds) so a 5 s stats sample still shows speech
  // level. Updated on the APM audio thread; read on the method-channel
  // thread. input==0 means the APM feeds us digital silence; output==0 with
  // input>0 means the pipeline itself (net gate or dynamics) eats the audio.
  float input_peak_ = 0.0f;
  float output_peak_ = 0.0f;

  uint64_t processed_hops_ = 0;
  uint64_t bypassed_frames_ = 0;
  uint64_t underruns_ = 0;
  uint64_t consecutive_errors_ = 0;
  std::string last_error_;
  // Serializes the method-channel thread (enable/disable/reset, which create
  // and destroy the native state) against the APM audio thread (Initialize /
  // Process). Destroying the state while a Process call is in flight is a
  // use-after-free (SIGSEGV on mode switch). Recursive: public methods nest
  // into ensure_state/clear_fifos.
  mutable std::recursive_mutex mutex_;
};

// No-op post-processor used as the "off" state. The vendored
// RTCAudioProcessingImpl::SetCapturePostProcessing unconditionally issues a
// virtual call on the given pointer while capture is running, so passing
// nullptr then is a guaranteed SIGSEGV (see core 2026-09-16: fault in
// SetCapturePostProcessing when disabling the Studio pipeline).
// Swapping in this passthrough keeps the pointer always valid.
class PassthroughAudioProcessor
    : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  void Initialize(int /*sample_rate_hz*/, int /*num_channels*/) override {}
  void Process(int /*num_bands*/,
               int /*num_frames*/,
               int /*buffer_size*/,
               float* /*buffer*/) override {}
  void Reset(int /*new_rate*/) override {}
  void Release() override {}
};

}  // namespace flutter_webrtc_plugin

#endif  // FLUTTER_WEBRTC_AUDIO_ENHANCEMENT_PIPELINE_HXX
