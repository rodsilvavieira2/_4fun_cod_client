//! Backends de I/O: simulado (testes) + stub CPAL (M1).

pub mod cpal_stub;
pub mod simulated;

use crate::errors::MediaError;

#[derive(Debug, Clone)]
pub struct DeviceDescriptor {
    pub id: String,
    pub label: String,
    pub is_input: bool,
    pub sample_rates: Vec<u32>,
    pub channels: Vec<u16>,
}

pub trait AudioBackend {
    fn name(&self) -> &'static str;
    fn enumerate(&self) -> Result<Vec<DeviceDescriptor>, MediaError>;
}

/// Nome do host efetivo reportado em capabilities. CPAL real entra no M1
/// após o spike; até lá, o valor honesto é `simulated`.
pub fn effective_host_name() -> &'static str {
    "simulated"
}
