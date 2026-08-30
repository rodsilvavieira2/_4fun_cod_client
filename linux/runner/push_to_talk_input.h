#ifndef RUNNER_PUSH_TO_TALK_INPUT_H_
#define RUNNER_PUSH_TO_TALK_INPUT_H_

#include <flutter_linux/flutter_linux.h>

// Instala os canais fourfun_cod/push_to_talk e
// fourfun_cod/push_to_talk_events no messenger do runner.
void push_to_talk_input_register(FlBinaryMessenger* messenger);

#endif  // RUNNER_PUSH_TO_TALK_INPUT_H_
