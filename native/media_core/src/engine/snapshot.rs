//! Snapshot completo (§21): recupera gaps de eventos e alimenta UI.
//! Token nunca aparece aqui (§27).

use crate::dsp::fallback::{DspProfile, EffectiveDspMode};
use crate::mixer::AudioSourceKind;
use crate::session::DeviceSelection;
use crate::telemetry::MetricsSnapshot;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct Capabilities {
    pub abi_version: u32,
    pub build_id: String,
    pub cpal_host: String,
    pub studio_available: bool,
    pub max_tracks: usize,
}

#[derive(Debug, Clone)]
pub struct EngineSnapshot {
    pub engine_id: u64,
    pub incarnation: u64,
    pub generation: u64,
    pub state_revision: u64,
    pub muted: bool,
    pub deafened: bool,
    pub ptt_enabled: bool,
    pub may_transmit: bool,
    pub input: DeviceSelection,
    pub output: DeviceSelection,
    pub input_gain: f32,
    pub output_gain: f32,
    pub user_volumes: HashMap<(String, AudioSourceKind), f32>,
    pub requested_dsp: DspProfile,
    pub effective_dsp: EffectiveDspMode,
    pub dsp_reason: Option<String>,
    pub device_epoch: u64,
    pub sample_index: u64,
    pub metrics: MetricsSnapshot,
    /// Flags efetivas resolvidas (§29.2) — sem segredos.
    pub flags: HashMap<String, bool>,
}
