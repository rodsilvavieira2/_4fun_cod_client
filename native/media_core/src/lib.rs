//! 4FunCode native media engine core.
//!
//! Plano: `4funcode-native-media-architecture` (§6). Rust concentra estado,
//! políticas, buffers e DSP próprio; C++ envolve LiveKit/APM. Este crate é
//! std-only no M1 para build offline determinístico.

pub mod api;
pub mod audio;
pub mod backends;
pub mod dsp;
pub mod engine;
pub mod mixer;
pub mod session;
pub mod telemetry;

pub mod errors;
pub use errors::{DspError, MediaError};
