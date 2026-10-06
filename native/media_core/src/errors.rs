//! Erros do engine (§25 do plano). Variantes estáveis; nunca vazar PCM,
//! tokens ou paths em mensagens.

use std::fmt;

/// Erro de mídia de alto nível, mapeável para status ABI estável.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MediaError {
    InvalidFormat(String),
    DeviceUnavailable(String),
    DspUnavailable(String),
    InvalidHandle,
    AbiMismatch,
    Busy,
    Unauthorized,
    PermissionDenied,
    UnsupportedFormat(String),
    Internal(String),
}

impl fmt::Display for MediaError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidFormat(m) => write!(f, "invalid format: {m}"),
            Self::DeviceUnavailable(m) => write!(f, "device unavailable: {m}"),
            Self::DspUnavailable(m) => write!(f, "dsp unavailable: {m}"),
            Self::InvalidHandle => write!(f, "invalid engine handle"),
            Self::AbiMismatch => write!(f, "abi mismatch"),
            Self::Busy => write!(f, "command queue busy"),
            Self::Unauthorized => write!(f, "unauthorized"),
            Self::PermissionDenied => write!(f, "permission denied"),
            Self::UnsupportedFormat(m) => write!(f, "unsupported format: {m}"),
            Self::Internal(m) => write!(f, "internal: {m}"),
        }
    }
}

impl std::error::Error for MediaError {}

/// Erro de DSP (deadline, frame inválido, modelo ausente).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DspError {
    InvalidFrame(String),
    ModelMissing(String),
    DeadlineExceeded,
    Bypassed(String),
}

impl fmt::Display for DspError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidFrame(m) => write!(f, "invalid frame: {m}"),
            Self::ModelMissing(m) => write!(f, "model missing: {m}"),
            Self::DeadlineExceeded => write!(f, "dsp deadline exceeded"),
            Self::Bypassed(m) => write!(f, "dsp bypassed: {m}"),
        }
    }
}

impl std::error::Error for DspError {}
