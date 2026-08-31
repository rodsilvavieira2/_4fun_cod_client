#include "push_to_talk_input.h"

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <optional>
#include <string>
#include <variant>

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::EventChannel;
using flutter::EventSink;
using flutter::MethodCall;
using flutter::MethodChannel;
using flutter::MethodResult;
using flutter::StreamHandlerError;
using flutter::StreamHandlerFunctions;

int virtual_key_for_hid_usage(uint32_t usage) {
  // Flutter PhysicalKeyboardKey.usbHidUsage includes the HID usage page
  // (keyboard A is 0x00070004). Keep accepting the legacy page-less value
  // so persisted bindings from older builds remain usable.
  if ((usage & 0xffff0000) != 0) {
    if ((usage & 0xffff0000) != 0x00070000) return 0;
    usage &= 0xffff;
  }
  if (usage >= 0x04 && usage <= 0x1d) return 'A' + usage - 0x04;
  if (usage >= 0x1e && usage <= 0x26) return '1' + usage - 0x1e;
  if (usage == 0x27) return '0';
  if (usage == 0x28) return VK_RETURN;
  if (usage == 0x29) return VK_ESCAPE;
  if (usage == 0x2b) return VK_TAB;
  if (usage == 0x2c) return VK_SPACE;
  if (usage >= 0x3a && usage <= 0x45) return VK_F1 + usage - 0x3a;
  if (usage >= 0x68 && usage <= 0x73) return VK_F13 + usage - 0x68;
  return 0;
}

bool value_bool(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  return it != map.end() && std::holds_alternative<bool>(it->second) &&
         std::get<bool>(it->second);
}

std::optional<std::string> value_string(const EncodableMap& map,
                                        const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end() || !std::holds_alternative<std::string>(it->second)) {
    return std::nullopt;
  }
  return std::get<std::string>(it->second);
}

std::optional<int64_t> value_int(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end()) return std::nullopt;
  if (std::holds_alternative<int32_t>(it->second)) {
    return std::get<int32_t>(it->second);
  }
  if (std::holds_alternative<int64_t>(it->second)) {
    return std::get<int64_t>(it->second);
  }
  return std::nullopt;
}

}  // namespace

class PushToTalkInput {
 public:
  explicit PushToTalkInput(flutter::BinaryMessenger* messenger) {
    instance_ = this;
    methods_ = std::make_unique<MethodChannel<EncodableValue>>(
        messenger, "fourfun_cod/push_to_talk",
        &flutter::StandardMethodCodec::GetInstance());
    methods_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleMethodCall(call, std::move(result));
        });
    events_ = std::make_unique<EventChannel<EncodableValue>>(
        messenger, "fourfun_cod/push_to_talk_events",
        &flutter::StandardMethodCodec::GetInstance());
    events_->SetStreamHandler(
        std::make_unique<StreamHandlerFunctions<EncodableValue>>(
            [this](const EncodableValue*,
                   std::unique_ptr<EventSink<EncodableValue>>&& sink)
                -> std::unique_ptr<StreamHandlerError<EncodableValue>> {
              sink_ = std::move(sink);
              return nullptr;
            },
            [this](const EncodableValue*)
                -> std::unique_ptr<StreamHandlerError<EncodableValue>> {
              sink_.reset();
              return nullptr;
            }));
  }

  ~PushToTalkInput() {
    Unregister();
    if (instance_ == this) instance_ = nullptr;
  }

 private:
  void HandleMethodCall(
      const MethodCall<EncodableValue>& call,
      std::unique_ptr<MethodResult<EncodableValue>> result) {
    if (call.method_name() != "configure") {
      result->NotImplemented();
      return;
    }
    Unregister();
    if (!call.arguments() || std::holds_alternative<std::monostate>(*call.arguments())) {
      result->Success(EncodableValue(true));
      return;
    }
    if (!std::holds_alternative<EncodableMap>(*call.arguments())) {
      result->Success(EncodableValue(false));
      return;
    }
    const auto& map = std::get<EncodableMap>(*call.arguments());
    const auto kind = value_string(map, "kind");
    if (!kind) {
      result->Success(EncodableValue(false));
      return;
    }
    control_ = value_bool(map, "control");
    alt_ = value_bool(map, "alt");
    shift_ = value_bool(map, "shift");
    if (*kind == "keyboard") {
      const auto physical_key_usage = value_int(map, "physicalKeyUsage");
      key_ = physical_key_usage
          ? virtual_key_for_hid_usage(
                static_cast<uint32_t>(*physical_key_usage))
          : 0;
      if (key_ == 0) {
        result->Success(EncodableValue(false));
        return;
      }
      keyboard_hook_ = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardHook,
                                        GetModuleHandle(nullptr), 0);
      result->Success(EncodableValue(keyboard_hook_ != nullptr));
      return;
    }
    if (*kind == "mouse") {
      const auto button = value_int(map, "mouseButton");
      mouse_button_ = button ? static_cast<int>(*button) : 0;
      if (mouse_button_ != 4 && mouse_button_ != 8 && mouse_button_ != 16) {
        result->Success(EncodableValue(false));
        return;
      }
      mouse_hook_ = SetWindowsHookEx(WH_MOUSE_LL, MouseHook,
                                     GetModuleHandle(nullptr), 0);
      result->Success(EncodableValue(mouse_hook_ != nullptr));
      return;
    }
    result->Success(EncodableValue(false));
  }

  void Unregister() {
    if (keyboard_hook_) UnhookWindowsHookEx(keyboard_hook_);
    if (mouse_hook_) UnhookWindowsHookEx(mouse_hook_);
    keyboard_hook_ = nullptr;
    mouse_hook_ = nullptr;
    key_ = 0;
    mouse_button_ = 0;
  }

  bool ModifiersMatch() const {
    return ((GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0) == control_ &&
           ((GetAsyncKeyState(VK_MENU) & 0x8000) != 0) == alt_ &&
           ((GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0) == shift_;
  }

  void Emit(const char* state) {
    if (!sink_) return;
    EncodableMap event;
    event[EncodableValue("state")] = EncodableValue(state);
    sink_->Success(EncodableValue(event));
  }

  static LRESULT CALLBACK KeyboardHook(int code, WPARAM message, LPARAM data) {
    if (code == HC_ACTION && instance_ && instance_->key_ != 0) {
      const auto* info = reinterpret_cast<KBDLLHOOKSTRUCT*>(data);
      if (static_cast<int>(info->vkCode) == instance_->key_) {
        if ((message == WM_KEYDOWN || message == WM_SYSKEYDOWN) &&
            instance_->ModifiersMatch()) {
          instance_->Emit("pressed");
        } else if (message == WM_KEYUP || message == WM_SYSKEYUP) {
          instance_->Emit("released");
        }
      }
    }
    return CallNextHookEx(nullptr, code, message, data);
  }

  static LRESULT CALLBACK MouseHook(int code, WPARAM message, LPARAM data) {
    if (code == HC_ACTION && instance_ && instance_->mouse_button_ != 0) {
      const bool middle = instance_->mouse_button_ == 4;
      const bool back = instance_->mouse_button_ == 8;
      const bool forward = instance_->mouse_button_ == 16;
      if ((middle && message == WM_MBUTTONDOWN) ||
          (back && message == WM_XBUTTONDOWN &&
           HIWORD(reinterpret_cast<MSLLHOOKSTRUCT*>(data)->mouseData) == XBUTTON1) ||
          (forward && message == WM_XBUTTONDOWN &&
           HIWORD(reinterpret_cast<MSLLHOOKSTRUCT*>(data)->mouseData) == XBUTTON2)) {
        instance_->Emit("pressed");
      }
      if ((middle && message == WM_MBUTTONUP) ||
          (back && message == WM_XBUTTONUP &&
           HIWORD(reinterpret_cast<MSLLHOOKSTRUCT*>(data)->mouseData) == XBUTTON1) ||
          (forward && message == WM_XBUTTONUP &&
           HIWORD(reinterpret_cast<MSLLHOOKSTRUCT*>(data)->mouseData) == XBUTTON2)) {
        instance_->Emit("released");
      }
    }
    return CallNextHookEx(nullptr, code, message, data);
  }

  static PushToTalkInput* instance_;
  std::unique_ptr<MethodChannel<EncodableValue>> methods_;
  std::unique_ptr<EventChannel<EncodableValue>> events_;
  std::unique_ptr<EventSink<EncodableValue>> sink_;
  HHOOK keyboard_hook_ = nullptr;
  HHOOK mouse_hook_ = nullptr;
  int key_ = 0;
  int mouse_button_ = 0;
  bool control_ = false;
  bool alt_ = false;
  bool shift_ = false;
};

PushToTalkInput* PushToTalkInput::instance_ = nullptr;

std::unique_ptr<PushToTalkInput> CreatePushToTalkInput(
    flutter::FlutterEngine* engine) {
  return std::make_unique<PushToTalkInput>(engine->messenger());
}
