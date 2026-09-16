mod dpdfnet;

use dpdfnet::{DpdfnetMono, HOP as DPDFNET_HOP, SAMPLE_RATE as DPDFNET_SAMPLE_RATE};
use std::ffi::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

pub struct DeepFilterState {
    monos: Vec<DpdfnetMono>,
    channels: usize,
    hop_size: usize,
    scratch: Vec<f32>,
}

impl DeepFilterState {
    fn new(sample_rate_hz: u32, channels: usize) -> Result<Self, String> {
        if sample_rate_hz != DPDFNET_SAMPLE_RATE {
            return Err("DPDFNet requires 48 kHz capture".to_string());
        }
        if channels == 0 {
            return Err("DPDFNet requires at least one channel".to_string());
        }

        // Round 10 (SPEC 2026-09-16): DeepFilterNet3 out, DPDFNet2 48 kHz
        // in. The DF `atten_lim` knob is gone with the old net — suppression
        // depth now lives in the C++ dynamics (expander/AGC/compressor).
        let mut monos = Vec::with_capacity(channels);
        for _ in 0..channels {
            monos.push(DpdfnetMono::new()?);
        }
        Ok(Self {
            monos,
            channels,
            hop_size: DPDFNET_HOP,
            scratch: vec![0.0; DPDFNET_HOP],
        })
    }

    fn process(
        &mut self,
        samples: &mut [f32],
        frames: usize,
        channels: usize,
    ) -> Result<(), String> {
        if channels != self.channels {
            return Err("DPDFNet channel count changed".to_string());
        }
        // The C++ caller guarantees exactly `hop_size` frames (it resamples
        // and frames the APM stream); anything else is a contract violation
        // and must surface as an error so the caller can count the bypass
        // instead of silently shipping unprocessed audio as "IA".
        if frames != self.hop_size {
            return Err(format!(
                "DPDFNet expected {} frames, got {frames}",
                self.hop_size
            ));
        }
        if samples.len() < frames * channels {
            return Err("DPDFNet received a short sample buffer".to_string());
        }

        for (channel, mono) in self.monos.iter_mut().enumerate() {
            for frame in 0..frames {
                self.scratch[frame] = samples[(frame * channels) + channel];
            }
            mono.process_hop(&mut self.scratch)?;
            for frame in 0..frames {
                samples[(frame * channels) + channel] = self.scratch[frame];
            }
        }
        Ok(())
    }

    fn flush(&mut self, samples: &mut [f32], frames: usize, channels: usize) -> Result<(), String> {
        if channels != self.channels {
            return Err("DPDFNet channel count changed".to_string());
        }
        if frames != self.hop_size {
            return Err(format!(
                "DPDFNet expected {} frames, got {frames}",
                self.hop_size
            ));
        }
        if samples.len() < frames * channels {
            return Err("DPDFNet received a short sample buffer".to_string());
        }

        for (channel, mono) in self.monos.iter_mut().enumerate() {
            mono.flush_tail(&mut self.scratch)?;
            for frame in 0..frames {
                samples[(frame * channels) + channel] = self.scratch[frame];
            }
        }
        Ok(())
    }
}

fn write_error(buffer: *mut c_char, buffer_len: usize, message: &str) {
    if buffer.is_null() || buffer_len == 0 {
        return;
    }
    let bytes = message.as_bytes();
    let copy_len = bytes.len().min(buffer_len.saturating_sub(1));
    unsafe {
        ptr::copy_nonoverlapping(bytes.as_ptr(), buffer.cast::<u8>(), copy_len);
        *buffer.add(copy_len) = 0;
    }
}

#[no_mangle]
pub extern "C" fn fourfun_deepfilter_runtime_available() -> bool {
    true
}

#[no_mangle]
pub extern "C" fn fourfun_deepfilter_create(
    sample_rate_hz: u32,
    channels: usize,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> *mut DeepFilterState {
    match catch_unwind(AssertUnwindSafe(|| {
        DeepFilterState::new(sample_rate_hz, channels)
    })) {
        Ok(Ok(state)) => Box::into_raw(Box::new(state)),
        Ok(Err(error)) => {
            write_error(error_buffer, error_buffer_len, &error);
            ptr::null_mut()
        }
        Err(_) => {
            write_error(
                error_buffer,
                error_buffer_len,
                "DeepFilterNet panicked during initialization",
            );
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn fourfun_deepfilter_process(
    state: *mut DeepFilterState,
    samples: *mut f32,
    frames: usize,
    channels: usize,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    if state.is_null() || samples.is_null() {
        write_error(
            error_buffer,
            error_buffer_len,
            "DeepFilterNet received a null pointer",
        );
        return false;
    }

    match catch_unwind(AssertUnwindSafe(|| {
        let sample_len = frames.saturating_mul(channels);
        let samples = unsafe { slice::from_raw_parts_mut(samples, sample_len) };
        let state = unsafe { &mut *state };
        state.process(samples, frames, channels)
    })) {
        Ok(Ok(())) => true,
        Ok(Err(error)) => {
            write_error(error_buffer, error_buffer_len, &error);
            false
        }
        Err(_) => {
            write_error(
                error_buffer,
                error_buffer_len,
                "DeepFilterNet panicked during processing",
            );
            false
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn fourfun_deepfilter_reset(state: *mut DeepFilterState) {
    if state.is_null() {
        return;
    }
    let holder = unsafe { &mut *state };
    for mono in holder.monos.iter_mut() {
        mono.reset();
    }
}

// End-of-stream drain: emits the net's tail hop (sherpa Flush parity).
// Harness-only; realtime has no consumer at teardown.
#[no_mangle]
pub extern "C" fn fourfun_deepfilter_flush(
    state: *mut DeepFilterState,
    samples: *mut f32,
    frames: usize,
    channels: usize,
    error_buffer: *mut c_char,
    error_buffer_len: usize,
) -> bool {
    if state.is_null() || samples.is_null() {
        write_error(
            error_buffer,
            error_buffer_len,
            "DeepFilterNet received a null pointer",
        );
        return false;
    }

    match catch_unwind(AssertUnwindSafe(|| {
        let sample_len = frames.saturating_mul(channels);
        let samples = unsafe { slice::from_raw_parts_mut(samples, sample_len) };
        let state = unsafe { &mut *state };
        state.flush(samples, frames, channels)
    })) {
        Ok(Ok(())) => true,
        Ok(Err(error)) => {
            write_error(error_buffer, error_buffer_len, &error);
            false
        }
        Err(_) => {
            write_error(
                error_buffer,
                error_buffer_len,
                "DeepFilterNet panicked during flush",
            );
            false
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn fourfun_deepfilter_destroy(state: *mut DeepFilterState) {
    if !state.is_null() {
        unsafe {
            drop(Box::from_raw(state));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_non_48khz_capture() {
        let error = match DeepFilterState::new(44_100, 1) {
            Ok(_) => panic!("expected non-48 kHz capture to fail"),
            Err(error) => error,
        };
        assert!(error.contains("48 kHz"));
    }

    #[test]
    fn rejects_wrong_frame_count() {
        let mut state = DeepFilterState::new(48_000, 1).expect("create state");
        let hop = state.hop_size;
        let mut samples = vec![0.0f32; hop - 1];
        let frames = samples.len();
        let error = match state.process(&mut samples, frames, 1) {
            Ok(()) => panic!("expected wrong frame count to fail"),
            Err(error) => error,
        };
        assert!(error.contains("expected"), "unexpected error: {error}");
    }

    #[test]
    fn processes_exact_hop_in_place() {
        let mut state = DeepFilterState::new(48_000, 1).expect("create state");
        let hop = state.hop_size;
        // 1 kHz tone at -20 dBFS: speech-like periodic content the net must
        // accept without erroring and return finite samples for.
        let mut samples = (0..hop)
            .map(|i| 0.1 * (2.0 * std::f32::consts::PI * 1000.0 * i as f32 / 48_000.0).sin())
            .collect::<Vec<f32>>();
        state
            .process(&mut samples, hop, 1)
            .expect("exact hop must process");
        assert_eq!(samples.len(), hop);
        assert!(
            samples.iter().all(|sample| sample.is_finite()),
            "net produced non-finite samples"
        );
    }

    /// Offline suppression simulation with the REAL DeepFilterNet3 model:
    /// 6 s of synthetic "speech in noise" (0 dB SNR, alternating 1 s
    /// speech / 1 s noise-only), processed hop-by-hop exactly like the
    /// C++ audio thread does. Proves the net attenuates noise while
    /// preserving voice, and measures CPU headroom (RTF).
    #[test]
    fn suppresses_noise_on_synthetic_speech() {
        use std::time::Instant;

        const SR: f32 = 48_000.0;
        const SECS: usize = 6;
        const N: usize = 48_000 * SECS;

        // Deterministic LCG so the test is reproducible.
        let mut rng_state: u64 = 0x1234_5678_9ABC_DEF1;
        let mut rand = || {
            rng_state = rng_state
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            ((rng_state >> 33) as f32 / u32::MAX as f32) * 2.0 - 1.0
        };

        // Speech-like carrier: harmonic complex (F0 120 Hz, 8 harmonics)
        // with 3.5 Hz syllabic amplitude modulation. Active on odd seconds.
        let mut clean = vec![0.0f32; N];
        let mut speech_power = 0.0f64;
        let mut speech_count = 0usize;
        for (n, sample) in clean.iter_mut().enumerate() {
            let second = n / 48_000;
            if second % 2 == 1 {
                let t = n as f32 / SR;
                let mut harmonic = 0.0f32;
                for harmonic_index in 1..=8 {
                    harmonic += (2.0 * std::f32::consts::PI * 120.0 * harmonic_index as f32 * t)
                        .sin()
                        / harmonic_index as f32;
                }
                let syllabic = 0.6 + 0.4 * (2.0 * std::f32::consts::PI * 3.5 * t).sin();
                *sample = 0.12 * harmonic * syllabic;
                speech_power += (*sample as f64) * (*sample as f64);
                speech_count += 1;
            }
        }
        let speech_rms = (speech_power / speech_count as f64).sqrt();
        // White noise at 0 dB SNR relative to active-speech RMS.
        let noise: Vec<f32> = (0..N)
            .map(|_| rand() * speech_rms as f32 * std::f32::consts::SQRT_2)
            .collect();
        let mixture: Vec<f32> = clean
            .iter()
            .zip(noise.iter())
            .map(|(speech, noise)| speech + noise)
            .collect();

        let mut state = DeepFilterState::new(48_000, 1).expect("create state");
        let hop = state.hop_size;
        assert_eq!(N % hop, 0, "test audio must be hop-aligned");
        let mut output = vec![0.0f32; N];
        let start = Instant::now();
        for (input_hop, output_hop) in mixture.chunks_exact(hop).zip(output.chunks_exact_mut(hop)) {
            output_hop.copy_from_slice(input_hop);
            state.process(output_hop, hop, 1).expect("hop must process");
        }
        let elapsed = start.elapsed();
        let rtf = elapsed.as_secs_f64() / SECS as f64;
        eprintln!("inference wall time: {elapsed:?} for {SECS}s audio (RTF {rtf:.2})");

        // Noise-only segments (even seconds, skipping the first 0.5 s of
        // state warmup): residual noise power in vs out.
        let mut noise_in = 0.0f64;
        let mut noise_out = 0.0f64;
        let mut noise_n = 0usize;
        for n in 24_000..N {
            if (n / 48_000) % 2 == 0 {
                noise_in += (mixture[n] as f64) * (mixture[n] as f64);
                noise_out += (output[n] as f64) * (output[n] as f64);
                noise_n += 1;
            }
        }
        let attenuation_db =
            10.0 * (noise_out / noise_n as f64 / (noise_in / noise_n as f64)).log10();
        eprintln!("noise attenuation: {attenuation_db:.1} dB");
        // Active-speech segments (odd seconds): correlation clean vs out.
        // NOTE: DeepFilterNet's deep filtering predicts complex coefficients
        let mut best_correlation = f32::MIN;
        let mut best_lag = 0;
        let mut lag = -(2 * hop as isize);
        while lag <= 2 * hop as isize {
            let mut sum_clean = 0.0f64;
            let mut sum_out = 0.0f64;
            let mut sum_clean_sq = 0.0f64;
            let mut sum_out_sq = 0.0f64;
            let mut sum_cross = 0.0f64;
            let mut count = 0usize;
            for n in 24_000..N {
                let second = n / 48_000;
                if second % 2 == 0 {
                    continue;
                }
                let m = n as isize + lag;
                if m < 0 || m >= N as isize {
                    continue;
                }
                let clean_sample = clean[n] as f64;
                let out_sample = output[m as usize] as f64;
                sum_clean += clean_sample;
                sum_out += out_sample;
                sum_clean_sq += clean_sample * clean_sample;
                sum_out_sq += out_sample * out_sample;
                sum_cross += clean_sample * out_sample;
                count += 1;
            }
            let mean_clean = sum_clean / count as f64;
            let mean_out = sum_out / count as f64;
            let covariance = sum_cross / count as f64 - mean_clean * mean_out;
            let std_clean = (sum_clean_sq / count as f64 - mean_clean * mean_clean).sqrt();
            let std_out = (sum_out_sq / count as f64 - mean_out * mean_out).sqrt();
            let correlation = (covariance / (std_clean * std_out)) as f32;
            if correlation > best_correlation {
                best_correlation = correlation;
                best_lag = lag;
            }
            lag += 32;
        }
        let correlation = best_correlation;
        eprintln!("best lag: {best_lag} samples");
        eprintln!("clean-vs-output correlation: {correlation:.3}");
        assert!(
            output.iter().all(|sample| sample.is_finite()),
            "net produced non-finite samples"
        );
        assert!(
            attenuation_db < -6.0,
            "net is not suppressing: attenuation {attenuation_db:.1} dB"
        );
        assert!(
            correlation > 0.7,
            "net is mangling speech: correlation {correlation:.3}"
        );
    }
}
