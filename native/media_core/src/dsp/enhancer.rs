//! Contrato do enhancer (§6): blocos mono de 480 @48 kHz.
//!
//! ADR-006 pendente: o produtivo será o port Rust atual
//! (`native/deepfilter_bridge`, via `ort`) otimizado ou o runtime online
//! sherpa-onnx. Este trait é a fronteira — os dois candidatos implementam
//! a mesma interface e são comparados pelo oracle de teste.

use crate::audio::format::HOP_SAMPLES_PER_CHANNEL;
use crate::errors::DspError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResetReason {
    DeviceSwitch,
    ProfileChange,
    StreamStart,
    ErrorRecovery,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ProcessReport {
    /// Hops efetivamente processados (0 = bypass; nunca alegar Studio
    /// ativo com `processed_hops == 0` — §21).
    pub processed_hops: u64,
    /// Atraso algorítmico do modelo em samples (ex.: hop inicial de
    /// silêncio do DPDFNet).
    pub algorithmic_delay_samples: u32,
}

pub trait SpeechEnhancer {
    fn process_480(
        &mut self,
        input: &[f32; HOP_SAMPLES_PER_CHANNEL],
        out: &mut [f32; HOP_SAMPLES_PER_CHANNEL],
    ) -> Result<ProcessReport, DspError>;

    fn reset(&mut self, reason: ResetReason);

    fn algorithmic_delay_samples(&self) -> u32;

    fn name(&self) -> &'static str;
}

/// Enhancer nulo: passthrough com `processed_hops == 0`. Usado no perfil
/// minimal e como base de teste do fallback observável.
#[derive(Debug, Default)]
pub struct NoopEnhancer {
    bypassed: u64,
}

impl SpeechEnhancer for NoopEnhancer {
    fn process_480(
        &mut self,
        input: &[f32; HOP_SAMPLES_PER_CHANNEL],
        out: &mut [f32; HOP_SAMPLES_PER_CHANNEL],
    ) -> Result<ProcessReport, DspError> {
        out.copy_from_slice(input);
        self.bypassed += 1;
        Ok(ProcessReport {
            processed_hops: 0,
            algorithmic_delay_samples: self.algorithmic_delay_samples(),
        })
    }

    fn reset(&mut self, _reason: ResetReason) {
        self.bypassed = 0;
    }

    fn algorithmic_delay_samples(&self) -> u32 {
        0
    }

    fn name(&self) -> &'static str {
        "noop"
    }
}

/// Stub do bridge DPDFNet2: reserva o slot do port Rust atual até a
/// extração validada (§Fase 2). Retorna `ModelMissing` em vez de fingir
/// processamento — o fallback então degrada de forma observável.
#[derive(Debug, Default)]
pub struct DeepFilterBridgeStub {
    attempts: u64,
}

impl SpeechEnhancer for DeepFilterBridgeStub {
    fn process_480(
        &mut self,
        _input: &[f32; HOP_SAMPLES_PER_CHANNEL],
        _out: &mut [f32; HOP_SAMPLES_PER_CHANNEL],
    ) -> Result<ProcessReport, DspError> {
        self.attempts += 1;
        Err(DspError::ModelMissing(
            "deepfilter_bridge ainda não extraído para media_core (Fase 2)".to_string(),
        ))
    }

    fn reset(&mut self, _reason: ResetReason) {
        self.attempts = 0;
    }

    fn algorithmic_delay_samples(&self) -> u32 {
        // Hop inicial de silêncio documentado no port atual.
        HOP_SAMPLES_PER_CHANNEL as u32
    }

    fn name(&self) -> &'static str {
        "dpdfnet2-stub"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn noop_is_honest_about_bypass() {
        let mut e = NoopEnhancer::default();
        let input = [0.5f32; HOP_SAMPLES_PER_CHANNEL];
        let mut out = [0.0f32; HOP_SAMPLES_PER_CHANNEL];
        let report = e.process_480(&input, &mut out).unwrap();
        assert_eq!(out, input);
        assert_eq!(report.processed_hops, 0);
    }

    #[test]
    fn bridge_stub_fails_loudly_not_silently() {
        let mut e = DeepFilterBridgeStub::default();
        let input = [0.5f32; HOP_SAMPLES_PER_CHANNEL];
        let mut out = [0.0f32; HOP_SAMPLES_PER_CHANNEL];
        assert!(matches!(
            e.process_480(&input, &mut out),
            Err(DspError::ModelMissing(_))
        ));
    }
}
