//! Backend simulado: enumeração determinística, jitter de callback e
//! unplug para testes de integração sem hardware (§33.3 item 1).

use crate::backends::{AudioBackend, DeviceDescriptor};
use crate::errors::MediaError;

pub struct SimulatedBackend {
    pub devices: Vec<DeviceDescriptor>,
}

impl SimulatedBackend {
    pub fn stereo_lab() -> Self {
        Self {
            devices: vec![
                DeviceDescriptor {
                    id: "sim-mic".to_string(),
                    label: "Simulated Microphone".to_string(),
                    is_input: true,
                    sample_rates: vec![44_100, 48_000],
                    channels: vec![1, 2],
                },
                DeviceDescriptor {
                    id: "sim-speaker".to_string(),
                    label: "Simulated Speakers".to_string(),
                    is_input: false,
                    sample_rates: vec![44_100, 48_000],
                    channels: vec![2],
                },
            ],
        }
    }

    pub fn empty() -> Self {
        Self { devices: Vec::new() }
    }
}

impl AudioBackend for SimulatedBackend {
    fn name(&self) -> &'static str {
        "simulated"
    }

    fn enumerate(&self) -> Result<Vec<DeviceDescriptor>, MediaError> {
        Ok(self.devices.clone())
    }
}

/// Gera callbacks de tamanho variável (128/256/480/512/960) a partir de
/// um tom, para teste do reframer sem hardware.
pub fn simulated_callbacks(sizes: &[usize], total: usize) -> Vec<Vec<f32>> {
    let mut out = Vec::new();
    let mut n = 0usize;
    let mut i = 0;
    while n < total {
        let size = sizes[i % sizes.len()];
        let block: Vec<f32> = (0..size)
            .map(|k| {
                0.2 * (2.0 * std::f32::consts::PI * 440.0 * (n + k) as f32
                    / 48_000.0)
                    .sin()
            })
            .collect();
        n += size;
        out.push(block);
        i += 1;
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enumerates_lab_devices() {
        let b = SimulatedBackend::stereo_lab();
        let devs = b.enumerate().unwrap();
        assert_eq!(devs.len(), 2);
        assert!(devs.iter().any(|d| d.is_input));
    }
}
