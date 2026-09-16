//! Build script: guarantees the DPDFNet ONNX model exists at compile time.
//! Resolution order:
//!   1. `$FOURFUN_DPDFNET_MODEL` (explicit local path, e.g. lab cache)
//!   2. `model/dpdfnet2_48khz_hr.onnx` next to this script (vendored)
//!   3. Download from the sherpa-onnx release (needs network once)
//! The resolved path is exported as `FOURFUN_DPDFNET_PATH` for `include_bytes!`.

use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

const MODEL_FILENAME: &str = "dpdfnet2_48khz_hr.onnx";
const MODEL_URL: &str = "https://github.com/k2-fsa/sherpa-onnx/releases/download/speech-enhancement-models/dpdfnet2_48khz_hr.onnx";
// onnxruntime rejects truncated files; the full export is ~10 MB.
const MIN_MODEL_BYTES: u64 = 9_000_000;

fn main() {
    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let vendored = manifest_dir.join("model").join(MODEL_FILENAME);

    let resolved: PathBuf = if let Ok(explicit) = env::var("FOURFUN_DPDFNET_MODEL") {
        PathBuf::from(explicit)
    } else if vendored.is_file() {
        vendored
    } else {
        if let Some(parent) = vendored.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let status = Command::new("curl")
            .args(["-sSL", "-o"])
            .arg(&vendored)
            .arg(MODEL_URL)
            .status()
            .expect("curl is required to fetch the DPDFNet model on first build");
        assert!(status.success(), "failed to download {MODEL_URL}");
        vendored
    };

    let bytes = fs::metadata(&resolved)
        .unwrap_or_else(|_| panic!("DPDFNet model missing at {}", resolved.display()))
        .len();
    assert!(
        bytes >= MIN_MODEL_BYTES,
        "DPDFNet model at {} looks truncated ({bytes} bytes)",
        resolved.display()
    );

    println!("cargo:rerun-if-env-changed=FOURFUN_DPDFNET_MODEL");
    println!("cargo:rerun-if-changed=model/{}", MODEL_FILENAME);
    println!(
        "cargo:rustc-env=FOURFUN_DPDFNET_PATH={}",
        resolved.display()
    );
}
