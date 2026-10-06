//! Comandos de controle (§22.2): fila bounded, dedup por request ID +
//! geração, setters last-wins, join/leave serializados.

use crate::dsp::fallback::DspProfile;
use crate::errors::MediaError;
use crate::mixer::AudioSourceKind;
use crate::session::DeviceSelection;

/// Contexto de comando: geração protege a sessão; revisão esperada
/// opcional para mutações não comutativas.
#[derive(Debug, Clone)]
pub struct CommandContext {
    pub request_id: String,
    pub generation: u64,
    pub expected_revision: Option<u64>,
}

impl CommandContext {
    pub fn new(request_id: impl Into<String>, generation: u64) -> Self {
        Self {
            request_id: request_id.into(),
            generation,
            expected_revision: None,
        }
    }
}

#[derive(Debug, Clone)]
pub enum MediaCommand {
    Join { channel_id: String, start_muted: bool },
    Leave,
    SetMute { muted: bool },
    SetDeafen { deafened: bool },
    SetPttMode { enabled: bool },
    SetPttPressed { pressed: bool, input_seq: u64 },
    SelectInput { selection: DeviceSelection },
    SelectOutput { selection: DeviceSelection },
    SetInputGain { linear: f32 },
    SetOutputGain { linear: f32 },
    SetUserVolume {
        identity: String,
        source: AudioSourceKind,
        linear: f32,
    },
    ConfigureDsp { profile: DspProfile },
}

#[derive(Debug, Clone)]
pub struct QueuedCommand {
    pub ctx: CommandContext,
    pub cmd: MediaCommand,
}

/// Recibo: aceito na fila NÃO significa aplicado (§22.2).
#[derive(Debug, Clone)]
pub struct CommandReceipt {
    pub request_id: String,
    pub accepted: bool,
    pub ticket: u64,
}

/// Resultado aplicado (via evento `command_applied`).
#[derive(Debug, Clone)]
pub struct AppliedResult {
    pub request_id: String,
    pub ticket: u64,
    pub state_revision: u64,
    pub error: Option<String>,
}

pub(crate) fn validate_command(
    cmd: &MediaCommand,
) -> Result<(), MediaError> {
    match cmd {
        MediaCommand::SetInputGain { linear }
        | MediaCommand::SetOutputGain { linear } => {
            if !linear.is_finite() {
                return Err(MediaError::InvalidFormat(
                    "gain must be finite".to_string(),
                ));
            }
            Ok(())
        }
        MediaCommand::SetUserVolume { identity, linear, .. } => {
            if identity.is_empty() || identity.len() > 256 {
                return Err(MediaError::InvalidFormat(
                    "identity length out of range".to_string(),
                ));
            }
            if !linear.is_finite() {
                return Err(MediaError::InvalidFormat(
                    "gain must be finite".to_string(),
                ));
            }
            Ok(())
        }
        MediaCommand::Join { channel_id, .. } => {
            if channel_id.is_empty() || channel_id.len() > 256 {
                return Err(MediaError::InvalidFormat(
                    "channel_id length out of range".to_string(),
                ));
            }
            Ok(())
        }
        _ => Ok(()),
    }
}
