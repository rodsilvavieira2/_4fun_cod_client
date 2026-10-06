//! ABI C v1 (§22.4): versionamento, status estáveis e limites.
//! PCM nunca trafega por JSON; comandos têm teto inicial de 64 KiB.

/// Versão da ABI de controle.
pub const ABI_VERSION: u32 = 1;
/// Teto inicial do JSON de comando (definido no contrato).
pub const MAX_COMMAND_JSON_BYTES: usize = 64 * 1024;

/// Status ABI estável (0 = OK).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum AbiStatus {
    Ok = 0,
    InvalidArgs = 1,
    AbiMismatch = 2,
    InvalidHandle = 3,
    Busy = 4,
    NoEvent = 5,
    Unauthorized = 6,
    Internal = 7,
}

impl AbiStatus {
    pub fn code(self) -> u32 {
        self as u32
    }
}

impl From<&crate::errors::MediaError> for AbiStatus {
    fn from(e: &crate::errors::MediaError) -> Self {
        use crate::errors::MediaError as E;
        match e {
            E::InvalidFormat(_)
            | E::UnsupportedFormat(_)
            | E::PermissionDenied => Self::InvalidArgs,
            E::AbiMismatch => Self::AbiMismatch,
            E::InvalidHandle => Self::InvalidHandle,
            E::Busy => Self::Busy,
            E::Unauthorized => Self::Unauthorized,
            _ => Self::Internal,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ok_is_zero_and_no_event_distinct_from_error() {
        assert_eq!(AbiStatus::Ok.code(), 0);
        assert_ne!(AbiStatus::NoEvent, AbiStatus::Ok);
    }
}
