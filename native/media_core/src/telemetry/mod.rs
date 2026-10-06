//! Telemetria (§26): contadores atômicos no caminho de áudio,
//! agregação fora dele. Sem PCM/tokens em logs.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

#[derive(Debug, Default, Clone)]
pub struct Counters {
    pub capture_callbacks: Arc<AtomicU64>,
    pub capture_samples: Arc<AtomicU64>,
    pub processed_hops: Arc<AtomicU64>,
    pub bypassed_hops: Arc<AtomicU64>,
    pub deadline_misses: Arc<AtomicU64>,
    pub dropped_frames: Arc<AtomicU64>,
    pub underruns: Arc<AtomicU64>,
    pub sanitized_samples: Arc<AtomicU64>,
}

impl Counters {
    pub fn snapshot(&self) -> MetricsSnapshot {
        MetricsSnapshot {
            capture_callbacks: self.capture_callbacks.load(Ordering::Relaxed),
            capture_samples: self.capture_samples.load(Ordering::Relaxed),
            processed_hops: self.processed_hops.load(Ordering::Relaxed),
            bypassed_hops: self.bypassed_hops.load(Ordering::Relaxed),
            deadline_misses: self.deadline_misses.load(Ordering::Relaxed),
            dropped_frames: self.dropped_frames.load(Ordering::Relaxed),
            underruns: self.underruns.load(Ordering::Relaxed),
            sanitized_samples: self
                .sanitized_samples
                .load(Ordering::Relaxed),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MetricsSnapshot {
    pub capture_callbacks: u64,
    pub capture_samples: u64,
    pub processed_hops: u64,
    pub bypassed_hops: u64,
    pub deadline_misses: u64,
    pub dropped_frames: u64,
    pub underruns: u64,
    pub sanitized_samples: u64,
}
