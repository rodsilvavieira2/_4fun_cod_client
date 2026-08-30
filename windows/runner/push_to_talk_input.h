#ifndef RUNNER_PUSH_TO_TALK_INPUT_H_
#define RUNNER_PUSH_TO_TALK_INPUT_H_

#include <flutter/flutter_engine.h>

#include <memory>

class PushToTalkInput;

std::unique_ptr<PushToTalkInput> CreatePushToTalkInput(
    flutter::FlutterEngine* engine);

#endif  // RUNNER_PUSH_TO_TALK_INPUT_H_
