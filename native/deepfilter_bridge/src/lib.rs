use std::ffi::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::slice;

use deep_filter::tract::{DfParams, DfTract, RuntimeParams};
use ndarray::Array2;

const DEEPFILTER_SAMPLE_RATE: u32 = 48_000;
// When a vetted DeepFilterNet2.tar.gz is committed, replace this with:
// include_bytes!("../models/DeepFilterNet2.tar.gz")
const DEEPFILTER2_MODEL: &[u8] = &[];

pub struct DeepFilterState {
    model: DfTract,
    input: Array2<f32>,
    output: Array2<f32>,
    channels: usize,
    hop_size: usize,
}

impl DeepFilterState {
    fn new(sample_rate_hz: u32, channels: usize) -> Result<Self, String> {
        if sample_rate_hz != DEEPFILTER_SAMPLE_RATE {
            return Err("DeepFilterNet requires 48 kHz capture".to_string());
        }
        if channels == 0 {
            return Err("DeepFilterNet requires at least one channel".to_string());
        }

        let params = if DEEPFILTER2_MODEL.is_empty() {
            DfParams::default()
        } else {
            DfParams::from_bytes(DEEPFILTER2_MODEL)
                .map_err(|error| format!("failed to load DeepFilterNet2 model: {error}"))?
        };
        let runtime = RuntimeParams::default_with_ch(channels);
        let model = DfTract::new(params, &runtime)
            .map_err(|error| format!("failed to initialize DeepFilterNet: {error}"))?;
        if model.sr as u32 != DEEPFILTER_SAMPLE_RATE {
            return Err(format!(
                "unexpected DeepFilterNet sample rate: {}",
                model.sr
            ));
        }

        let hop_size = model.hop_size;
        Ok(Self {
            model,
            input: Array2::zeros((channels, hop_size)),
            output: Array2::zeros((channels, hop_size)),
            channels,
            hop_size,
        })
    }

    fn process(
        &mut self,
        samples: &mut [f32],
        frames: usize,
        channels: usize,
    ) -> Result<(), String> {
        if channels != self.channels {
            return Err("DeepFilterNet channel count changed".to_string());
        }
        if frames != self.hop_size {
            return Ok(());
        }
        if samples.len() < frames * channels {
            return Err("DeepFilterNet received a short sample buffer".to_string());
        }

        for frame in 0..frames {
            for channel in 0..channels {
                self.input[(channel, frame)] = samples[(frame * channels) + channel];
            }
        }

        self.model
            .process(self.input.view(), self.output.view_mut())
            .map_err(|error| format!("DeepFilterNet processing failed: {error}"))?;

        for frame in 0..frames {
            for channel in 0..channels {
                samples[(frame * channels) + channel] = self.output[(channel, frame)];
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
pub extern "C" fn fourfun_deepfilter_destroy(state: *mut DeepFilterState) {
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
}
