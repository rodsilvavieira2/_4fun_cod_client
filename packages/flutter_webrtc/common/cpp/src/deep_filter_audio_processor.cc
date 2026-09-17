#if defined(_MSC_VER) && !defined(_CRT_SECURE_NO_WARNINGS)
// MSVC 14.44 promotes getenv deprecation (C4996) under /W4; the
// three STUDIO_* reads below are one-shot init reads, no overflow risk.
#define _CRT_SECURE_NO_WARNINGS
#endif
#include "deep_filter_audio_processor.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <string>
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
void fourfun_deepfilter_reset(void* state);
bool fourfun_deepfilter_flush(void* state,
                              float* out_samples,
                              uintptr_t frames,
                              uintptr_t channels,
                              char* error_buffer,
                              uintptr_t error_buffer_len);
}

namespace flutter_webrtc_plugin {
namespace {

// Studio dynamics tuning (all stages run at 48 kHz, after DeepFilterNet).
constexpr float kPipelineRateHz = 48000.0f;
constexpr float kAgcTargetDbfs = -15.0f;  // round 10: -15 meio de -14..-16 (detector RMS)
// Tuning round 2 (SPEC 2026-09-16): makeup cap 20 -> 12 dB. Hypothesis:
// +20 dB of makeup lifts the noise floor during pauses (negative dBAK on
// fan/keyboard). Perna B liked the makeup (dLOUD +0.6), so the guardrail
// decides whether 12 dB keeps intelligibility without the lift.
constexpr float kAgcMaxGainDb = 9.0f;  // round 10: nao amplificar noise floor residual
constexpr float kAgcMinGainDb = -12.0f;
constexpr float kAgcGateDbfs = -45.0f;  // round 5: freeze AGC in pauses (was -60: gain climbed +8 dB in silence)
constexpr double kAgcAttackSec = 0.45;  // round 10: 400-500 ms, sem modulacao rapida
constexpr double kAgcReleaseSec = 2.5;  // gain turns UP slowly (no pumping)
// Tuning round 5 (SPEC 2026-09-16, all-at-once per user): pause gate.
// Symptom: bursts BETWEEN phrases — AGC rode up in pauses, breathing and
// keyboard surfaced, next phrase hit hot. Ducks sub-floor hops by up to
// 12 dB (attack ~2 ms so clicks don't sneak through, release ~150 ms so
// phrase onsets aren't chopped). Same floor as the AGC freeze above.
constexpr float kGateThresholdDbfs = -45.0f;
constexpr float kGateDepthDb = 7.0f;  // round 10: 12 -> 7 (meio de 6-8)
constexpr float kGateRatio = 2.0f;    // round 10: downward expander 2:1
constexpr double kGateAttackSec = 0.002;
constexpr double kGateHoldSec = 0.075;   // round 10: hold 75 ms anti-chatter
constexpr double kGateReleaseSec = 0.200;  // round 10: 150 -> 200 ms
constexpr float kCompThresholdDb = -12.0f;
constexpr float kCompRatio = 3.0f;  // round 10: 4 -> 3
constexpr float kCompKneeDb = 6.0f;
constexpr double kCompAttackSec = 0.006;   // round 10: 5 -> 6 ms
constexpr double kCompReleaseSec = 0.135;  // round 10: 120 -> 135 ms
constexpr float kLimiterCeilingDbfs = -1.0f;
constexpr double kLimiterAttackSec = 0.0005;
constexpr double kLimiterReleaseSec = 0.040;
// Tuning round 1b (SPEC 2026-09-16): fc 80 feriu o guardrail Perna B
// (OVRL 2.69->2.56, SIG 3.48->3.08 — HPF 80 Hz afina voz real). 60 Hz
// preserva fundamental/chest (~100 Hz: -0.5 dB vs -1.2 dB) e ainda corta
// o sub-grave do fan (40 Hz: ~-7 dB).
constexpr float kHpfCutoffHz = 60.0f;

constexpr size_t kErrorBufferLen = 256;

std::string ReadError(char* buffer) {
  return buffer[0] == '\0' ? "DeepFilterNet indisponível" : std::string(buffer);
}

inline float DbToLinear(float db) {
  return std::pow(10.0f, db / 20.0f);
}

inline float OnePoleCoeff(double time_sec) {
  if (!(time_sec > 0.0)) {
    return 1.0f;
  }
  return 1.0f - std::exp(static_cast<float>(-1.0 / (time_sec * kPipelineRateHz)));
}

// Peak of a buffer (diagnostic only). Peak-holds decay per call (~100
// calls/s), so a stats sample seconds later still shows speech level.
inline float BufferPeak(const float* samples, int count) {
  float peak = 0.0f;
  for (int i = 0; i < count; ++i) {
    const float a = std::fabs(samples[i]);
    if (a > peak) peak = a;
  }
  return peak;
}

constexpr float kPeakDecayPerCall = 0.9995f;

// Wire scale of the vendored APM hook (float samples in int16 range).
constexpr float kWirePeak = 32768.0f;
// Detection threshold: normalized feeds never exceed ~1.x; anything above
// 2.0 can only be S16-scale. S16 signals below this are under -84 dBFS,
// i.e. inaudible either way.
constexpr float kS16DetectPeak = 2.0f;

}  // namespace

AudioEnhancementPipeline::AudioEnhancementPipeline() = default;

AudioEnhancementPipeline::~AudioEnhancementPipeline() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  state_.reset();
}

bool AudioEnhancementPipeline::runtime_available() const {
  return fourfun_deepfilter_runtime_available();
}

void AudioEnhancementPipeline::StateDeleter::operator()(void* state) const {
  if (state != nullptr) {
    fourfun_deepfilter_destroy(state);
  }
}

void AudioEnhancementPipeline::LinearResampler::Reset() {
  pos_ = 0.0;
  prev_ = 0.0f;
}

AudioEnhancementPipeline::AutoScale::AutoScale(
    AudioEnhancementPipeline* self,
    float* buffer,
    int frames,
    float in_peak)
    : self_(self), buffer_(buffer), frames_(frames), restore_(1.0f) {
  if (self_ == nullptr || buffer_ == nullptr || frames_ <= 0) {
    return;
  }
  if (in_peak > kS16DetectPeak) {
    restore_ = kWirePeak;
    const float norm = 1.0f / kWirePeak;
    for (int i = 0; i < frames_; ++i) {
      buffer_[i] *= norm;
    }
  }
}

AudioEnhancementPipeline::AutoScale::~AutoScale() {
  if (self_ == nullptr || buffer_ == nullptr || frames_ <= 0) {
    return;
  }
  if (restore_ != 1.0f) {
    for (int i = 0; i < frames_; ++i) {
      buffer_[i] *= restore_;
    }
  }
  // Post-scale peak: same wire domain as the input peak, so the stats pair
  // (inputPeak, outputPeak) directly shows what the pipeline did to level.
  const float out_peak = BufferPeak(buffer_, frames_);
  self_->output_peak_ =
      (std::max)(self_->output_peak_ * kPeakDecayPerCall, out_peak);
}

void AudioEnhancementPipeline::LinearResampler::Process(
    const float* input,
    size_t count,
    double step,
    std::vector<float>& output) {
  if (input == nullptr || count == 0 || !(step > 0.0)) {
    return;
  }
  // Streaming linear interpolation. `pos_` is the next output position in
  // current-input coordinates; positions in [-1, 0) interpolate between the
  // previous call's last sample (`prev_`) and `input[0]`, which keeps the
  // stream continuous across calls.
  double pos = pos_;
  const double limit = static_cast<double>(count) - 1.0;
  while (pos < limit) {
    const long index = static_cast<long>(std::floor(pos));
    const double frac = pos - static_cast<double>(index);
    const float a = (index < 0) ? prev_ : input[index];
    // index + 1 <= count - 1: guaranteed by pos < count - 1.
    const float b = input[index + 1];
    output.push_back(
        static_cast<float>(a + (static_cast<double>(b - a) * frac)));
    pos += step;
  }
  pos_ = pos - static_cast<double>(count);
  prev_ = input[count - 1];
}

void AudioEnhancementPipeline::Hpf::Reset() { s1_ = 0.0f; s2_ = 0.0f; }

void AudioEnhancementPipeline::Hpf::ProcessBlock(float* samples, int count) {
  // RBJ high-pass biquad, Q = 1/sqrt(2), transposed Direct Form II.
  // Coefficients recomputed per call: ~10 flops, no state to keep in sync
  // with the tuning constexpr.
  constexpr float kPi = 3.141592653589793f;
  const float w0 = 2.0f * kPi * kHpfCutoffHz / kPipelineRateHz;
  const float c = std::cos(w0);
  const float s = std::sin(w0);
  const float alpha = s / 1.4142135623730951f;
  const float a0 = 1.0f + alpha;
  const float b0 = (1.0f + c) * 0.5f / a0;
  const float b1 = -(1.0f + c) / a0;
  const float b2 = b0;
  const float a1 = -2.0f * c / a0;
  const float a2 = (1.0f - alpha) / a0;
  for (int i = 0; i < count; ++i) {
    const float x = samples[i];
    const float y = b0 * x + s1_;
    s1_ = b1 * x - a1 * y + s2_;
    s2_ = b2 * x - a2 * y;
    samples[i] = y;
  }
}

void AudioEnhancementPipeline::StudioDynamics::Reset() {
  agc_gain_db_ = 0.0f;
  last_gain_lin_ = 1.0f;
  gate_att_db_ = 0.0f;
  last_gate_lin_ = 1.0f;
  gate_hold_left_ = 0;
  comp_env_ = 0.0f;
  lim_env_ = 0.0f;
  // NOTE: limited_frames_ is a diagnostic counter and survives Reset (like
  // the pipeline-level counters survive APM Reset on a device switch).
}

void AudioEnhancementPipeline::StudioDynamics::ProcessBlock(float* samples,
                                                           int count) {
  if (samples == nullptr || count <= 0) {
    return;
  }
  // Sanitize (the net must never emit these, but a NaN here would latch
  // every envelope and mute the mic until a Reset) and measure hop RMS.
  double sum_sq = 0.0;
  for (int i = 0; i < count; ++i) {
    float s = samples[i];
    if (!std::isfinite(s)) {
      s = 0.0f;
      samples[i] = 0.0f;
    }
    sum_sq += static_cast<double>(s) * static_cast<double>(s);
  }
  const float rms_db = static_cast<float>(
      20.0f * std::log10(std::sqrt(sum_sq / static_cast<double>(count)) +
                         1e-9f));

  // Slow AGC: steer the hop RMS toward the target level. Gated on silence
  // so pauses don't ramp the gain into the noise floor, and asymmetric
  // (down fast, up slow) so sudden shouts are tamed without "breathing".
  // STUDIO_STAGE=1 freezes the AGC at unity (expander-only tuning stage).
  const bool run_agc = (stage_ == 0 || stage_ == 2);
  if (run_agc && rms_db > kAgcGateDbfs) {
    const float desired = (std::min)(
        kAgcMaxGainDb, (std::max)(kAgcMinGainDb, kAgcTargetDbfs - rms_db));
    const double tau =
        (desired < agc_gain_db_) ? kAgcAttackSec : kAgcReleaseSec;
    const float coeff =
        1.0f - std::exp(static_cast<float>(
                   -static_cast<double>(count) / kPipelineRateHz / tau));
    agc_gain_db_ += (desired - agc_gain_db_) * coeff;
  }
  const float start_gain = last_gain_lin_;
  const float end_gain = run_agc ? DbToLinear(agc_gain_db_) : 1.0f;

  // Downward expander with hold (round 10): below the floor, attenuation
  // grows with the distance below threshold (2:1 slope, capped at depth)
  // instead of slamming to full depth; hold rides through inter-phoneme
  // dips so the gate can't chatter between fonemas.
  float gate_want = 0.0f;
  if (rms_db < kGateThresholdDbfs) {
    if (gate_hold_left_ > 0) {
      gate_hold_left_ -= count;
    } else {
      gate_want =
          -(kGateThresholdDbfs - rms_db) * (1.0f - 1.0f / kGateRatio);
      gate_want = (std::max)(gate_want, -kGateDepthDb);
    }
  } else {
    gate_hold_left_ =
        static_cast<int>(kGateHoldSec * kPipelineRateHz);
  }
  const double gate_tau =
      (gate_want < gate_att_db_) ? kGateAttackSec : kGateReleaseSec;
  const float gate_coeff =
      1.0f - std::exp(static_cast<float>(
                 -static_cast<double>(count) / kPipelineRateHz / gate_tau));
  gate_att_db_ += (gate_want - gate_att_db_) * gate_coeff;
  const float gate_start = last_gate_lin_;
  const float gate_end = DbToLinear(gate_att_db_);

  const float comp_atk = OnePoleCoeff(kCompAttackSec);
  const float comp_rel = OnePoleCoeff(kCompReleaseSec);
  const float lim_atk = OnePoleCoeff(kLimiterAttackSec);
  const float lim_rel = OnePoleCoeff(kLimiterReleaseSec);
  const float ceiling = DbToLinear(kLimiterCeilingDbfs);
  // STUDIO_STAGE=1/2 skip compressor+limiter (expander / expander+AGC only).
  const bool run_comp_lim = (stage_ == 0);

  for (int i = 0; i < count; ++i) {
    // Zipper-free AGC ramp across the hop.
    const float t =
        (count == 1) ? 1.0f : static_cast<float>(i) / (count - 1.0f);
    float y = samples[i] * (start_gain + (end_gain - start_gain) * t) *
              (gate_start + (gate_end - gate_start) * t);

    if (run_comp_lim) {
    // Light soft-knee compressor: shouts stay audible, not painful.
    const float comp_abs = std::fabs(y) + 1e-12f;
    comp_env_ += (comp_abs - comp_env_) *
                 ((comp_abs > comp_env_) ? comp_atk : comp_rel);
    const float env_db = 20.0f * std::log10(comp_env_);
    float gr_db = 0.0f;
    const double over = 2.0 * (env_db - kCompThresholdDb);
    if (over > kCompKneeDb) {
      gr_db = (env_db - kCompThresholdDb) * (1.0f - 1.0f / kCompRatio);
    } else if (over > -kCompKneeDb) {
      const float knee_pos = (env_db - kCompThresholdDb) + kCompKneeDb * 0.5f;
      gr_db = (1.0f - 1.0f / kCompRatio) * knee_pos * knee_pos /
              (2.0f * kCompKneeDb);
    }
    y *= DbToLinear(-gr_db);

    // Limiter: safety net at -1 dBFS. Rarely active by design — if this
    // counter climbs steadily, the stages above are set too hot.
    const float lim_abs = std::fabs(y);
    lim_env_ +=
        (lim_abs - lim_env_) * ((lim_abs > lim_env_) ? lim_atk : lim_rel);
    if (lim_env_ > ceiling && lim_env_ > 1e-9f) {
      y *= ceiling / lim_env_;
      ++limited_frames_;
    }
    }  // run_comp_lim

    // Hard clamp: must never ship > 0 dBFS (clip/click protection).
    samples[i] = (std::min)(1.0f, (std::max)(-1.0f, y));
  }
  last_gain_lin_ = end_gain;
  last_gate_lin_ = gate_end;
}

void AudioEnhancementPipeline::Initialize(int sample_rate_hz,
                                          int num_channels) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  if (num_channels > 0) {
    num_channels_ = num_channels;
  }
  // Round 7: env-gated net bypass (default off). Read once per Initialize
  // (device/rate switch), not per hop.
  if (const char* env = std::getenv("STUDIO_BYPASS_NET")) {
    bypass_net_ = (env[0] == '1');
  } else {
    bypass_net_ = false;
  }
  // Round 7b: net-only mode (default off).
  if (const char* env = std::getenv("STUDIO_NET_ONLY")) {
    net_only_ = (env[0] == '1');
  } else {
    net_only_ = false;
  }
  // Round 10: staged tuning selector (default 0 = full chain).
  if (const char* env = std::getenv("STUDIO_STAGE")) {
    int stage = std::atoi(env);
    dynamics_.set_stage((stage >= 1 && stage <= 2) ? stage : 0);
  } else {
    dynamics_.set_stage(0);
  }
  // Eager create so a broken runtime surfaces in last_error() before the
  // first Process call. The net itself always runs at 48 kHz mono: the
  // vendored adapter only hands us channel 0, and any device rate is
  // resampled in Process.
  (void)sample_rate_hz;
  ensure_state();
}

void AudioEnhancementPipeline::Process(int num_bands,
                                       int num_frames,
                                       int buffer_size,
                                       float* buffer) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  (void)num_bands;  // Split-band count; carries no layout info (see below).
  if (buffer == nullptr || num_frames <= 0 || buffer_size < num_frames ||
      num_frames > kMaxFramesPerCall) {
    return;
  }
  // Level telemetry first: input==0 over speech means the APM feeds us
  // digital silence (capture-side problem); output==0 with input>0 means
  // the pipeline itself eats the audio (net gate or dynamics problem).
  const float in_peak = BufferPeak(buffer, num_frames);
  input_peak_ = (std::max)(input_peak_ * kPeakDecayPerCall, in_peak);
  // Scale adapter: normalizes S16-scale wire audio to ±1 around the DF +
  // dynamics core and restores the exact wire scale (plus output-peak
  // telemetry) on scope exit. Covers every return below.
  AutoScale wire_scale(this, buffer, num_frames, in_peak);
  // Contract of the vendored CustomProcessingAdapter
  // (webrtc-sdk/libwebrtc rtc_audio_processing_impl.cc): `buffer` holds
  // channel 0 as `num_frames` fullband samples of one 10 ms frame, and
  // buffer_size == 160 * num_bands == num_frames. So the device rate is
  // num_frames * 100 and there is exactly one channel to process.
  const int rate_hz = num_frames * 100;
  if (rate_hz != last_rate_hz_) {
    // Defensive: the adapter calls Reset(rate) on rate changes, but never
    // trust resampler/FIFO continuity across a rate switch.
    clear_fifos();
    last_rate_hz_ = rate_hz;
  }
  if (!ensure_state()) {
    bypassed_frames_ += static_cast<uint64_t>(num_frames);
    return;
  }

  if (rate_hz == kDeepFilterSampleRate &&
      num_frames == kDeepFilterHopSize) {
    // Fast path: the 10 ms device frame IS one net hop. Zero added latency.
    if (process_hop(buffer)) {
      return;
    }
    bypassed_frames_ += static_cast<uint64_t>(num_frames);
    return;
  }

  // Slow path: resample to 48 kHz, enhance whole hops, resample back.
  // FIFOs absorb the +/-1 sample jitter of block resampling; steady-state
  // latency stays under one device frame.
  up_.Process(buffer, static_cast<size_t>(num_frames),
              static_cast<double>(rate_hz) /
                  static_cast<double>(kDeepFilterSampleRate),
              in_fifo_);
  if (in_fifo_.size() > kMaxFifoSamples ||
      out_fifo_.size() > kMaxFifoSamples ||
      device_fifo_.size() > kMaxFifoSamples) {
    clear_fifos();
    ++underruns_;
  }
  std::vector<float> hop(kDeepFilterHopSize);
  while (in_fifo_.size() >= static_cast<size_t>(kDeepFilterHopSize)) {
    std::copy_n(in_fifo_.data(), kDeepFilterHopSize, hop.data());
    in_fifo_.erase(in_fifo_.begin(),
                   in_fifo_.begin() + kDeepFilterHopSize);
    // NOTE: process_hop runs in place but leaves `hop` untouched on FFI
    // failure (the Rust side only writes the output buffer on success), so
    // re-inserting `hop` below passes the unprocessed input through and
    // keeps the stream cadence instead of dropping 10 ms (a dropout clicks
    // louder than noise).
    if (!process_hop(hop.data())) {
      bypassed_frames_ += static_cast<uint64_t>(kDeepFilterHopSize);
    }
    out_fifo_.insert(out_fifo_.end(), hop.begin(), hop.end());
  }
  if (!out_fifo_.empty()) {
    down_.Process(out_fifo_.data(), out_fifo_.size(),
                  static_cast<double>(kDeepFilterSampleRate) /
                      static_cast<double>(rate_hz),
                  device_fifo_);
    out_fifo_.clear();
  }
  if (device_fifo_.size() >= static_cast<size_t>(num_frames)) {
    std::copy_n(device_fifo_.data(), num_frames, buffer);
    device_fifo_.erase(device_fifo_.begin(),
                       device_fifo_.begin() + num_frames);
  } else {
    // Startup only: not enough enhanced audio yet. Emit what we have and
    // hold the last sample for the remainder (no clicks, no uninitialized
    // memory on the wire).
    const float pad = device_fifo_.empty() ? 0.0f : device_fifo_.back();
    std::copy(device_fifo_.begin(), device_fifo_.end(), buffer);
    std::fill(buffer + device_fifo_.size(), buffer + num_frames, pad);
    bypassed_frames_ +=
        static_cast<uint64_t>(num_frames) - device_fifo_.size();
    ++underruns_;
    device_fifo_.clear();
  }
}

void AudioEnhancementPipeline::Reset(int new_rate) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  (void)new_rate;
  // The net state itself is rate-independent (always 48 kHz mono); only
  // framing state must go. Never touches consecutive_errors_/last_error_ so
  // diagnostics survive a device switch.
  clear_fifos();
  if (state_ != nullptr) {
    // DPDFNet carries recurrent + STFT state across hops: a device switch
    // must not leak the old room into the new stream.
    fourfun_deepfilter_reset(state_.get());
  }
}

void AudioEnhancementPipeline::Release() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  clear_fifos();
  state_.reset();
}

bool AudioEnhancementPipeline::FlushNetTail(float* out) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  if (out == nullptr || state_ == nullptr) {
    return false;
  }
  char error[kErrorBufferLen] = {};
  const bool ok = fourfun_deepfilter_flush(
      state_.get(), out, static_cast<uintptr_t>(kDeepFilterHopSize),
      static_cast<uintptr_t>(1), error, kErrorBufferLen);
  if (!ok) {
    ++consecutive_errors_;
    last_error_ = ReadError(error);
    return false;
  }
  ++processed_hops_;
  return true;
}

bool AudioEnhancementPipeline::ensure_state() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  if (state_ != nullptr) {
    return true;
  }
  char error[kErrorBufferLen] = {};
  void* state = fourfun_deepfilter_create(
      static_cast<uint32_t>(kDeepFilterSampleRate),
      static_cast<uintptr_t>(1), error, kErrorBufferLen);
  if (state == nullptr) {
    ++consecutive_errors_;
    last_error_ = ReadError(error);
    return false;
  }
  state_.reset(state);
  // NOTE: num_channels_ keeps the device channel count reported by
  // Initialize (diagnostic only) — the net always runs mono on channel 0,
  // the only channel the vendored adapter hands us.
  last_error_.clear();
  return true;
}

bool AudioEnhancementPipeline::process_hop(float* samples) {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  if (net_only_) {
    // Round 7b test: neural net ALONE — straight in, straight out.
    char error[kErrorBufferLen] = {};
    const bool ok = fourfun_deepfilter_process(
        state_.get(), samples, static_cast<uintptr_t>(kDeepFilterHopSize),
        static_cast<uintptr_t>(1), error, kErrorBufferLen);
    if (!ok) {
      ++consecutive_errors_;
      last_error_ = ReadError(error);
      return false;
    }
    consecutive_errors_ = 0;
    ++processed_hops_;
    return true;
  }
  // Tuning round 1: rumble cut BEFORE the net (see Hpf in the header).
  hpf_.ProcessBlock(samples, kDeepFilterHopSize);
  if (bypass_net_) {
    // Round 7 test: no net — dynamics (gate/AGC/comp/limiter) run on the
    // HPF'd hop alone. Still counts as processed (not a bypass/failure).
    dynamics_.ProcessBlock(samples, kDeepFilterHopSize);
    ++processed_hops_;
    return true;
  }
  char error[kErrorBufferLen] = {};
  const bool ok = fourfun_deepfilter_process(
      state_.get(), samples, static_cast<uintptr_t>(kDeepFilterHopSize),
      static_cast<uintptr_t>(1), error, kErrorBufferLen);
  if (!ok) {
    ++consecutive_errors_;
    last_error_ = ReadError(error);
    return false;
  }
  // Net succeeded: run the own dynamics on the denoised hop before it goes
  // back to the device rate and the encoder.
  dynamics_.ProcessBlock(samples, kDeepFilterHopSize);
  consecutive_errors_ = 0;
  ++processed_hops_;
  return true;
}

void AudioEnhancementPipeline::clear_fifos() {
  std::lock_guard<std::recursive_mutex> lock(mutex_);
  in_fifo_.clear();
  out_fifo_.clear();
  device_fifo_.clear();
  up_.Reset();
  down_.Reset();
  // A rate/device switch invalidates envelope continuity; restart the
  // dynamics at unity gain so the first hop after the switch can't thump.
  dynamics_.Reset();
  hpf_.Reset();
}

}  // namespace flutter_webrtc_plugin
