//! Contrato PCM (§7.1): voz float32 48 kHz mono, hop 480; share estéreo;
//! int16 na fronteira do SDK.

use crate::errors::MediaError;

/// Taxa canônica do engine na fronteira do DSP.
pub const ENGINE_SAMPLE_RATE_HZ: u32 = 48_000;
/// Hop DSP/APM: 10 ms = 480 samples por canal.
pub const HOP_SAMPLES_PER_CHANNEL: usize = 480;
/// Teto de canais (mono voz + estéreo share/render).
pub const MAX_CHANNELS: u16 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PcmFormat {
    pub sample_rate_hz: u32,
    pub channels: u16,
    pub samples_per_channel: u16,
}

impl PcmFormat {
    /// Formato canônico de voz: mono 48 kHz / 480.
    pub const VOICE_MONO: Self = Self {
        sample_rate_hz: ENGINE_SAMPLE_RATE_HZ,
        channels: 1,
        samples_per_channel: HOP_SAMPLES_PER_CHANNEL as u16,
    };
    /// Formato canônico de share/render: estéreo 48 kHz / 480.
    pub const SHARE_STEREO: Self = Self {
        sample_rate_hz: ENGINE_SAMPLE_RATE_HZ,
        channels: 2,
        samples_per_channel: HOP_SAMPLES_PER_CHANNEL as u16,
    };

    /// Valida layout: `len == channels * samples_per_channel`.
    pub fn validate_len(&self, len: usize) -> Result<(), MediaError> {
        let expected =
            self.channels as usize * self.samples_per_channel as usize;
        if len != expected {
            return Err(MediaError::InvalidFormat(format!(
                "expected {expected} values ({}ch x {}spc), got {len}",
                self.channels, self.samples_per_channel
            )));
        }
        Ok(())
    }

    /// Voz canônica? (usado no gate AC-03)
    pub fn is_canonical_voice(&self) -> bool {
        *self == Self::VOICE_MONO
    }

    pub fn total_values(&self) -> usize {
        self.channels as usize * self.samples_per_channel as usize
    }
}

/// Converte int16 interleaved -> float32 normalizado, saturando NaN/Inf para 0.
pub fn int16_to_float32(input: &[i16], output: &mut [f32]) {
    assert_eq!(input.len(), output.len());
    for (dst, src) in output.iter_mut().zip(input.iter()) {
        // -32768..32767 -> -1.0..~1.0 (divisão por 32768 preserva simetria).
        *dst = (*src as f32) / 32768.0;
    }
}

/// Converte float32 -> int16 com saturação (sem wrap) e sanitização.
pub fn float32_to_int16(input: &[f32], output: &mut [i16]) {
    assert_eq!(input.len(), output.len());
    for (dst, src) in output.iter_mut().zip(input.iter()) {
        let mut v = *src;
        if !v.is_finite() {
            v = 0.0;
        }
        // Clamp em [-1.0, ~1.0]; 32767 é o teto positivo.
        let scaled = (v * 32768.0).round();
        *dst = scaled.clamp(-32768.0, 32767.0) as i16;
    }
}

/// Sanitiza bloco float32 in-place: NaN/Inf -> 0. Retorna ocorrências.
pub fn sanitize_float32(block: &mut [f32]) -> u64 {
    let mut bad = 0u64;
    for v in block.iter_mut() {
        if !v.is_finite() {
            *v = 0.0;
            bad += 1;
        }
    }
    bad
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn voice_format_is_canonical() {
        assert!(PcmFormat::VOICE_MONO.is_canonical_voice());
        assert!(!PcmFormat::SHARE_STEREO.is_canonical_voice());
    }

    #[test]
    fn validate_len_rejects_mismatch() {
        assert!(PcmFormat::VOICE_MONO.validate_len(480).is_ok());
        assert!(PcmFormat::VOICE_MONO.validate_len(481).is_err());
        assert!(PcmFormat::SHARE_STEREO.validate_len(960).is_ok());
    }

    #[test]
    fn int16_extremes_round_trip_without_wrap() {
        let input = [i16::MIN, -1, 0, 1, i16::MAX];
        let mut f = [0.0f32; 5];
        int16_to_float32(&input, &mut f);
        assert!((f[0] - -1.0).abs() < 1e-6);
        let mut back = [0i16; 5];
        float32_to_int16(&f, &mut back);
        assert_eq!(back, input);
    }

    #[test]
    fn float32_overflow_saturates_and_nan_zeroes() {
        let input = [2.0f32, -2.0, f32::NAN, f32::INFINITY, 0.5];
        let mut out = [0i16; 5];
        float32_to_int16(&input, &mut out);
        assert_eq!(out[0], 32767);
        assert_eq!(out[1], -32768);
        assert_eq!(out[2], 0);
        assert_eq!(out[3], 0);
    }

    #[test]
    fn sanitize_counts_non_finite() {
        let mut block = [0.25f32, f32::NAN, 0.5, f32::NEG_INFINITY];
        assert_eq!(sanitize_float32(&mut block), 2);
        assert!(block.iter().all(|v| v.is_finite()));
    }
}
