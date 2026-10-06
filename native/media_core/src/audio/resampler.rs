//! Resampler com estado (§7.2): passthrough 48 kHz; interpolação linear
//! para 44,1 kHz e taxas próximas, com carry fracionário entre blocos.
//! Um resampler band-limited dedicado é trabalho futuro — este estágio
//! garante continuidade de fase e sample count (erro residual < 1 sample
//! por bloco, absorvido sem perda de ordem).

#[derive(Debug, Clone)]
pub struct Resampler {
    from_hz: u32,
    /// Posição fracionária pendente no domínio de `input` (0 <= frac < step).
    frac: f64,
    produced: u64,
}

impl Resampler {
    pub fn new(from_hz: u32) -> Self {
        Self {
            from_hz,
            frac: 0.0,
            produced: 0,
        }
    }

    pub fn ratio(&self) -> f64 {
        48_000.0 / self.from_hz as f64
    }

    /// Converte `input` (domínio `from_hz`) para 48 kHz. Retorna samples.
    pub fn process(&mut self, input: &[f32]) -> Vec<f32> {
        if self.from_hz == 48_000 {
            self.produced += input.len() as u64;
            return input.to_vec();
        }
        if input.is_empty() {
            return Vec::new();
        }
        let step = self.from_hz as f64 / 48_000.0;
        let mut out = Vec::new();
        let mut pos = self.frac;
        while pos < input.len() as f64 {
            let i0 = pos.floor() as usize;
            let frac = (pos - i0 as f64) as f32;
            let s0 = input[i0];
            // Sem lookahead para o próximo bloco: clamp no fim (erro de no
            // máximo 1 sample interpolado por bloco, inaudível).
            let s1 = if i0 + 1 < input.len() {
                input[i0 + 1]
            } else {
                s0
            };
            out.push(s0 + (s1 - s0) * frac);
            pos += step;
        }
        self.frac = pos - input.len() as f64;
        debug_assert!((0.0..step + 1e-9).contains(&self.frac), "frac {}", self.frac);
        if self.frac < 0.0 {
            self.frac = 0.0;
        }
        self.produced += out.len() as u64;
        out
    }

    pub fn produced(&self) -> u64 {
        self.produced
    }

    pub fn reset(&mut self) {
        self.frac = 0.0;
        self.produced = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn passthrough_48k_preserves_samples() {
        let mut r = Resampler::new(48_000);
        let input = vec![0.1f32, 0.2, 0.3];
        assert_eq!(r.process(&input), input);
        assert_eq!(r.produced(), 3);
    }

    #[test]
    fn upsample_44k1_block_produces_480() {
        let mut r = Resampler::new(44_100);
        // Tom 1 kHz em 44,1 kHz.
        let block: Vec<f32> = (0..441)
            .map(|i| {
                (2.0 * std::f32::consts::PI * 1000.0 * i as f32 / 44_100.0)
                    .sin()
            })
            .collect();
        let a = r.process(&block);
        let b = r.process(&block);
        assert!((a.len() as isize - 480).abs() <= 1, "len {}", a.len());
        assert!((b.len() as isize - 480).abs() <= 1, "len {}", b.len());
        assert!(a.iter().chain(b.iter()).all(|v| v.is_finite()));
    }

    #[test]
    fn impulse_response_is_finite() {
        let mut r = Resampler::new(44_100);
        let mut input = vec![0.0f32; 441];
        input[220] = 1.0;
        let out = r.process(&input);
        assert!(out.iter().all(|v| v.is_finite()));
        assert!(out.iter().any(|&v| v > 0.1));
    }

    #[test]
    fn sample_count_is_conserved_across_blocks() {
        let mut r = Resampler::new(44_100);
        // 10 blocos de 441 @44,1k devem render ~4800 @48k (±1 por bloco).
        let mut total = 0usize;
        for _ in 0..10 {
            total += r.process(&vec![0.0f32; 441]).len();
        }
        assert!((total as isize - 4800).abs() <= 10, "total {total}");
        assert_eq!(r.produced(), total as u64);
    }
}
