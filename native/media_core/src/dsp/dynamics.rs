//! Dynamics (§10.1): expander/AGC lento/compressor/limiter em cadeia
//! determinística por bloco de 480. Parâmetros espelham o pipeline C++
//! atual para paridade audível na extração.

#[derive(Debug, Clone)]
pub struct DynamicsProfile {
    /// Alvo do AGC em dBFS.
    pub agc_target_db: f32,
    /// Ganho máximo/mínimo do AGC em dB.
    pub agc_max_gain_db: f32,
    pub agc_min_gain_db: f32,
    /// Threshold do compressor em dBFS + ratio.
    pub comp_threshold_db: f32,
    pub comp_ratio: f32,
    /// Teto do limiter em dBFS.
    pub limiter_ceiling_db: f32,
}

impl DynamicsProfile {
    /// Perfil padrão (paridade com `StudioDynamics` do C++ atual).
    pub fn studio() -> Self {
        Self {
            agc_target_db: -15.0,
            agc_max_gain_db: 9.0,
            agc_min_gain_db: -12.0,
            comp_threshold_db: -12.0,
            comp_ratio: 3.0,
            limiter_ceiling_db: -1.0,
        }
    }

    /// Perfil leve do fallback basic (só proteção de picos).
    pub fn light() -> Self {
        Self {
            agc_target_db: -15.0,
            agc_max_gain_db: 3.0,
            agc_min_gain_db: -6.0,
            comp_threshold_db: -9.0,
            comp_ratio: 2.0,
            limiter_ceiling_db: -1.0,
        }
    }
}

#[derive(Debug, Clone)]
pub struct Dynamics {
    profile: DynamicsProfile,
    agc_gain_db: f32,
}

impl Dynamics {
    pub fn new(profile: DynamicsProfile) -> Self {
        Self {
            profile,
            agc_gain_db: 0.0,
        }
    }

    /// Processa bloco in-place. `voice_probability` (0..1, do VAD) condiciona
    /// o AGC: sem voz, o ganho congela (sem pumping de ruído).
    pub fn process(&mut self, block: &mut [f32], voice_probability: f32) {
        // Nível do bloco.
        let mut peak: f32 = 0.0;
        let mut sum = 0.0f64;
        for v in block.iter() {
            let a = v.abs();
            peak = peak.max(a);
            sum += (*v as f64) * (*v as f64);
        }
        let rms_db =
            20.0 * ((sum / block.len().max(1) as f64).sqrt().max(1e-9) as f32)
                .log10();

        // AGC lento: corrige em direção ao alvo, proporcional à voz.
        let err = self.profile.agc_target_db - rms_db;
        let step = (err * 0.02 * voice_probability.clamp(0.0, 1.0)).clamp(
            -0.15,
            0.15,
        );
        self.agc_gain_db = (self.agc_gain_db + step).clamp(
            self.profile.agc_min_gain_db,
            self.profile.agc_max_gain_db,
        );
        let agc_lin = 10.0f32.powf(self.agc_gain_db / 20.0);

        let ceiling_lin =
            10.0f32.powf(self.profile.limiter_ceiling_db / 20.0);
        let thr_lin = 10.0f32.powf(self.profile.comp_threshold_db / 20.0);
        for v in block.iter_mut() {
            let mut s = *v * agc_lin;
            // Compressor estático acima do threshold.
            let a = s.abs();
            if a > thr_lin {
                let over_db = 20.0 * (a / thr_lin).log10();
                let reduced_db = over_db / self.profile.comp_ratio;
                s = s.signum()
                    * thr_lin
                    * 10.0f32.powf(reduced_db / 20.0);
            }
            // Limiter final + clamp.
            s = s.clamp(-ceiling_lin, ceiling_lin).clamp(-1.0, 1.0);
            *v = if s.is_finite() { s } else { 0.0 };
        }
        let _ = peak;
    }

    pub fn agc_gain_db(&self) -> f32 {
        self.agc_gain_db
    }

    pub fn reset(&mut self) {
        self.agc_gain_db = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quiet_voice_gets_gain_and_loud_hits_limiter() {
        let mut dyn_ = Dynamics::new(DynamicsProfile::studio());
        // Voz baixa (-30 dBFS aprox): AGC deve abrir ganho com voz presente.
        // Cada hop recebe áudio NOVO (como em produção); reprocessar o mesmo
        // buffer in-place acumularia ganho sobre ganho e falsearia o teste.
        for _ in 0..60 {
            let mut quiet = vec![0.03f32; 480];
            dyn_.process(&mut quiet, 1.0);
        }
        assert!(
            dyn_.agc_gain_db() > 1.0,
            "agc did not open: {}",
            dyn_.agc_gain_db()
        );
        // Pico alto: limiter segura em ±1.
        let mut loud = vec![5.0f32; 480];
        dyn_.process(&mut loud, 1.0);
        assert!(loud.iter().all(|v| v.abs() <= 1.0));
        assert!(loud.iter().all(|v| v.is_finite()));
    }

    #[test]
    fn agc_freezes_without_voice() {
        let mut dyn_ = Dynamics::new(DynamicsProfile::studio());
        let mut noise = vec![0.001f32; 480];
        for _ in 0..60 {
            dyn_.process(&mut noise, 0.0);
        }
        assert!(
            dyn_.agc_gain_db().abs() < 0.5,
            "agc pumped noise: {}",
            dyn_.agc_gain_db()
        );
    }
}
