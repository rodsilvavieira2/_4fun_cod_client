//! Sessão e segurança TX (§13, §18, §21): latch fail-closed,
//! epochs, Desired vs Effective, PTT com expiração.

use std::collections::HashMap;
use std::time::{Duration, Instant};

/// Seleção de dispositivo: segue o sistema ou fixo (pinned).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DeviceSelection {
    SystemDefault,
    Pinned(String),
}

/// Estado desejado (preferências) vs efetivo (rodando) — §21.
#[derive(Debug, Clone)]
pub struct DesiredState {
    pub muted: bool,
    pub deafened: bool,
    pub ptt_enabled: bool,
    pub input: DeviceSelection,
    pub output: DeviceSelection,
    pub input_gain: f32,
    pub output_gain: f32,
    pub user_volumes: HashMap<(String, crate::mixer::AudioSourceKind), f32>,
}

impl Default for DesiredState {
    fn default() -> Self {
        Self {
            muted: true,
            deafened: false,
            ptt_enabled: false,
            input: DeviceSelection::SystemDefault,
            output: DeviceSelection::SystemDefault,
            input_gain: 1.0,
            output_gain: 1.0,
            user_volumes: HashMap::new(),
        }
    }
}

/// Latch de transmissão fail-closed: PTT perdido expira; reconnect nunca
/// reativa PTT; deafen bloqueia voz + system audio.
#[derive(Debug)]
pub struct TxLatch {
    muted: bool,
    deafened: bool,
    ptt_enabled: bool,
    ptt_pressed: bool,
    ptt_pressed_at: Option<Instant>,
    ptt_timeout: Duration,
    input_seq: u64,
}

impl TxLatch {
    pub fn new(ptt_timeout: Duration) -> Self {
        Self {
            muted: true,
            deafened: false,
            ptt_enabled: false,
            ptt_pressed: false,
            ptt_pressed_at: None,
            ptt_timeout,
            input_seq: 0,
        }
    }

    pub fn set_muted(&mut self, muted: bool) {
        self.muted = muted;
    }

    pub fn set_deafened(&mut self, deafened: bool) {
        self.deafened = deafened;
    }

    pub fn set_ptt_enabled(&mut self, enabled: bool) {
        self.ptt_enabled = enabled;
        if !enabled {
            self.ptt_pressed = false;
            self.ptt_pressed_at = None;
        }
    }

    /// Pressiona/solta PTT com sequência de input (watchdog).
    pub fn set_ptt_pressed(&mut self, pressed: bool, input_seq: u64) {
        // Sequência antiga é rejeitada (stale input).
        if input_seq < self.input_seq {
            return;
        }
        self.input_seq = input_seq;
        self.ptt_pressed = pressed;
        self.ptt_pressed_at = pressed.then(Instant::now);
    }

    /// Expira PTT órfão (watchdog). Retorna `true` se expirou agora.
    pub fn expire_stale_ptt(&mut self) -> bool {
        if self.ptt_pressed
            && let Some(at) = self.ptt_pressed_at
            && at.elapsed() >= self.ptt_timeout
        {
            self.ptt_pressed = false;
            self.ptt_pressed_at = None;
            return true;
        }
        false
    }

    /// Reconnect: PTT volta solto, mute/deafen persistem (§29.1).
    pub fn on_reconnect(&mut self) {
        self.ptt_pressed = false;
        self.ptt_pressed_at = None;
    }

    /// Pode transmitir este epoch? Nenhum frame de epoch bloqueado entra
    /// no transporte (AC-07).
    pub fn may_transmit(&self) -> bool {
        if self.muted || self.deafened {
            return false;
        }
        if self.ptt_enabled && !self.ptt_pressed {
            return false;
        }
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fail_closed_by_default() {
        let latch = TxLatch::new(Duration::from_secs(5));
        assert!(!latch.may_transmit());
    }

    #[test]
    fn unmute_opens_and_deafen_blocks() {
        let mut latch = TxLatch::new(Duration::from_secs(5));
        latch.set_muted(false);
        assert!(latch.may_transmit());
        latch.set_deafened(true);
        assert!(!latch.may_transmit());
    }

    #[test]
    fn stale_ptt_expires_and_reconnect_releases() {
        let mut latch = TxLatch::new(Duration::from_millis(1));
        latch.set_muted(false);
        latch.set_ptt_enabled(true);
        latch.set_ptt_pressed(true, 7);
        assert!(latch.may_transmit());
        std::thread::sleep(Duration::from_millis(5));
        assert!(latch.expire_stale_ptt());
        assert!(!latch.may_transmit());
        // Rejeita sequência antiga.
        latch.set_ptt_pressed(true, 9);
        latch.on_reconnect();
        assert!(!latch.may_transmit());
        latch.set_ptt_pressed(false, 6); // stale: ignorado
        latch.set_muted(false);
        assert!(!latch.may_transmit()); // PTT ainda exigido, solto
    }
}
