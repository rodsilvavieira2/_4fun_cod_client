#ifndef FOURFUN_WINDOW_SHARE_CANDIDATES_H_
#define FOURFUN_WINDOW_SHARE_CANDIDATES_H_

#include <cstdint>
#include <string>
#include <vector>

namespace flutter_webrtc_plugin {

struct ShareWindowCandidate {
  std::string id;
  std::string name;
  uint32_t process_id;
  bool minimized;
};

struct ShareWindowState {
  bool valid = false;
  bool visible = false;
  bool minimized = false;
  bool foreground = false;
};

std::vector<ShareWindowCandidate> EnumerateShareWindows();
ShareWindowState ReadShareWindowState(const std::string& id,
                                     uint32_t process_id);

}  // namespace flutter_webrtc_plugin
#endif
