//! Reframer (§7.2): agrega/quebra callbacks de tamanho arbitrário em
//! blocos de 480 samples, preservando ordem e sobras. Sem perda/duplicação.

use crate::audio::format::HOP_SAMPLES_PER_CHANNEL;

/// FIFO pré-alocável que emite blocos exatos de 480 mono.
#[derive(Debug)]
pub struct Reframer {
    pending: Vec<f32>,
    total_produced: u64,
    discontinuities: u64,
}

impl Reframer {
    pub fn new() -> Self {
        Self {
            pending: Vec::with_capacity(HOP_SAMPLES_PER_CHANNEL * 2),
            total_produced: 0,
            discontinuities: 0,
        }
    }

    /// Empurra `input` (qualquer tamanho); retorna blocos completos de 480.
    pub fn push(&mut self, input: &[f32]) -> Vec<[f32; HOP_SAMPLES_PER_CHANNEL]> {
        self.pending.extend_from_slice(input);
        let mut out = Vec::new();
        while self.pending.len() >= HOP_SAMPLES_PER_CHANNEL {
            let mut block = [0.0f32; HOP_SAMPLES_PER_CHANNEL];
            block.copy_from_slice(&self.pending[..HOP_SAMPLES_PER_CHANNEL]);
            self.pending.drain(..HOP_SAMPLES_PER_CHANNEL);
            self.total_produced += HOP_SAMPLES_PER_CHANNEL as u64;
            out.push(block);
        }
        out
    }

    /// Marca descontinuidade (hot-swap): descarta sobra, não finge continuidade.
    pub fn mark_discontinuity(&mut self) {
        self.pending.clear();
        self.discontinuities += 1;
    }

    pub fn pending_len(&self) -> usize {
        self.pending.len()
    }

    pub fn total_produced(&self) -> u64 {
        self.total_produced
    }

    pub fn discontinuities(&self) -> u64 {
        self.discontinuities
    }
}

impl Default for Reframer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aggregates_256_plus_256_into_480_plus_32() {
        let mut r = Reframer::new();
        let a = vec![1.0f32; 256];
        let b = vec![2.0f32; 256];
        assert!(r.push(&a).is_empty());
        let blocks = r.push(&b);
        assert_eq!(blocks.len(), 1);
        assert_eq!(r.pending_len(), 32);
        assert_eq!(r.total_produced(), 480);
        // Ordem preservada: 256 de 1.0 + 224 de 2.0.
        assert!(blocks[0][..256].iter().all(|&v| v == 1.0));
        assert!(blocks[0][256..].iter().all(|&v| v == 2.0));
    }

    #[test]
    fn handles_128_256_480_512_960_sequences() {
        for size in [128usize, 256, 480, 512, 960] {
            let mut r = Reframer::new();
            let input = vec![0.5f32; size * 3];
            let mut produced = 0usize;
            for chunk in input.chunks(size) {
                produced += r.push(chunk).len() * HOP_SAMPLES_PER_CHANNEL;
            }
            produced += (r.pending_len() / HOP_SAMPLES_PER_CHANNEL)
                * HOP_SAMPLES_PER_CHANNEL;
            assert_eq!(produced + r.pending_len(), size * 3, "size {size}");
        }
    }

    #[test]
    fn discontinuity_discards_leftovers() {
        let mut r = Reframer::new();
        r.push(&[1.0f32; 100]);
        r.mark_discontinuity();
        assert_eq!(r.pending_len(), 0);
        assert_eq!(r.discontinuities(), 1);
    }
}
