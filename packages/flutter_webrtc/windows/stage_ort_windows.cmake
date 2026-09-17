# Post-cargo staging for the Windows plugin link.
#
# Background: on Windows the ort crate (onnxruntime) links STATICALLY — the
# pyke dist (x86_64-pc-windows-msvc+directml) ships a 341MB static
# `onnxruntime.lib` (verified: full archive, zero refs to any DLL) which ends
# up inside our bridge .lib, exactly like Linux. There is NO onnxruntime.dll.
#
# What the FINAL plugin link still needs (per ort-sys build/static_link):
#   - DX12 system libs: dxguid, DXCORE, DXGI, D3D12 (Windows SDK, linked by
#     name in CMakeLists — always present with MSVC).
#   - DirectML import lib: the dist ships DirectML.dll but NO DirectML.lib,
#     so we generate the import lib with dumpbin+lib.exe (same trick works
#     for any DLL: exports -> .def -> import .lib).
#   - DirectML.dll at RUNTIME next to the plugin (shipped via bundled libs).
#
# This script:
#  1. locates DirectML.dll — first in the cargo profile root (ort's
#     copy-dylibs), then via the exact link-search dir recorded in the
#     ort-sys build output (target/release/build/ort-sys-*/output, points
#     into the %LOCALAPPDATA%\ort.pyke.io\dfbin download cache), then a
#     recursive search of the dfbin cache;
#  2. dumps its exports with dumpbin and builds an import lib with lib.exe.
#
# Inputs (-D): BRIDGE_DIR, STAGE_DIR, STAGE_DLL, STAGE_LIB, DUMPBIN_EXE, LIB_EXE.

# (Macro args carry Windows backslash paths; NEW preserves them verbatim
# instead of reading \U \t etc. as escape sequences.)
if(POLICY CMP0219)
  cmake_policy(SET CMP0219 NEW)
endif()

foreach(VAR IN ITEMS BRIDGE_DIR STAGE_DIR STAGE_DLL STAGE_LIB DUMPBIN_EXE LIB_EXE)
  if(NOT DEFINED ${VAR})
    message(FATAL_ERROR "stage_ort_windows.cmake: -D${VAR}=... is required")
  endif()
  # (pwsh callers may pass -D values wrapped in literal quotes; the MSVC
  # tools then see the quotes as part of the filename -> LNK1104.)
  string(REGEX REPLACE "^\"(.*)\"$" "\\1" ${VAR} "${${VAR}}")
endforeach()

# 1. locate DirectML.dll (see header for source order). Empty files are
#      rejected: ort's copy-dylibs has been observed leaving a 0-byte
#      DirectML.dll at the profile root (dumpbin then fails on it) while the
#      dfbin original is intact.
macro(_fourfun_take_dll CAND)
  file(SIZE "${CAND}" _SZ)
  if(_SZ GREATER 0)
    set(SRC_DLL "${CAND}")
  endif()
endmacro()
set(SRC_DLL "")
file(GLOB CAND_DLL "${BRIDGE_DIR}/target/release/DirectML.dll")
foreach(C IN LISTS CAND_DLL)
  if(NOT SRC_DLL)
    _fourfun_take_dll("${C}")
  endif()
endforeach()
if(NOT SRC_DLL)
  file(GLOB ORT_BUILD_OUT "${BRIDGE_DIR}/target/release/build/ort-sys-*/output")
  foreach(OUT_FILE IN LISTS ORT_BUILD_OUT)
    file(STRINGS "${OUT_FILE}" OUT_LINES REGEX "rustc-link-search=native=")
    foreach(L IN LISTS OUT_LINES)
      if(L MATCHES "rustc-link-search=native=(.*)")
        set(LINK_DIR "${CMAKE_MATCH_1}")
        # (cargo may emit the line with trailing whitespace/control chars)
        string(STRIP "${LINK_DIR}" LINK_DIR)
        if(EXISTS "${LINK_DIR}/DirectML.dll")
          _fourfun_take_dll("${LINK_DIR}/DirectML.dll")
          if(SRC_DLL)
            break()
          endif()
        endif()
      endif()
    endforeach()
    if(SRC_DLL)
      break()
    endif()
  endforeach()
endif()
if(NOT SRC_DLL)
  file(GLOB_RECURSE CAND_DLL "$ENV{LOCALAPPDATA}/ort.pyke.io/dfbin/*/DirectML.dll")
  foreach(C IN LISTS CAND_DLL)
    if(NOT SRC_DLL)
      _fourfun_take_dll("${C}")
    endif()
  endforeach()
endif()
if(NOT SRC_DLL)
  message(FATAL_ERROR
    "DirectML.dll not found: nothing in ${BRIDGE_DIR}/target/release, "
    "no link-search dir in ort-sys build output, nothing in "
    "$ENV{LOCALAPPDATA}/ort.pyke.io/dfbin. Check cargo output above.")
endif()

file(MAKE_DIRECTORY "${STAGE_DIR}")
file(COPY_FILE "${SRC_DLL}" "${STAGE_DLL}"
     ONLY_IF_DIFFERENT)

# 2. generate the import lib (dumpbin exports -> .def -> lib.exe).
execute_process(
  COMMAND "${DUMPBIN_EXE}" /EXPORTS "${SRC_DLL}"
  OUTPUT_FILE "${STAGE_DIR}/directml.exports.txt"
  ERROR_VARIABLE DUMP_ERR
  RESULT_VARIABLE DUMP_RES
)
if(NOT DUMP_RES EQUAL 0)
  message(FATAL_ERROR "dumpbin /EXPORTS failed for ${SRC_DLL}: ${DUMP_ERR}")
endif()

file(STRINGS "${STAGE_DIR}/directml.exports.txt" EXP_LINES)
set(DEF_BODY "LIBRARY DirectML\nEXPORTS\n")
set(IN_TABLE FALSE)
foreach(LINE IN LISTS EXP_LINES)
  if(NOT IN_TABLE)
    if(LINE MATCHES "ordinal.*hint.*RVA.*name")
      set(IN_TABLE TRUE)
    endif()
  elseif(LINE MATCHES "^ *[0-9]+ +[0-9A-Fa-f]+ +[0-9A-Fa-f]+ +([A-Za-z0-9_]+)")
    # (No blank-line guard: dumpbin puts one between the header and the first
    # entry. The trailing Summary cannot match: it has no ordinal columns.)
    string(APPEND DEF_BODY "    ${CMAKE_MATCH_1}\n")
  endif()
endforeach()
file(WRITE "${STAGE_DIR}/directml.def" "${DEF_BODY}")

execute_process(
  COMMAND "${LIB_EXE}" /DEF:${STAGE_DIR}/directml.def
    /OUT:${STAGE_LIB} /MACHINE:X64
  RESULT_VARIABLE LIB_RES
)
if(NOT LIB_RES EQUAL 0)
  message(FATAL_ERROR "lib.exe failed generating ${STAGE_LIB}")
endif()
