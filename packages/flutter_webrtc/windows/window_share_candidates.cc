#include "window_share_candidates.h"

#include <Windows.h>
#include <dwmapi.h>

#include <limits>
#include <utility>

namespace flutter_webrtc_plugin {
namespace {

bool IsCloaked(HWND window) {
  DWORD cloaked = 0;
  return SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_CLOAKED, &cloaked,
                                       sizeof(cloaked))) && cloaked != 0;
}

std::string Utf8Title(HWND window) {
  const int length = GetWindowTextLengthW(window);
  if (length <= 0 || length > 32767) return {};
  std::wstring title(static_cast<size_t>(length) + 1, L'\0');
  const int copied = GetWindowTextW(window, title.data(), length + 1);
  if (copied <= 0) return {};
  const int bytes = WideCharToMultiByte(CP_UTF8, 0, title.data(), copied,
                                      nullptr, 0, nullptr, nullptr);
  if (bytes <= 0) return {};
  std::string result(bytes, '\0');
  WideCharToMultiByte(CP_UTF8, 0, title.data(), copied, result.data(), bytes,
                      nullptr, nullptr);
  return result;
}

BOOL CALLBACK CollectWindow(HWND window, LPARAM context) {
  if (!IsWindowVisible(window) || IsCloaked(window)) return TRUE;
  DWORD pid = 0;
  GetWindowThreadProcessId(window, &pid);
  // Avoid querying this process's UI thread through GetWindowText.
  if (pid == 0 || pid == GetCurrentProcessId()) return TRUE;
  const auto style = GetWindowLongPtrW(window, GWL_EXSTYLE);
  if ((style & WS_EX_TOOLWINDOW) ||
      (GetWindow(window, GW_OWNER) && !(style & WS_EX_APPWINDOW))) {
    return TRUE;
  }
  auto name = Utf8Title(window);
  if (name.empty()) return TRUE;
  auto* windows = reinterpret_cast<std::vector<ShareWindowCandidate>*>(context);
  windows->push_back({std::to_string(reinterpret_cast<uintptr_t>(window)),
                      std::move(name), pid, IsIconic(window) != FALSE});
  return TRUE;
}

}  // namespace

std::vector<ShareWindowCandidate> EnumerateShareWindows() {
  std::vector<ShareWindowCandidate> windows;
  EnumWindows(CollectWindow, reinterpret_cast<LPARAM>(&windows));
  return windows;
}

ShareWindowState ReadShareWindowState(const std::string& id,
                                     uint32_t process_id) {
  ShareWindowState state;
  uintptr_t handle = 0;
  try {
    if (id.empty() || id.find_first_not_of("0123456789") != std::string::npos) {
      return state;
    }
    const auto parsed = std::stoull(id);
    if (parsed > (std::numeric_limits<uintptr_t>::max)()) return state;
    handle = static_cast<uintptr_t>(parsed);
  } catch (...) {
    return state;
  }
  const auto window = reinterpret_cast<HWND>(handle);
  DWORD pid = 0;
  if (!IsWindow(window) || !GetWindowThreadProcessId(window, &pid) ||
      pid != process_id || pid == GetCurrentProcessId()) {
    return state;
  }
  state.valid = true;
  state.visible = IsWindowVisible(window) && !IsCloaked(window);
  state.minimized = IsIconic(window) != FALSE;
  const auto foreground = GetForegroundWindow();
  state.foreground = foreground == window ||
      (foreground && (GetAncestor(foreground, GA_ROOT) == window ||
                      GetAncestor(foreground, GA_ROOTOWNER) == window));
  return state;
}

}  // namespace flutter_webrtc_plugin
