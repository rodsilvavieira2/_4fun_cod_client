// Minimal TU for the fourfun DeepFilterNet bridge DLL (Windows).
//
// The cargo-built staticlib (and the prebuilt static onnxruntime archived
// inside it) is /MD (release CRT). Linking it straight into the plugin
// breaks Debug builds (`flutter run`: /MDd) with LNK2038/LNK1319, which the
// linker treats as fatal. This DLL wraps the staticlib and is ALWAYS built
// with the release CRT (MSVC_RUNTIME_LIBRARY=MultiThreadedDLL in
// CMakeLists), so the CRT boundary sits at the DLL edge and every plugin
// config (Debug/Profile/Release) links only the import lib. The FFI is pure
// C with caller-owned buffers, so no CRT objects cross the boundary.
//
// The exported symbols come from fourfun_deepfilter_bridge.def; this TU only
// exists because a SHARED target needs at least one source, and defines the
// trivial DllMain.
#include <windows.h>

BOOL APIENTRY DllMain(HMODULE /*module*/, DWORD /*reason*/, LPVOID /*reserved*/) {
  return TRUE;
}
