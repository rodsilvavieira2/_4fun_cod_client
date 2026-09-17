cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "flutter_webrtc")
project(${PROJECT_NAME} LANGUAGES CXX)

if (CMAKE_VERSION VERSION_GREATER_EQUAL "3.24.0")
  cmake_policy(SET CMP0135 NEW)
endif()

# Add the libwebrtc dependency
include("${CMAKE_CURRENT_SOURCE_DIR}/../third_party/CMakeLists.txt")

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "flutter_webrtc_plugin")

add_definitions(-DLIB_WEBRTC_API_DLL)
add_definitions(-DRTC_DESKTOP_DEVICE)

add_library(${PLUGIN_NAME} SHARED
  "../common/cpp/src/deep_filter_audio_processor.cc"
  "../common/cpp/src/flutter_common.cc"
  "../common/cpp/src/flutter_data_channel.cc"
  "../common/cpp/src/flutter_data_packet_cryptor.cc"
  "../common/cpp/src/flutter_frame_cryptor.cc"
  "../common/cpp/src/flutter_media_stream.cc"
  "../common/cpp/src/flutter_utf8_sanitize.cc"
  "../common/cpp/src/flutter_peerconnection.cc"
  "../common/cpp/src/flutter_frame_capturer.cc"
  "../common/cpp/src/flutter_video_renderer.cc"
  "../common/cpp/src/flutter_screen_capture.cc"
  "../common/cpp/src/flutter_webrtc.cc"
  "../common/cpp/src/flutter_webrtc_base.cc"
  "application_loopback_capturer.cc"
  "loopback_capturer_factory.cc"
  "flutter_webrtc_plugin.cc"
  "task_runner_windows.cc"
)

unset(DEEPFILTER_BRIDGE_DIR CACHE)
get_filename_component(FLUTTER_WEBRTC_PLUGIN_ROOT
  "${CMAKE_CURRENT_SOURCE_DIR}/.." REALPATH)
get_filename_component(DEEPFILTER_BRIDGE_DIR
  "${FLUTTER_WEBRTC_PLUGIN_ROOT}/../../native/deepfilter_bridge" REALPATH)
if(NOT EXISTS "${DEEPFILTER_BRIDGE_DIR}/Cargo.toml")
  message(FATAL_ERROR "Unable to locate native/deepfilter_bridge from ${CMAKE_CURRENT_SOURCE_DIR}")
endif()
message(STATUS "flutter_webrtc: DeepFilterNet bridge at ${DEEPFILTER_BRIDGE_DIR}")
set(DEEPFILTER_BRIDGE_LIB
  "${DEEPFILTER_BRIDGE_DIR}/target/release/fourfun_deepfilter_bridge.lib")
find_program(CARGO_EXECUTABLE cargo)
if(NOT CARGO_EXECUTABLE)
  message(FATAL_ERROR "cargo is required to build DeepFilterNet support")
endif()
add_custom_command(
  OUTPUT "${DEEPFILTER_BRIDGE_LIB}"
  COMMAND "${CARGO_EXECUTABLE}" build --manifest-path
          "${DEEPFILTER_BRIDGE_DIR}/Cargo.toml" --release
  WORKING_DIRECTORY "${DEEPFILTER_BRIDGE_DIR}"
  # The .lib lives in the source tree (cargo target dir), so it survives
  # `flutter clean` while the C++ objects don't. Without DEPENDS, CMake
  # considers the existing .lib up to date and silently links a STALE Rust
  # bridge next to fresh C++ objects. Depending on the bridge sources
  # forces cargo to re-run (a no-op when fresh) on every Flutter build.
  DEPENDS "${DEEPFILTER_BRIDGE_DIR}/Cargo.toml"
          "${DEEPFILTER_BRIDGE_DIR}/Cargo.lock"
          "${DEEPFILTER_BRIDGE_DIR}/build.rs"
          "${DEEPFILTER_BRIDGE_DIR}/src/lib.rs"
          "${DEEPFILTER_BRIDGE_DIR}/src/dpdfnet.rs"
  COMMENT "Building fourfun DeepFilterNet bridge"
)
add_custom_target(fourfun_deepfilter_bridge_build
  DEPENDS "${DEEPFILTER_BRIDGE_LIB}")
add_library(fourfun_deepfilter_bridge STATIC IMPORTED GLOBAL)
set_target_properties(fourfun_deepfilter_bridge PROPERTIES
  IMPORTED_LOCATION "${DEEPFILTER_BRIDGE_LIB}")
# On MSVC the ort crate links onnxruntime dynamically: stage the downloaded
# DLL at build time (after cargo) and ship it. Linux needs none of this -
# onnxruntime is statically inside the .a (verified: no DT_NEEDED, Ort
# symbols defined in the plugin .so).
#
# The ort download cache path contains a version hash (unstable), and
# copy-dylibs only surfaces the .dll - never the import .lib the MSVC link
# needs. So the stage script takes the DLL (copy-dylibs drops it at the cargo
# profile root) and rebuilds an import lib from its exports with the MSVC
# tools living next to the linker.
set(FOURFUN_ORT_STAGE_DIR "${CMAKE_CURRENT_BINARY_DIR}/fourfun_ort_stage")
get_filename_component(FOURFUN_MSVC_BINDIR "${CMAKE_LINKER}" DIRECTORY)
find_program(FOURFUN_DUMPBIN_EXE NAMES dumpbin.exe
  PATHS "${FOURFUN_MSVC_BINDIR}" NO_DEFAULT_PATH)
find_program(FOURFUN_LIB_EXE NAMES lib.exe
  PATHS "${FOURFUN_MSVC_BINDIR}" NO_DEFAULT_PATH)
if(NOT FOURFUN_DUMPBIN_EXE OR NOT FOURFUN_LIB_EXE)
  message(FATAL_ERROR
    "fourfun: dumpbin.exe/lib.exe not found next to ${CMAKE_LINKER} - "
    "cannot stage onnxruntime for the DeepFilterNet bridge")
endif()
if(NOT TARGET fourfun_ort_stage)
add_custom_command(
  OUTPUT "${FOURFUN_ORT_STAGE_DIR}/onnxruntime.dll"
         "${FOURFUN_ORT_STAGE_DIR}/onnxruntime.lib"
  COMMAND ${CMAKE_COMMAND}
    -DBRIDGE_DIR="${DEEPFILTER_BRIDGE_DIR}"
    -DSTAGE_DIR="${FOURFUN_ORT_STAGE_DIR}"
    -DDUMPBIN_EXE="${FOURFUN_DUMPBIN_EXE}"
    -DLIB_EXE="${FOURFUN_LIB_EXE}"
    -P "${CMAKE_CURRENT_SOURCE_DIR}/stage_ort_windows.cmake"
  DEPENDS "${DEEPFILTER_BRIDGE_LIB}"
  COMMENT "Staging onnxruntime binaries for flutter_webrtc"
)
add_custom_target(fourfun_ort_stage
  DEPENDS "${FOURFUN_ORT_STAGE_DIR}/onnxruntime.dll"
          "${FOURFUN_ORT_STAGE_DIR}/onnxruntime.lib")
endif()
if(NOT TARGET fourfun_onnxruntime)
add_library(fourfun_onnxruntime STATIC IMPORTED GLOBAL)
set_target_properties(fourfun_onnxruntime PROPERTIES
  IMPORTED_LOCATION "${FOURFUN_ORT_STAGE_DIR}/onnxruntime.lib")
endif()


include_directories(
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common/cpp/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/svpng"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/include"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../common/cpp/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/include"
)
target_link_libraries(${PLUGIN_NAME} PRIVATE 
  flutter
  flutter_wrapper_plugin
  fourfun_deepfilter_bridge
  fourfun_onnxruntime
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/lib/libwebrtc.dll.lib"
  avrt.lib
  ksuser.lib
  mmdevapi.lib
  ole32.lib
  runtimeobject.lib
  uuid.lib
  bcrypt.lib
  ntdll.lib
  userenv.lib
  winmm.lib
  ws2_32.lib
)
add_dependencies(${PLUGIN_NAME} fourfun_deepfilter_bridge_build)
add_dependencies(${PLUGIN_NAME} fourfun_ort_stage)

# List of absolute paths to libraries that should be bundled with the plugin
set(flutter_webrtc_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc/lib/libwebrtc.dll"
  "${FOURFUN_ORT_STAGE_DIR}/onnxruntime.dll"
  PARENT_SCOPE
)
