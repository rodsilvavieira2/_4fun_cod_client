//! Eventos engine -> Dart (§23): envelope versionado com geração,
//! sequência e revisão de estado. `monotonic_ns` é clock local do engine.

#[derive(Debug, Clone)]
pub struct NativeEvent {
    pub schema_version: u32,
    pub engine_id: u64,
    pub generation: u64,
    pub event_seq: u64,
    pub state_revision: u64,
    pub kind: EventKind,
    pub request_id: Option<String>,
}

#[derive(Debug, Clone)]
pub enum EventKind {
    SnapshotSync,
    CommandApplied { ticket: u64, error: Option<String> },
    DeviceSwitchCompleted { direction: String, gap_ms: u64 },
    DspDegraded { effective: String, reason: String },
    PttExpired,
    MetricsTick,
}

impl NativeEvent {
    pub fn kind_name(&self) -> &'static str {
        match &self.kind {
            EventKind::SnapshotSync => "snapshot_sync",
            EventKind::CommandApplied { .. } => "command_applied",
            EventKind::DeviceSwitchCompleted { .. } => {
                "device_switch_completed"
            }
            EventKind::DspDegraded { .. } => "dsp_degraded",
            EventKind::PttExpired => "ptt_expired",
            EventKind::MetricsTick => "metrics_tick",
        }
    }
}
