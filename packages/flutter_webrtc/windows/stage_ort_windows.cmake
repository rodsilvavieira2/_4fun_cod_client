# Post-cargo staging for the Windows plugin link.
# The ort crate downloads prebuilt onnxruntime binaries at cargo build time
# (shared DLL + import lib on MSVC). Unlike Linux — where onnxruntime ends
# up statically inside the Rust archive — the Windows plugin DLL must link
# the import lib AND ship the DLL next to the exe. This script runs at BUILD
# time (after cargo, via a custom command that DEPENDS on the .lib output),
# locates both files under the cargo target dir and copies them to STAGE_DIR.
# Fails loudly when absent so CI reports a missing runtime instead of
# cryptic LNK2019s or a startup crash on user machines.
if(NOT DEFINED BRIDGE_DIR OR NOT DEFINED STAGE_DIR)
  message(FATAL_ERROR "stage_ort_windows.cmake needs BRIDGE_DIR + STAGE_DIR")
endif()

file(MAKE_DIRECTORY "${STAGE_DIR}")

# ort-sys puts the prebuilts in its OUT_DIR (target/release/build/ort-sys-*)
# and cargo may also surface copies at target/release{,/deps}.
file(GLOB_RECURSE CAND_DLL
  "${BRIDGE_DIR}/target/release/onnxruntime.dll")
file(GLOB_RECURSE CAND_LIB
  "${BRIDGE_DIR}/target/release/onnxruntime.lib")

list(LENGTH CAND_DLL N_DLL)
list(LENGTH CAND_LIB N_LIB)
if(N_DLL EQUAL 0 OR N_LIB EQUAL 0)
  message(FATAL_ERROR
    "onnxruntime binaries not found under ${BRIDGE_DIR}/target/release "
    "(dll=${N_DLL} lib=${N_LIB}). The ort crate should have downloaded them "
    "during cargo build — check cargo/build.rs output above.")
endif()
list(GET CAND_DLL 0 ORT_DLL)
list(GET CAND_LIB 0 ORT_LIB)
message(STATUS "fourfun: staging ${ORT_DLL} + ${ORT_LIB}")

file(COPY_FILE "${ORT_DLL}" "${STAGE_DIR}/onnxruntime.dll")
file(COPY_FILE "${ORT_LIB}" "${STAGE_DIR}/onnxruntime.lib")
