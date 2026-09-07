#include "push_to_talk_input.h"

PushToTalkInput* PushToTalkInput::instance_ = nullptr;

std::unique_ptr<PushToTalkInput> CreatePushToTalkInput(
    flutter::FlutterEngine* engine) {
  return std::make_unique<PushToTalkInput>(engine->messenger());
}
