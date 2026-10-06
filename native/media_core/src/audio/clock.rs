//! Clock lógico da sessão (§7.2): `sample_index` avança no domínio
//! 48 kHz; hot-swap conserva o clock e incrementa `device_epoch`.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FrameMetadata {
    pub generation: u64,
    pub device_epoch: u64,
    /// Primeiro sample por canal do bloco, no domínio 48 kHz.
    pub sample_index: u64,
    pub sample_rate_hz: u32,
    pub channels: u16,
    pub samples_per_channel: u16,
    pub discontinuity: bool,
}

#[derive(Debug, Clone)]
pub struct SessionClock {
    generation: u64,
    device_epoch: u64,
    sample_index: u64,
}

impl SessionClock {
    pub fn new(generation: u64) -> Self {
        Self {
            generation,
            device_epoch: 0,
            sample_index: 0,
        }
    }

    /// Hot-swap: novo epoch, mesmo clock (não finge continuidade).
    pub fn next_epoch(&mut self) -> u64 {
        self.device_epoch += 1;
        self.device_epoch
    }

    pub fn stamp(
        &mut self,
        channels: u16,
        samples_per_channel: u16,
        discontinuity: bool,
    ) -> FrameMetadata {
        let meta = FrameMetadata {
            generation: self.generation,
            device_epoch: self.device_epoch,
            sample_index: self.sample_index,
            sample_rate_hz: crate::audio::format::ENGINE_SAMPLE_RATE_HZ,
            channels,
            samples_per_channel,
            discontinuity,
        };
        self.sample_index += samples_per_channel as u64;
        meta
    }

    pub fn device_epoch(&self) -> u64 {
        self.device_epoch
    }

    pub fn sample_index(&self) -> u64 {
        self.sample_index
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hot_swap_keeps_clock_and_bumps_epoch() {
        let mut clock = SessionClock::new(3);
        let a = clock.stamp(1, 480, false);
        assert_eq!(a.sample_index, 0);
        assert_eq!(clock.next_epoch(), 1);
        let b = clock.stamp(1, 480, true);
        assert_eq!(b.device_epoch, 1);
        assert_eq!(b.sample_index, 480);
        assert!(b.discontinuity);
    }
}
