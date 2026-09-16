// Harness file-in/file-out da cadeia Studio (W1).
// Uso: harness_studio in_48k_s16_mono.wav out.wav
// Contrato: 48 kHz mono S16, tamanho multiplo de 480 amostras.
// Alimenta hops de 10 ms em escala S16 (== fio do APM) no
// AudioEnhancementPipeline real (DF + dynamics) e grava a saida.
// Stats + picos vao para stderr.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "deep_filter_audio_processor.h"

namespace {
#pragma pack(push, 1)
struct WavHead {
  char riff[4];
  uint32_t size;
  char wave[4];
  char fmt[4];
  uint32_t fmt_len;
  uint16_t audio_fmt;
  uint16_t channels;
  uint32_t sample_rate;
  uint32_t byte_rate;
  uint16_t block_align;
  uint16_t bits;
  char data[4];
  uint32_t data_len;
};
#pragma pack(pop)

bool read_wav(const char* path, std::vector<float>& s16, uint32_t& rate) {
  FILE* f = std::fopen(path, "rb");
  if (!f) return false;
  WavHead h{};
  if (std::fread(&h, sizeof(h), 1, f) != 1) { std::fclose(f); return false; }
  if (std::memcmp(h.riff, "RIFF", 4) || std::memcmp(h.wave, "WAVE", 4) ||
      h.audio_fmt != 1 || h.channels != 1 || h.bits != 16 ||
      h.sample_rate != 48000) {
    std::fclose(f);
    return false;
  }
  size_t n = h.data_len / 2;
  std::vector<int16_t> pcm(n);
  if (std::fread(pcm.data(), 2, n, f) != n) { std::fclose(f); return false; }
  std::fclose(f);
  s16.resize(n);
  for (size_t i = 0; i < n; ++i) s16[i] = static_cast<float>(pcm[i]);
  rate = h.sample_rate;
  return true;
}

bool write_wav(const char* path, const std::vector<float>& s16) {
  FILE* f = std::fopen(path, "wb");
  if (!f) return false;
  WavHead h{};
  std::memcpy(h.riff, "RIFF", 4);
  std::memcpy(h.wave, "WAVE", 4);
  std::memcpy(h.fmt, "fmt ", 4);
  std::memcpy(h.data, "data", 4);
  h.fmt_len = 16;
  h.audio_fmt = 1;
  h.channels = 1;
  h.sample_rate = 48000;
  h.bits = 16;
  h.block_align = 2;
  h.byte_rate = 48000 * 2;
  h.data_len = static_cast<uint32_t>(s16.size() * 2);
  h.size = 36 + h.data_len;
  if (std::fwrite(&h, sizeof(h), 1, f) != 1) { std::fclose(f); return false; }
  for (float v : s16) {
    if (v > 32767.0f) v = 32767.0f;
    if (v < -32768.0f) v = -32768.0f;
    int16_t s = static_cast<int16_t>(v);
    if (std::fwrite(&s, 2, 1, f) != 1) { std::fclose(f); return false; }
  }
  std::fclose(f);
  return true;
}
}  // namespace

int main(int argc, char** argv) {
  using flutter_webrtc_plugin::AudioEnhancementPipeline;
  if (argc != 3) {
    std::fprintf(stderr, "uso: %s in.wav out.wav\n", argv[0]);
    return 2;
  }
  std::vector<float> in;
  uint32_t rate = 0;
  if (!read_wav(argv[1], in, rate)) {
    std::fprintf(stderr, "falha lendo %s (esperado 48k mono S16)\n", argv[1]);
    return 1;
  }
  if (in.size() % 480 != 0) {
    std::fprintf(stderr, "tamanho %zu nao multiplo de 480\n", in.size());
    return 1;
  }
  AudioEnhancementPipeline pipe;
  if (!pipe.runtime_available()) {
    std::fprintf(stderr, "bridge DF indisponivel: %s\n",
                 pipe.last_error().c_str());
    return 1;
  }
  pipe.Initialize(48000, 1);
  std::vector<float> hop(480);
  for (size_t i = 0; i < in.size(); i += 480) {
    std::memcpy(hop.data(), in.data() + i, sizeof(float) * 480);
    pipe.Process(1, 480, 480, hop.data());
    std::memcpy(in.data() + i, hop.data(), sizeof(float) * 480);
  }
  const bool net_only = std::getenv("STUDIO_NET_ONLY") != nullptr &&
                        std::getenv("STUDIO_NET_ONLY")[0] == '1';
  if (net_only) {
    // Sherpa Flush parity: drain the tail hop, then drop the leading
    // skipped hop so the file is [H_1..H_N] exactly like the Python ref.
    std::vector<float> tail(480, 0.0f);
    if (!pipe.FlushNetTail(tail.data())) {
      std::fprintf(stderr, "flush falhou: %s\n", pipe.last_error().c_str());
      return 1;
    }
    in.insert(in.end(), tail.begin(), tail.end());
    in.erase(in.begin(), in.begin() + 480);
  }
  auto st = pipe.stats();
  std::fprintf(stderr,
               "hops=%llu bypass=%llu underruns=%llu in_peak=%.0f out_peak=%.0f "
               "agc=%.1fdB limited=%llu err='%s'\n",
               (unsigned long long)st.processed_hops,
               (unsigned long long)st.bypassed_frames,
               (unsigned long long)st.underruns, st.input_peak, st.output_peak,
               st.agc_gain_db, (unsigned long long)st.limited_frames,
               pipe.failed() ? pipe.last_error().c_str() : "");
  if (pipe.failed()) return 1;
  if (!write_wav(argv[2], in)) {
    std::fprintf(stderr, "falha escrevendo %s\n", argv[2]);
    return 1;
  }
  return 0;
}
