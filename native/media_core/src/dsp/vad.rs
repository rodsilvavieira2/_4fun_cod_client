//! VAD lateral (§11): detector de energia com gate suave. Não é
//! supressão — apenas informa probabilidade de fala para AGC/dynamics.

#[derive(Debug, Clone)]
pub struct Vad {
    /// Limiar de fala em dBFS (ex.: -45).
    speech_threshold_db: f32,
    /// Largura da transição suave em dB.
    soft_width_db: f32,
    last_probability: f32,
}

impl Vad {
    pub fn new(speech_threshold_db: f32, soft_width_db: f32) -> Self {
        Self {
            speech_threshold_db,
            soft_width_db: soft_width_db.max(0.5),
            last_probability: 0.0,
        }
    }

    /// Probabilidade de fala 0..1 para um hop de 480.
    pub fn probability(&mut self, hop: &[f32]) -> f32 {
        let mut sum = 0.0f64;
        for v in hop {
            sum += (*v as f64) * (*v as f64);
        }
        let rms = (sum / hop.len().max(1) as f64).sqrt();
        let db = 20.0 * (rms.max(1e-9) as f32).log10();
        // Gate suave: 0 abaixo de (thr - width/2), 1 acima de (thr + width/2).
        let t = ((db - self.speech_threshold_db) / self.soft_width_db + 0.5)
            .clamp(0.0, 1.0);
        // Suavização temporal leve (ataque/release simétricos simples).
        self.last_probability += (t - self.last_probability) * 0.35;
        self.last_probability.clamp(0.0, 1.0)
    }

    pub fn last_probability(&self) -> f32 {
        self.last_probability
    }

    pub fn reset(&mut self) {
        self.last_probability = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn silence_scores_near_zero_and_tone_near_one() {
        let mut vad = Vad::new(-45.0, 6.0);
        for _ in 0..20 {
            assert!(vad.probability(&[0.0f32; 480]) < 0.2);
        }
        let tone: Vec<f32> = (0..480)
            .map(|i| {
                0.3 * (2.0 * std::f32::consts::PI * 440.0 * i as f32
                    / 48_000.0)
                    .sin()
            })
            .collect();
        for _ in 0..20 {
            vad.probability(&tone);
        }
        assert!(vad.last_probability() > 0.8);
    }
}
