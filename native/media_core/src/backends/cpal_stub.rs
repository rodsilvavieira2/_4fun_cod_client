//! Stub CPAL (M1): documenta o wiring planejado sem puxar a
//! dependência antes do spike M0 fechar o pin (versão/features por target).
//!
//! Plano §8: CPAL como abstração, PipeWire no Linux (feature explícita),
//! WASAPI shared/event-driven no Windows. Quando o pin fechar:
//! 1. adicionar `cpal = { version = "=0.18.x", ... }` ao Cargo.toml;
//! 2. implementar `CpalBackend` atrás de `AudioBackend`;
//! 3. reportar host efetivo em capabilities (trocar `effective_host_name`).

use crate::backends::{AudioBackend, DeviceDescriptor};
use crate::errors::MediaError;

pub struct CpalBackendStub;

impl AudioBackend for CpalBackendStub {
    fn name(&self) -> &'static str {
        "cpal-stub"
    }

    fn enumerate(&self) -> Result<Vec<DeviceDescriptor>, MediaError> {
        Err(MediaError::DspUnavailable(
            "CPAL ainda não validado no spike M0; use simulated".to_string(),
        ))
    }
}
