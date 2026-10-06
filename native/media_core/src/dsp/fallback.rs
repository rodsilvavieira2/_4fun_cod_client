//! Fallback observável (§29.1): Studio -> basic -> minimal, com circuit
//! breaker por deadline e modo efetivo sempre reportado.

/// Perfil DSP solicitado.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DspProfile {
    Studio,
    #[default]
    Basic,
    Minimal,
}

/// Modo efetivo (nunca alegar Studio com 0 hops processados).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EffectiveDspMode {
    Studio,
    Basic,
    Minimal,
}

#[derive(Debug, Clone)]
pub struct DspFallback {
    requested: DspProfile,
    effective: EffectiveDspMode,
    /// Janela do circuit breaker: N deadlines em W hops disparam degradação.
    deadline_window: u32,
    deadline_threshold: u32,
    recent_deadlines: u32,
    hops_in_window: u32,
    reason: Option<String>,
}

impl DspFallback {
    pub fn new(requested: DspProfile) -> Self {
        let effective = match requested {
            DspProfile::Studio => EffectiveDspMode::Basic,
            DspProfile::Basic => EffectiveDspMode::Basic,
            DspProfile::Minimal => EffectiveDspMode::Minimal,
        };
        Self {
            requested,
            effective,
            deadline_window: 100,
            deadline_threshold: 5,
            recent_deadlines: 0,
            hops_in_window: 0,
            reason: Some("studio não validado no M1; opera basic".to_string()),
        }
    }

    pub fn requested(&self) -> DspProfile {
        self.requested
    }

    pub fn effective(&self) -> EffectiveDspMode {
        self.effective
    }

    pub fn reason(&self) -> Option<&str> {
        self.reason.as_deref()
    }

    /// Solicita novo perfil; efetivo resolve após validação de capabilities.
    pub fn request(&mut self, profile: DspProfile, studio_available: bool) {
        self.requested = profile;
        self.effective = match profile {
            DspProfile::Studio if studio_available => EffectiveDspMode::Studio,
            DspProfile::Studio => {
                self.reason = Some("studio indisponível; basic efetivo".to_string());
                EffectiveDspMode::Basic
            }
            DspProfile::Basic => EffectiveDspMode::Basic,
            DspProfile::Minimal => EffectiveDspMode::Minimal,
        };
    }

    /// Registra resultado de hop; retorna `true` se degradou neste hop.
    pub fn note_hop(&mut self, deadline_missed: bool) -> bool {
        self.hops_in_window += 1;
        if deadline_missed {
            self.recent_deadlines += 1;
        }
        if self.hops_in_window >= self.deadline_window {
            self.hops_in_window = 0;
            self.recent_deadlines = 0;
        }
        if self.recent_deadlines >= self.deadline_threshold
            && self.effective == EffectiveDspMode::Studio
        {
            self.effective = EffectiveDspMode::Basic;
            self.reason = Some(
                "circuit breaker: deadlines excedidos, degradado para basic"
                    .to_string(),
            );
            return true;
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn studio_request_without_model_is_honest() {
        let mut f = DspFallback::new(DspProfile::Studio);
        assert_eq!(f.effective(), EffectiveDspMode::Basic);
        assert!(f.reason().is_some());
        f.request(DspProfile::Studio, true);
        assert_eq!(f.effective(), EffectiveDspMode::Studio);
    }

    #[test]
    fn circuit_breaker_degrades_studio() {
        let mut f = DspFallback::new(DspProfile::Basic);
        f.request(DspProfile::Studio, true);
        for _ in 0..5 {
            f.note_hop(true);
        }
        assert_eq!(f.effective(), EffectiveDspMode::Basic);
    }
}
