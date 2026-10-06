//! Ator de controle (§21): serializa comandos, aplica em fronteira de
//! bloco, emite eventos. Estado de engine separado de sessão/dispositivo.

use crate::audio::clock::SessionClock;
use crate::dsp::fallback::{DspFallback, DspProfile};
use crate::engine::commands::{
    AppliedResult, CommandContext, CommandReceipt, MediaCommand,
    QueuedCommand, validate_command,
};
use crate::engine::events::{EventKind, NativeEvent};
use crate::engine::snapshot::{Capabilities, EngineSnapshot};
use crate::errors::MediaError;
use crate::mixer::{AudioSourceKind, Mixer};
use crate::session::{DesiredState, TxLatch};
use crate::telemetry::Counters;
use std::collections::{HashMap, HashSet, VecDeque};
use std::time::Duration;

/// Capacidade da fila de comandos (§9.2).
pub const COMMAND_QUEUE_CAPACITY: usize = 128;
const SCHEMA_VERSION: u32 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
// Transições completas (Starting/Degraded/Stopping) chegam com o streaming
// de dispositivos/DSP no M1; a máquina de estados segue o §21 do plano.
#[allow(dead_code)]
enum EngineLifecycle {
    Ready,
    Starting,
    Running,
    Degraded,
    Stopping,
    Disposed,
}

pub struct Engine {
    id: u64,
    incarnation: u64,
    generation: u64,
    revision: u64,
    lifecycle: EngineLifecycle,
    desired: DesiredState,
    latch: TxLatch,
    dsp: DspFallback,
    mixer: Mixer,
    clock: SessionClock,
    counters: Counters,
    queue: VecDeque<QueuedCommand>,
    seen_requests: HashSet<(u64, String)>,
    next_ticket: u64,
    next_seq: u64,
    pending_events: VecDeque<NativeEvent>,
    flags: HashMap<String, bool>,
    disposed: bool,
}

impl Engine {
    pub fn create(
        id: u64,
        incarnation: u64,
        flags: HashMap<String, bool>,
    ) -> Self {
        Self {
            id,
            incarnation,
            generation: 0,
            revision: 0,
            lifecycle: EngineLifecycle::Ready,
            desired: DesiredState::default(),
            latch: TxLatch::new(Duration::from_secs(5)),
            dsp: DspFallback::new(DspProfile::Basic),
            mixer: Mixer::new(),
            clock: SessionClock::new(0),
            counters: Counters::default(),
            queue: VecDeque::with_capacity(COMMAND_QUEUE_CAPACITY),
            seen_requests: HashSet::new(),
            next_ticket: 1,
            next_seq: 1,
            pending_events: VecDeque::new(),
            flags,
            disposed: false,
        }
    }

    pub fn capabilities(&self) -> Capabilities {
        Capabilities {
            abi_version: crate::api::abi::ABI_VERSION,
            build_id: env!("CARGO_PKG_VERSION").to_string(),
            cpal_host: crate::backends::effective_host_name().to_string(),
            studio_available: false,
            max_tracks: 32,
        }
    }

    /// Enfileira comando. Request ID deduplica por geração (§22.5).
    pub fn submit(
        &mut self,
        ctx: CommandContext,
        cmd: MediaCommand,
    ) -> Result<CommandReceipt, MediaError> {
        if self.disposed {
            return Err(MediaError::InvalidHandle);
        }
        if ctx.generation != self.generation
            && !matches!(cmd, MediaCommand::Join { .. })
        {
            return Err(MediaError::InvalidFormat(format!(
                "stale generation: got {}, current {}",
                ctx.generation, self.generation
            )));
        }
        if let Some(expected) = ctx.expected_revision
            && expected != self.revision
        {
            return Err(MediaError::InvalidFormat(format!(
                "stale revision: got {expected}, current {}",
                self.revision
            )));
        }
        validate_command(&cmd)?;
        if !self.seen_requests.insert((ctx.generation, ctx.request_id.clone()))
        {
            // Dedup: reemite recibo sem reenfileirar.
            return Ok(CommandReceipt {
                request_id: ctx.request_id,
                accepted: true,
                ticket: 0,
            });
        }
        if self.queue.len() >= COMMAND_QUEUE_CAPACITY {
            return Err(MediaError::Busy);
        }
        let ticket = self.next_ticket;
        self.next_ticket += 1;
        let request_id = ctx.request_id.clone();
        self.queue.push_back(QueuedCommand { ctx, cmd });
        Ok(CommandReceipt {
            request_id,
            accepted: true,
            ticket,
        })
    }

    /// Drena a fila aplicando comandos; retorna resultados aplicados.
    pub fn pump(&mut self) -> Vec<AppliedResult> {
        let mut results = Vec::new();
        while let Some(q) = self.queue.pop_front() {
            let ticket = self.next_ticket;
            self.next_ticket += 1;
            let error = self.apply(&q.ctx, &q.cmd).err().map(|e| e.to_string());
            if error.is_none() {
                self.revision += 1;
            }
            let revision = self.revision;
            self.emit(EventKind::CommandApplied {
                ticket,
                error: error.clone(),
            });
            results.push(AppliedResult {
                request_id: q.ctx.request_id,
                ticket,
                state_revision: revision,
                error,
            });
        }
        results
    }

    fn apply(
        &mut self,
        _ctx: &CommandContext,
        cmd: &MediaCommand,
    ) -> Result<(), MediaError> {
        match cmd {
            MediaCommand::Join { start_muted, .. } => {
                self.generation += 1;
                self.clock = SessionClock::new(self.generation);
                self.lifecycle = EngineLifecycle::Running;
                self.desired.muted = *start_muted;
                self.latch.set_muted(*start_muted);
                // Reconnect semantics: PTT volta solto.
                self.latch.on_reconnect();
            }
            MediaCommand::Leave => {
                self.lifecycle = EngineLifecycle::Ready;
                self.queue.clear();
            }
            MediaCommand::SetMute { muted } => {
                self.desired.muted = *muted;
                self.latch.set_muted(*muted);
            }
            MediaCommand::SetDeafen { deafened } => {
                self.desired.deafened = *deafened;
                self.latch.set_deafened(*deafened);
            }
            MediaCommand::SetPttMode { enabled } => {
                self.desired.ptt_enabled = *enabled;
                self.latch.set_ptt_enabled(*enabled);
            }
            MediaCommand::SetPttPressed { pressed, input_seq } => {
                self.latch.set_ptt_pressed(*pressed, *input_seq);
            }
            MediaCommand::SelectInput { selection } => {
                self.desired.input = selection.clone();
                self.clock.next_epoch();
            }
            MediaCommand::SelectOutput { selection } => {
                self.desired.output = selection.clone();
            }
            MediaCommand::SetInputGain { linear } => {
                self.desired.input_gain = linear.clamp(0.0, 1.0);
            }
            MediaCommand::SetOutputGain { linear } => {
                self.desired.output_gain = linear.clamp(0.0, 2.0);
                self.mixer.set_master(self.desired.output_gain);
            }
            MediaCommand::SetUserVolume { identity, source, linear } => {
                let source: AudioSourceKind = *source;
                self.desired
                    .user_volumes
                    .insert((identity.clone(), source), linear.clamp(0.0, 2.0));
                self.mixer.set_volume(identity, source, *linear);
            }
            MediaCommand::ConfigureDsp { profile } => {
                self.dsp.request(*profile, false);
            }
        }
        Ok(())
    }

    fn emit(&mut self, kind: EventKind) {
        let seq = self.next_seq;
        self.next_seq += 1;
        self.pending_events.push_back(NativeEvent {
            schema_version: SCHEMA_VERSION,
            engine_id: self.id,
            generation: self.generation,
            event_seq: seq,
            state_revision: self.revision,
            kind,
            request_id: None,
        });
        // Backpressure: eventos antigos de métricas caem primeiro.
        while self.pending_events.len() > 512 {
            self.pending_events.pop_front();
        }
    }

    pub fn poll_event(&mut self) -> Option<NativeEvent> {
        // Expira PTT órfão no poll (watchdog).
        if self.latch.expire_stale_ptt() {
            let seq = self.next_seq;
            self.next_seq += 1;
            return Some(NativeEvent {
                schema_version: SCHEMA_VERSION,
                engine_id: self.id,
                generation: self.generation,
                event_seq: seq,
                state_revision: self.revision,
                kind: EventKind::PttExpired,
                request_id: None,
            });
        }
        self.pending_events.pop_front()
    }

    pub fn snapshot(&self) -> EngineSnapshot {
        EngineSnapshot {
            engine_id: self.id,
            incarnation: self.incarnation,
            generation: self.generation,
            state_revision: self.revision,
            muted: self.desired.muted,
            deafened: self.desired.deafened,
            ptt_enabled: self.desired.ptt_enabled,
            may_transmit: self.latch.may_transmit(),
            input: self.desired.input.clone(),
            output: self.desired.output.clone(),
            input_gain: self.desired.input_gain,
            output_gain: self.desired.output_gain,
            user_volumes: self.desired.user_volumes.clone(),
            requested_dsp: self.dsp.requested(),
            effective_dsp: self.dsp.effective(),
            dsp_reason: self.dsp.reason().map(str::to_string),
            device_epoch: self.clock.device_epoch(),
            sample_index: self.clock.sample_index(),
            metrics: self.counters.snapshot(),
            flags: self.flags.clone(),
        }
    }

    /// Fechamento TX mínimo e seguro (§22.5); idempotente.
    pub fn close_tx(&mut self) {
        self.latch.set_muted(true);
        self.queue.clear();
    }

    /// Destroy idempotente por handle (§22.5).
    pub fn dispose(&mut self) {
        if self.disposed {
            return;
        }
        self.close_tx();
        self.lifecycle = EngineLifecycle::Disposed;
        self.disposed = true;
    }

    pub fn is_disposed(&self) -> bool {
        self.disposed
    }

    pub fn id(&self) -> u64 {
        self.id
    }

    pub fn incarnation(&self) -> u64 {
        self.incarnation
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::DeviceSelection;

    fn engine() -> Engine {
        Engine::create(7, 1, HashMap::new())
    }

    fn ctx(id: &str, generation: u64) -> CommandContext {
        CommandContext::new(id, generation)
    }

    #[test]
    fn join_opens_generation_and_mute_blocks_tx() {
        let mut e = engine();
        e.submit(ctx("j1", 0), MediaCommand::Join {
            channel_id: "ch".to_string(),
            start_muted: true,
        })
        .unwrap();
        e.pump();
        let snap = e.snapshot();
        assert_eq!(snap.generation, 1);
        assert!(!snap.may_transmit);
        e.submit(ctx("u1", 1), MediaCommand::SetMute { muted: false })
            .unwrap();
        e.pump();
        assert!(e.snapshot().may_transmit);
    }

    #[test]
    fn stale_generation_rejected_and_dedup_safe() {
        let mut e = engine();
        e.submit(ctx("j1", 0), MediaCommand::Join {
            channel_id: "ch".to_string(),
            start_muted: false,
        })
        .unwrap();
        e.pump();
        assert!(e
            .submit(ctx("old", 0), MediaCommand::SetMute { muted: true })
            .is_err());
        let r1 = e
            .submit(ctx("dup", 1), MediaCommand::SetMute { muted: true })
            .unwrap();
        assert!(r1.accepted);
        // Dedup: mesmo request id + geração não reenfileira.
        let r2 = e
            .submit(ctx("dup", 1), MediaCommand::SetMute { muted: true })
            .unwrap();
        assert!(r2.accepted);
        e.pump();
        assert!(e.snapshot().muted);
    }

    #[test]
    fn full_mute_deafen_ptt_flow() {
        let mut e = engine();
        e.submit(ctx("j", 0), MediaCommand::Join {
            channel_id: "ch".to_string(),
            start_muted: false,
        })
        .unwrap();
        e.pump();
        assert!(e.snapshot().may_transmit);
        for (i, cmd) in [
            MediaCommand::SetPttMode { enabled: true },
            MediaCommand::SetPttPressed { pressed: true, input_seq: 1 },
        ]
        .into_iter()
        .enumerate()
        {
            e.submit(ctx(&format!("p{i}"), 1), cmd).unwrap();
        }
        e.pump();
        assert!(e.snapshot().may_transmit);
        e.submit(ctx("d", 1), MediaCommand::SetDeafen { deafened: true })
            .unwrap();
        e.pump();
        assert!(!e.snapshot().may_transmit);
    }

    #[test]
    fn dispose_is_idempotent() {
        let mut e = engine();
        e.dispose();
        e.dispose();
        assert!(e.is_disposed());
        assert!(e
            .submit(ctx("x", 0), MediaCommand::Leave)
            .is_err());
    }

    #[test]
    fn command_applied_events_flow() {
        let mut e = engine();
        e.submit(ctx("j", 0), MediaCommand::Join {
            channel_id: "ch".to_string(),
            start_muted: true,
        })
        .unwrap();
        let results = e.pump();
        assert_eq!(results.len(), 1);
        assert!(results[0].error.is_none());
        assert!(e.poll_event().is_some());
    }

    #[test]
    fn select_input_bumps_epoch() {
        let mut e = engine();
        e.submit(ctx("j", 0), MediaCommand::Join {
            channel_id: "ch".to_string(),
            start_muted: true,
        })
        .unwrap();
        e.pump();
        e.submit(ctx("s", 1), MediaCommand::SelectInput {
            selection: DeviceSelection::Pinned("mic-1".to_string()),
        })
        .unwrap();
        e.pump();
        assert_eq!(e.snapshot().device_epoch, 1);
    }
}
