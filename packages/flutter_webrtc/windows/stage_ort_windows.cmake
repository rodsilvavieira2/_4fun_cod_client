# Post-cargo staging for the Windows plugin link.
#
# Background: the ort crate (onnxruntime) downloads its own prebuilt binaries
# into its private cargo cache dir (path contains a version hash — NOT
# stable), and only the .dll (never the .lib) is copied next to the cargo
# output via the `copy-dylibs` default feature. The MSVC plugin link needs an
# import lib, so this script:
# 1. locates onnxruntime.dll — deterministically first: the ort-sys build
#      script stdout (target/release/build/ort-sys-*/output) records the exact
#      `cargo:rustc-link-search=native=<dir>` the link used, and the DLL lives
#      there (the %LOCALAPPDATA%\ort.pyke.io\dfbin download cache). The
#      copy-dylibs profile-root copy is only a fallback: ort's copier uses a
#      non-recursive read_dir, so a dist with subdirs silently copies nothing
#      (observed on Windows: cargo Finished OK, no DLL in target/release).
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

# copy-dylibs drops the DLL at the profile root (target/release/) — but only
# when the dist layout is flat (its copier uses a non-recursive read_dir).
# Deterministic source first: the ort-sys build output records the exact
# link-search dir used for the link; the DLL is guaranteed to be there.
set(ORT_DLL "")
file(GLOB ORT_BUILD_OUT "${BRIDGE_DIR}/target/release/build/ort-sys-*/output")
foreach(OUT_FILE IN LISTS ORT_BUILD_OUT)
  file(STRINGS "${OUT_FILE}" OUT_LINES REGEX "rustc-link-search=native=")
  foreach(L IN LISTS OUT_LINES)
    if(L MATCHES "rustc-link-search=native=(.*)")
      set(LINK_DIR "${CMAKE_MATCH_1}")
      # (cargo may emit the line with trailing whitespace/control chars)
      string(STRIP "${LINK_DIR}" LINK_DIR)
      if(EXISTS "${LINK_DIR}/onnxruntime.dll")
        set(ORT_DLL "${LINK_DIR}/onnxruntime.dll")
        break()
      endif()
    endif()
  endforeach()
  if(ORT_DLL)
    break()
  endif()
endforeach()
if(NOT ORT_DLL)
  set(ORT_DLL "${BRIDGE_DIR}/target/release/onnxruntime.dll")
endif()
if(NOT EXISTS "${ORT_DLL}")
  file(GLOB_RECURSE CAND_DLL "${BRIDGE_DIR}/target/release/onnxruntime.dll")
  list(LENGTH CAND_DLL N_DLL)
  if(N_DLL EQUAL 0)
    # Last resort: the ort download cache itself.
    file(GLOB_RECURSE CAND_DLL "$ENV{LOCALAPPDATA}/ort.pyke.io/dfbin/*/onnxruntime.dll")
    list(LENGTH CAND_DLL N_DLL)
  endif()
  if(N_DLL EQUAL 0)
    message(FATAL_ERROR
      "onnxruntime.dll not found: no link-search dir in ort-sys build output, "
      "nothing in ${BRIDGE_DIR}/target/release, nothing in "
      "$ENV{LOCALAPPDATA}/ort.pyke.io/dfbin. Check cargo output above.")
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
