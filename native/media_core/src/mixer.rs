//! Mixer de playback (§12): volume por usuário/fonte com rampas,
//! headroom e limiter master. Speaking independe de volume 0.

use std::collections::HashMap;

/// Fonte de áudio remota (paridade com `RtcAudioSource` do Dart).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum AudioSourceKind {
    Microphone,
    ScreenShareAudio,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct TrackKey {
    pub identity: String,
    pub source: AudioSourceKind,
}

#[derive(Debug, Clone)]
struct TrackState {
    gain: f32,
    current: f32,
}

#[derive(Debug)]
pub struct Mixer {
    tracks: HashMap<TrackKey, TrackState>,
    master_gain: f32,
    limiter_ceiling: f32,
    ramp_per_block: f32,
    active_tracks: usize,
}

impl Mixer {
    pub fn new() -> Self {
        Self {
            tracks: HashMap::new(),
            master_gain: 1.0,
            limiter_ceiling: 10.0f32.powf(-1.0 / 20.0),
            // Rampa de ~5 ms por bloco de 10 ms (evita cliques).
            ramp_per_block: 0.5,
            active_tracks: 0,
        }
    }

    /// Ganho 0.0..2.0 por fonte; fora da faixa é normalizado (clamp).
    pub fn set_volume(&mut self, identity: &str, source: AudioSourceKind, linear: f32) {
        let gain = linear.clamp(0.0, 2.0);
        self.tracks
            .entry(TrackKey {
                identity: identity.to_string(),
                source,
            })
            .and_modify(|t| t.gain = gain)
            .or_insert(TrackState { gain, current: gain });
    }

    pub fn remove_identity(&mut self, identity: &str) {
        self.tracks.retain(|k, _| k.identity != identity);
    }

    pub fn set_master(&mut self, linear: f32) {
        self.master_gain = linear.clamp(0.0, 2.0);
    }

    /// Soma `inputs` (uma fatia por track ativa, mesma key order) em `out`
    /// estéreo interleaved. `inputs` tem `frames` samples por canal.
    pub fn mix_stereo(
        &mut self,
        frames: usize,
        inputs: &[(TrackKey, Vec<f32>)],
        out: &mut [f32],
    ) {
        assert_eq!(out.len(), frames * 2);
        out.fill(0.0);
        self.active_tracks = inputs.len();
        for (key, pcm) in inputs {
            let state = self
                .tracks
                .entry(key.clone())
                .or_insert(TrackState { gain: 1.0, current: 1.0 });
            // Rampa em direção ao alvo.
            let diff = state.gain - state.current;
            if diff.abs() > f32::EPSILON {
                let step = diff.signum() * diff.abs().min(self.ramp_per_block);
                state.current += step;
            }
            let g = state.current * self.master_gain;
            // Mono -> estéreo com headroom (-3 dB por canal); estéreo passa.
            if pcm.len() == frames {
                for i in 0..frames {
                    out[i * 2] += pcm[i] * g * std::f32::consts::FRAC_1_SQRT_2;
                    out[i * 2 + 1] +=
                        pcm[i] * g * std::f32::consts::FRAC_1_SQRT_2;
                }
            } else if pcm.len() == frames * 2 {
                for i in 0..frames {
                    out[i * 2] += pcm[i * 2] * g;
                    out[i * 2 + 1] += pcm[i * 2 + 1] * g;
                }
            }
        }
        // Limiter master.
        for v in out.iter_mut() {
            *v = (*v).clamp(-self.limiter_ceiling, self.limiter_ceiling);
            if !v.is_finite() {
                *v = 0.0;
            }
        }
    }

    pub fn active_tracks(&self) -> usize {
        self.active_tracks
    }
}

impl Default for Mixer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn volume_zero_silences_but_keeps_track() {
        let mut m = Mixer::new();
        m.set_volume("user_1", AudioSourceKind::Microphone, 0.0);
        let key = TrackKey {
            identity: "user_1".to_string(),
            source: AudioSourceKind::Microphone,
        };
        let mut out = vec![0.0f32; 480 * 2];
        m.mix_stereo(480, &[(key, vec![0.5f32; 480])], &mut out);
        assert!(out.iter().all(|&v| v == 0.0));
    }

    #[test]
    fn sources_are_independent() {
        let mut m = Mixer::new();
        m.set_volume("user_1", AudioSourceKind::Microphone, 1.0);
        m.set_volume("user_1", AudioSourceKind::ScreenShareAudio, 0.0);
        let mic = TrackKey {
            identity: "user_1".to_string(),
            source: AudioSourceKind::Microphone,
        };
        let share = TrackKey {
            identity: "user_1".to_string(),
            source: AudioSourceKind::ScreenShareAudio,
        };
        let mut out = vec![0.0f32; 8];
        m.mix_stereo(
            4,
            &[(mic, vec![1.0f32; 4]), (share, vec![1.0f32; 4])],
            &mut out,
        );
        // Só mic contribui: 1.0 * 1/sqrt(2) por canal.
        assert!((out[0] - std::f32::consts::FRAC_1_SQRT_2).abs() < 0.001);
    }

    #[test]
    fn master_limiter_prevents_clipping() {
        let mut m = Mixer::new();
        m.set_master(2.0);
        let mut out = vec![0.0f32; 8];
        let keys: Vec<(TrackKey, Vec<f32>)> = (0..8)
            .map(|i| {
                (
                    TrackKey {
                        identity: format!("user_{i}"),
                        source: AudioSourceKind::Microphone,
                    },
                    vec![1.0f32; 4],
                )
            })
            .collect();
        m.mix_stereo(4, &keys, &mut out);
        assert!(out.iter().all(|v| v.abs() <= 0.91));
    }
}
