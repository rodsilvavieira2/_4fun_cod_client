#include "push_to_talk_input.h"

std::unique_ptr<PushToTalkInput> CreatePushToTalkInput(
    flutter::FlutterEngine* engine, HWND window) {
  return std::make_unique<PushToTalkInput>(engine->messenger(), window);
}
