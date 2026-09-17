# Post-cargo staging for the Windows plugin link.
#
# Background: the ort crate (onnxruntime) downloads its own prebuilt binaries
# into its private cargo cache dir (path contains a version hash — NOT
# stable), and only the .dll (never the .lib) is copied next to the cargo
# output via the `copy-dylibs` default feature. The MSVC plugin link needs an
# import lib, so this script:
#   1. locates onnxruntime.dll under the cargo target dir,
#   2. rebuilds an import lib from its exports with dumpbin.exe + lib.exe
#      (onnxruntime exports a plain C API, so a generated .def is exact),
#   3. copies both into STAGE_DIR for the plugin link + bundle.
# Fails loudly when anything is absent so CI reports a missing runtime
# instead of cryptic LNK2019s or a startup crash on user machines.
if(NOT DEFINED BRIDGE_DIR OR NOT DEFINED STAGE_DIR)
  message(FATAL_ERROR "stage_ort_windows.cmake needs BRIDGE_DIR + STAGE_DIR")
endif()
if(NOT DEFINED DUMPBIN_EXE OR NOT DEFINED LIB_EXE)
  message(FATAL_ERROR "stage_ort_windows.cmake needs DUMPBIN_EXE + LIB_EXE (MSVC tools)")
endif()

file(MAKE_DIRECTORY "${STAGE_DIR}")

# copy-dylibs drops the DLL at the profile root (target/release/); fall back
# to a recursive search for robustness against ort layout changes.
set(ORT_DLL "${BRIDGE_DIR}/target/release/onnxruntime.dll")
if(NOT EXISTS "${ORT_DLL}")
  file(GLOB_RECURSE CAND_DLL "${BRIDGE_DIR}/target/release/onnxruntime.dll")
  list(LENGTH CAND_DLL N_DLL)
  if(N_DLL EQUAL 0)
    message(FATAL_ERROR
      "onnxruntime.dll not found under ${BRIDGE_DIR}/target/release. "
      "The ort crate should have downloaded it during cargo build "
      "(copy-dylibs feature) - check cargo output above.")
  endif()
  list(GET CAND_DLL 0 ORT_DLL)
endif()
message(STATUS "fourfun: onnxruntime.dll = ${ORT_DLL}")

# Rebuild the import lib from the DLL exports.
execute_process(
  COMMAND "${DUMPBIN_EXE}" /exports "${ORT_DLL}"
  OUTPUT_FILE "${STAGE_DIR}/onnxruntime.exports.txt"
  RESULT_VARIABLE DUMP_RES
)
if(NOT DUMP_RES EQUAL 0)
  message(FATAL_ERROR "dumpbin /exports failed on ${ORT_DLL}")
endif()
file(STRINGS "${STAGE_DIR}/onnxruntime.exports.txt" EXP_LINES)
set(DEF_BODY "LIBRARY onnxruntime\nEXPORTS\n")
set(IN_TABLE FALSE)
foreach(LINE IN LISTS EXP_LINES)
  if(NOT IN_TABLE)
    if(LINE MATCHES "^ *ordinal +hint +RVA +name")
      set(IN_TABLE TRUE)
    endif()
  elseif(LINE MATCHES "^ *[0-9]+ +[0-9A-Fa-f]+ +[0-9A-Fa-f]+ +([A-Za-z0-9_]+)")
    # (No blank-line guard: dumpbin puts one between the header and the first
    # entry. The trailing Summary cannot match — section names start with '.',
    # which is outside [0-9A-Fa-f].)
    string(APPEND DEF_BODY "    ${CMAKE_MATCH_1}\n")
  endif()
endforeach()
file(WRITE "${STAGE_DIR}/onnxruntime.def" "${DEF_BODY}")
execute_process(
  COMMAND "${LIB_EXE}" /def:"${STAGE_DIR}/onnxruntime.def"
    /out:"${STAGE_DIR}/onnxruntime.lib" /machine:x64
  RESULT_VARIABLE LIB_RES
)
if(NOT LIB_RES EQUAL 0)
  message(FATAL_ERROR "lib.exe failed to build onnxruntime.lib from exports")
endif()
if(NOT EXISTS "${STAGE_DIR}/onnxruntime.lib")
  message(FATAL_ERROR "onnxruntime.lib was not produced in ${STAGE_DIR}")
endif()

file(COPY_FILE "${ORT_DLL}" "${STAGE_DIR}/onnxruntime.dll")
message(STATUS "fourfun: staged onnxruntime.dll + onnxruntime.lib in ${STAGE_DIR}")
