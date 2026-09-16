//! DPDFNet2 48 kHz streaming denoiser (ONNX Runtime backend).
//!
//! Bit-exact port of sherpa-onnx `OnlineSpeechDenoiserStftImpl` +
//! `OnlineSpeechDenoiserDpdfNetImpl` (Apache-2.0, Xiaomi/Ceva):
//! vorbis-windowed WOLA-STFT (n_fft 960 / hop 480), single-frame ONNX
//! inference with carried recurrent state, overlap-add with synthesis
//! window. First hop emits silence (1-hop algorithmic latency, same as
//! sherpa); steady state is 480-in/480-out.

use std::f32::consts::PI as PI_F32;
use std::sync::OnceLock;

pub const SAMPLE_RATE: u32 = 48_000;
pub const HOP: usize = 480;
pub const N_FFT: usize = 960;
pub const WIN: usize = 960;
pub const BINS: usize = 481;
pub const STATE_SIZE: usize = 56436;
pub const ERB_NORM_SIZE: usize = 481;
pub const SPEC_NORM_SIZE: usize = 96;

const MODEL_BYTES: &[u8] = include_bytes!(concat!(env!("FOURFUN_DPDFNET_PATH")));
const ERB_NORM_BYTES: &[u8] = include_bytes!("../model/dpdfnet_erb_norm.f32");
const SPEC_NORM_BYTES: &[u8] = include_bytes!("../model/dpdfnet_spec_norm.f32");

fn ensure_ort() {
    static ONCE: OnceLock<()> = OnceLock::new();
    ONCE.get_or_init(|| {
        assert!(ort::init().with_name("fourfun-dpdfnet").commit());
    });
}

fn parse_f32_le(bytes: &[u8], count: usize) -> Vec<f32> {
    assert_eq!(bytes.len(), count * 4, "norm table size mismatch");
    bytes
        .chunks_exact(4)
        .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
        .collect()
}

/// Exact sherpa `MakeVorbisWindow` (math.cc):
/// w[i] = sin(pi/2 * sin(pi/2 * (i+0.5)/half)^2), half = N/2.
fn vorbis_window(n: usize) -> Vec<f32> {
    let half = n as f32 / 2.0;
    (0..n)
        .map(|i| {
            let s = (0.5 * PI_F32 * (i as f32 + 0.5) / half).sin();
            (0.5 * PI_F32 * s * s).sin()
        })
        .collect()
}

/// Naive double-precision DFT pair, mirroring sherpa `StreamingDft`
/// (forward: imag -= ; inverse: 1/N scaling, DC/Nyquist unfolded).
struct StreamingDft {
    n_fft: usize,
    num_bins: usize,
    cos_f: Vec<f64>,
    sin_f: Vec<f64>,
    cos_i: Vec<f64>,
    sin_i: Vec<f64>,
}

impl StreamingDft {
    fn new(n_fft: usize) -> Self {
        let num_bins = n_fft / 2 + 1;
        let mut cos_f = vec![0.0f64; num_bins * n_fft];
        let mut sin_f = vec![0.0f64; num_bins * n_fft];
        let mut cos_i = vec![0.0f64; n_fft * num_bins];
        let mut sin_i = vec![0.0f64; n_fft * num_bins];
        for k in 0..num_bins {
            for n in 0..n_fft {
                let angle = 2.0 * std::f64::consts::PI * k as f64 * n as f64 / n_fft as f64;
                let (s, c) = angle.sin_cos();
                cos_f[k * n_fft + n] = c;
                sin_f[k * n_fft + n] = s;
                cos_i[n * num_bins + k] = c;
                sin_i[n * num_bins + k] = s;
            }
        }
        Self {
            n_fft,
            num_bins,
            cos_f,
            sin_f,
            cos_i,
            sin_i,
        }
    }

    fn forward(&self, input: &[f32], output: &mut [f32]) {
        debug_assert_eq!(input.len(), self.n_fft);
        debug_assert_eq!(output.len(), 2 * self.num_bins);
        for k in 0..self.num_bins {
            let mut real = 0.0f64;
            let mut imag = 0.0f64;
            let cos = &self.cos_f[k * self.n_fft..(k + 1) * self.n_fft];
            let sin = &self.sin_f[k * self.n_fft..(k + 1) * self.n_fft];
            for n in 0..self.n_fft {
                let v = input[n] as f64;
                real += v * cos[n];
                imag -= v * sin[n];
            }
            output[2 * k] = real as f32;
            output[2 * k + 1] = imag as f32;
        }
    }

    fn inverse(&self, input: &[f32], output: &mut [f32]) {
        debug_assert_eq!(input.len(), 2 * self.num_bins);
        debug_assert_eq!(output.len(), self.n_fft);
        for n in 0..self.n_fft {
            let mut sum = input[0] as f64;
            if self.n_fft % 2 == 0 {
                let nyq = input[2 * (self.num_bins - 1)] as f64;
                sum += if n & 1 == 1 { -nyq } else { nyq };
            }
            let cos = &self.cos_i[n * self.num_bins..(n + 1) * self.num_bins];
            let sin = &self.sin_i[n * self.num_bins..(n + 1) * self.num_bins];
            for k in 1..self.num_bins - 1 {
                let real = input[2 * k] as f64;
                let imag = input[2 * k + 1] as f64;
                sum += 2.0 * (real * cos[k] - imag * sin[k]);
            }
            output[n] = (sum / self.n_fft as f64) as f32;
        }
    }
}

fn init_state() -> Vec<f32> {
    let mut state = vec![0.0f32; STATE_SIZE];
    let erb = parse_f32_le(ERB_NORM_BYTES, ERB_NORM_SIZE);
    let spec = parse_f32_le(SPEC_NORM_BYTES, SPEC_NORM_SIZE);
    state[..ERB_NORM_SIZE].copy_from_slice(&erb);
    state[ERB_NORM_SIZE..ERB_NORM_SIZE + SPEC_NORM_SIZE].copy_from_slice(&spec);
    state
}

pub struct DpdfnetMono {
    session: ort::session::Session,
    state: Vec<f32>,
    analysis: Vec<f32>,
    overlap: Vec<f32>,
    window: Vec<f32>,
    dft: StreamingDft,
    fft_in: Vec<f32>,
    spec: Vec<f32>,
    enhanced: Vec<f32>,
    ifft_out: Vec<f32>,
    started: bool,
}

impl DpdfnetMono {
    pub fn new() -> Result<Self, String> {
        ensure_ort();
        let session = ort::session::Session::builder()
            .map_err(|e| format!("ORT session builder failed: {e}"))?
            .commit_from_memory(MODEL_BYTES)
            .map_err(|e| format!("DPDFNet model load failed: {e}"))?;
        Ok(Self {
            session,
            state: init_state(),
            analysis: vec![0.0; WIN],
            overlap: vec![0.0; WIN],
            window: vorbis_window(WIN),
            dft: StreamingDft::new(N_FFT),
            fft_in: vec![0.0; WIN],
            spec: vec![0.0; 2 * BINS],
            enhanced: vec![0.0; 2 * BINS],
            ifft_out: vec![0.0; WIN],
            started: false,
        })
    }

    pub fn reset(&mut self) {
        self.analysis.fill(0.0);
        self.overlap.fill(0.0);
        self.state = init_state();
        self.started = false;
    }

    /// One 10 ms hop in place (sherpa parity: first hop emits silence).
    pub fn process_hop(&mut self, io: &mut [f32]) -> Result<(), String> {
        if io.len() != HOP {
            return Err(format!("DPDFNet expected {HOP} frames, got {}", io.len()));
        }
        // Shift analysis buffer, append hop, apply analysis window.
        self.analysis.copy_within(HOP.., 0);
        self.analysis[WIN - HOP..].copy_from_slice(io);
        for i in 0..WIN {
            self.fft_in[i] = self.analysis[i] * self.window[i];
        }
        self.dft.forward(&self.fft_in, &mut self.spec);

        let spec_tensor = ort::value::Tensor::from_array(([1usize, 1, BINS, 2], self.spec.clone()))
            .map_err(|e| format!("spec tensor failed: {e}"))?;
        let state_tensor = ort::value::Tensor::from_array(([STATE_SIZE], self.state.clone()))
            .map_err(|e| format!("state tensor failed: {e}"))?;

        let outputs = self
            .session
            .run(ort::inputs!["spec" => spec_tensor, "state_in" => state_tensor])
            .map_err(|e| format!("DPDFNet inference failed: {e}"))?;

        let (enh_shape, enh_data) = outputs["spec_e"]
            .try_extract_tensor::<f32>()
            .map_err(|e| format!("spec_e extract failed: {e}"))?;
        if **enh_shape != [1, 1, BINS as i64, 2] {
            return Err(format!("unexpected spec_e shape: {enh_shape:?}"));
        }
        self.enhanced.copy_from_slice(enh_data);

        let (_, state_data) = outputs["state_out"]
            .try_extract_tensor::<f32>()
            .map_err(|e| format!("state_out extract failed: {e}"))?;
        if state_data.len() != STATE_SIZE {
            return Err(format!("unexpected state size: {}", state_data.len()));
        }
        self.state.copy_from_slice(state_data);

        self.dft.inverse(&self.enhanced, &mut self.ifft_out);

        self.overlap.copy_within(HOP.., 0);
        self.overlap[WIN - HOP..].fill(0.0);
        for i in 0..WIN {
            self.overlap[i] += self.ifft_out[i] * self.window[i];
        }

        // Sherpa parity: the first hop computes H_0 (seeding overlap/state)
        // but emits nothing — output stream is [H_1..H_N], i.e. input delayed
        // by exactly one hop. In fixed-size realtime callbacks the skipped
        // hop surfaces as 10 ms of leading silence (inaudible at mic-open).
        if !self.started {
            self.started = true;
            io.fill(0.0);
            return Ok(());
        }
        io.copy_from_slice(&self.overlap[..HOP]);
        Ok(())
    }

    /// End-of-stream drain (sherpa `Flush` parity for hop-multiple streams):
    /// runs one zero hop through the net and emits its head, completing the
    /// [H_1..H_N] stream. Harness-only — realtime has no consumer at teardown.
    pub fn flush_tail(&mut self, out: &mut [f32]) -> Result<(), String> {
        if out.len() != HOP {
            return Err(format!("DPDFNet flush expected {HOP} frames"));
        }
        let mut zero = [0.0f32; HOP];
        // Bypass the started_ skip: the stream already started.
        let was = self.started;
        self.started = true;
        self.process_hop(&mut zero)?;
        self.started = was;
        out.copy_from_slice(&zero);
        Ok(())
    }
}
