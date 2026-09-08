#ifndef RUNNER_PUSH_TO_TALK_INPUT_H_
#define RUNNER_PUSH_TO_TALK_INPUT_H_

#include <flutter/event_channel.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <variant>

namespace push_to_talk_detail {

using flutter::EncodableMap;
using flutter::EncodableValue;

inline int virtual_key_for_hid_usage(uint32_t usage) {
  // Flutter PhysicalKeyboardKey.usbHidUsage includes the HID usage page
  // (keyboard A is 0x00070004). Legacy page-less values are treated as the
  // keyboard page so persisted bindings from older builds remain usable.
  const uint32_t page = usage & 0xffff0000;
  const uint32_t id = usage & 0xffff;
  if (page == 0x000c0000) {
    // Consumer page: media keys (single VK each, visible to WH_KEYBOARD_LL).
    if (id == 0xe2) return VK_VOLUME_MUTE;
    if (id == 0xe9) return VK_VOLUME_UP;
    if (id == 0xea) return VK_VOLUME_DOWN;
    return 0;
  }
  if (page != 0 && page != 0x00070000) return 0;
  if (id >= 0x04 && id <= 0x1d) return 'A' + id - 0x04;
  if (id >= 0x1e && id <= 0x26) return '1' + id - 0x1e;
  if (id == 0x27) return '0';
  if (id == 0x28) return VK_RETURN;
  if (id == 0x29) return VK_ESCAPE;
  if (id == 0x2a) return VK_BACK;
  // Punctuation (ABNT2/Data positions follow the US HID layout here).
  if (id == 0x2d) return VK_OEM_MINUS;
  if (id == 0x2e) return VK_OEM_PLUS;
  if (id == 0x2f) return VK_OEM_4;
  if (id == 0x30) return VK_OEM_6;
  if (id == 0x31) return VK_OEM_5;
  if (id == 0x32) return VK_OEM_102;
  if (id == 0x33) return VK_OEM_1;
  if (id == 0x34) return VK_OEM_7;
  if (id == 0x35) return VK_OEM_3;
  if (id == 0x36) return VK_OEM_COMMA;
  if (id == 0x37) return VK_OEM_PERIOD;
  if (id == 0x38) return VK_OEM_2;
  if (id == 0x2b) return VK_TAB;
  if (id == 0x2c) return VK_SPACE;
  if (id == 0x39) return VK_CAPITAL;
  if (id >= 0x3a && id <= 0x45) return VK_F1 + id - 0x3a;
  // Navigation cluster + arrows.
  if (id == 0x49) return VK_INSERT;
  if (id == 0x4a) return VK_HOME;
  if (id == 0x4b) return VK_PRIOR;
  if (id == 0x4c) return VK_DELETE;
  if (id == 0x4d) return VK_END;
  if (id == 0x4e) return VK_NEXT;
  if (id == 0x4f) return VK_RIGHT;
  if (id == 0x50) return VK_LEFT;
  if (id == 0x51) return VK_DOWN;
  if (id == 0x52) return VK_UP;
  // Numpad (0x59-0x61 KP1-KP9, 0x62 KP0, 0x63 KP.).
  if (id >= 0x59 && id <= 0x61) return VK_NUMPAD1 + id - 0x59;
  if (id == 0x62) return VK_NUMPAD0;
  if (id == 0x63) return VK_DECIMAL;
  if (id == 0x47) return VK_SCROLL;
  if (id == 0x48) return VK_PAUSE;
  // NOTE: PrintScreen (0x46) intentionally unmapped — WH_KEYBOARD_LL does not
  // deliver a reliable KeyDown for it, so promising it would ship broken.
  if (id >= 0x68 && id <= 0x73) return VK_F13 + id - 0x68;
  return 0;
}

inline bool IsControlVk(int vk) {
  return vk == VK_CONTROL || vk == VK_LCONTROL || vk == VK_RCONTROL;
}

inline bool IsAltVk(int vk) {
  return vk == VK_MENU || vk == VK_LMENU || vk == VK_RMENU;
}

inline bool IsShiftVk(int vk) {
  return vk == VK_SHIFT || vk == VK_LSHIFT || vk == VK_RSHIFT;
}

inline bool value_bool(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  return it != map.end() && std::holds_alternative<bool>(it->second) &&
         std::get<bool>(it->second);
}

inline std::optional<std::string> value_string(const EncodableMap& map,
                                               const char* key) {
  const auto it = map.find(EncodableValue(key));
  if (it == map.end() || !std::holds_alternative<std::string>(it->second)) {
    return std::nullopt;
  }
  return std::get<std::string>(it->second);
}

inline std::optional<int64_t> value_int(const EncodableMap& map,
                                        const char* key) {
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

}  // namespace push_to_talk_detail

// Substituto de flutter::StreamHandlerFunctions (removido do embedder):
// repassa OnListen/OnCancel para a instância dona do sink.
class PushToTalkStreamHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  using Sink = flutter::EventSink<flutter::EncodableValue>;
  using ListenFn = std::function<void(std::unique_ptr<Sink>&&)>;
  using CancelFn = std::function<void()>;

  PushToTalkStreamHandler(ListenFn on_listen, CancelFn on_cancel)
      : on_listen_(std::move(on_listen)), on_cancel_(std::move(on_cancel)) {}

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue*,
      std::unique_ptr<Sink>&& sink) override {
    on_listen_(std::move(sink));
    return nullptr;
  }

  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(const flutter::EncodableValue*) override {
    on_cancel_();
    return nullptr;
  }

 private:
  ListenFn on_listen_;
  CancelFn on_cancel_;
};

class PushToTalkInput {
 public:
  explicit PushToTalkInput(flutter::BinaryMessenger* messenger) {
    instance_ = this;
    methods_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "fourfun_cod/push_to_talk",
        &flutter::StandardMethodCodec::GetInstance());
    methods_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          HandleMethodCall(call, std::move(result));
        });
    events_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        messenger, "fourfun_cod/push_to_talk_events",
        &flutter::StandardMethodCodec::GetInstance());
    events_->SetStreamHandler(
        std::make_unique<PushToTalkStreamHandler>(
            [this](std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& sink) {
              sink_ = std::move(sink);
            },
            [this]() { sink_.reset(); }));
  }

  ~PushToTalkInput() {
    Unregister();
    if (instance_ == this) instance_ = nullptr;
  }

 private:
  using EncodableMap = flutter::EncodableMap;
  using EncodableValue = flutter::EncodableValue;
  using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
  using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

  // Estado do chord observado via eventos KeyDown/KeyUp (nunca via polling).
  // Ativa somente com o chord COMPLETO pressionado e libera ao soltar
  // QUALQUER membro — sem PTT travado e sem reter eventos de outros apps
  // (o hook sempre repassa via CallNextHookEx).
  struct Chord {
    int trigger_vk = 0;    // 0 = sem tecla-gatilho (só-modificadores/mouse).
    int mouse_button = 0;  // 0 = teclado; senão 4/8/16 (middle/back/forward).
    bool need_ctrl = false;
    bool need_alt = false;
    bool need_shift = false;
    bool ctrl_down = false;
    bool alt_down = false;
    bool shift_down = false;
    bool main_down = false;  // tecla-gatilho ou botão do mouse.
    bool active = false;

    bool MainSatisfied() const {
      return (trigger_vk == 0 && mouse_button == 0) || main_down;
    }
    // Paridade com o Dart: modificadores extras NÃO ativam (match exato).
    bool ModifiersExact() const {
      return (ctrl_down == need_ctrl) && (alt_down == need_alt) &&
             (shift_down == need_shift);
    }
    bool Engaged() const { return MainSatisfied() && ModifiersExact(); }
  };

  void HandleMethodCall(
      const MethodCall& call,
      std::unique_ptr<MethodResult> result) {
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
      result->Error("unsupported_key", "Argumentos inválidos para o atalho.");
      return;
    }
    const auto& map = std::get<EncodableMap>(*call.arguments());
    const auto kind = push_to_talk_detail::value_string(map, "kind");
    if (!kind) {
      result->Error("unsupported_key", "Tipo de atalho desconhecido.");
      return;
    }
    chord_.need_ctrl = push_to_talk_detail::value_bool(map, "control");
    chord_.need_alt = push_to_talk_detail::value_bool(map, "alt");
    chord_.need_shift = push_to_talk_detail::value_bool(map, "shift");
    if (*kind == "keyboard") {
      const auto physical_key_usage =
          push_to_talk_detail::value_int(map, "physicalKeyUsage");
      if (physical_key_usage) {
        chord_.trigger_vk = push_to_talk_detail::virtual_key_for_hid_usage(
            static_cast<uint32_t>(*physical_key_usage));
        if (chord_.trigger_vk == 0) {
          ResetChord();
          result->Error("unsupported_key",
                        "Tecla não suportada como atalho global no Windows.");
          return;
        }
      } else if (!chord_.need_ctrl && !chord_.need_alt) {
        // Só-modificadores exige Ctrl e/ou Alt (Shift sozinho não vale).
        ResetChord();
        result->Error("unsupported_key",
                      "Atalho só de modificadores inválido no Windows.");
        return;
      }
      keyboard_hook_ = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardHook,
                                        GetModuleHandle(nullptr), 0);
      if (!keyboard_hook_) {
        ResetChord();
        result->Error("register_failed",
                      "Não foi possível instalar o hook de teclado.");
        return;
      }
      result->Success(EncodableValue(true));
      return;
    }
    if (*kind == "mouse") {
      const auto button = push_to_talk_detail::value_int(map, "mouseButton");
      chord_.mouse_button = button ? static_cast<int>(*button) : 0;
      if (chord_.mouse_button != 4 && chord_.mouse_button != 8 &&
          chord_.mouse_button != 16) {
        ResetChord();
        result->Error("unsupported_key",
                      "Botão do mouse não suportado como atalho.");
        return;
      }
      mouse_hook_ =
          SetWindowsHookEx(WH_MOUSE_LL, MouseHook, GetModuleHandle(nullptr), 0);
      // Mouse com modificadores também observa o teclado para rastrear
      // Ctrl/Alt/Shift via eventos (sem polling).
      if (mouse_hook_ && (chord_.need_ctrl || chord_.need_alt || chord_.need_shift)) {
        keyboard_hook_ = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardHook,
                                          GetModuleHandle(nullptr), 0);
      }
      if (!mouse_hook_ || ((chord_.need_ctrl || chord_.need_alt || chord_.need_shift) &&
                            !keyboard_hook_)) {
        Unregister();
        result->Error("register_failed",
                      "Não foi possível instalar o hook de mouse/teclado.");
        return;
      }
      result->Success(EncodableValue(true));
      return;
    }
    ResetChord();
    result->Error("unsupported_key", "Tipo de atalho desconhecido.");
  }

  void ResetChord() { chord_ = Chord(); }

  void Unregister() {
    if (keyboard_hook_) UnhookWindowsHookEx(keyboard_hook_);
    if (mouse_hook_) UnhookWindowsHookEx(mouse_hook_);
    keyboard_hook_ = nullptr;
    mouse_hook_ = nullptr;
    if (chord_.active) Emit("released");
    ResetChord();
  }

  void OnKeyboardVk(int vk, bool down) {
    if (push_to_talk_detail::IsControlVk(vk)) {
      chord_.ctrl_down = down;
    } else if (push_to_talk_detail::IsAltVk(vk)) {
      chord_.alt_down = down;
    } else if (push_to_talk_detail::IsShiftVk(vk)) {
      chord_.shift_down = down;
    } else if (vk == chord_.trigger_vk && chord_.trigger_vk != 0) {
      chord_.main_down = down;
    } else {
      return;  // Tecla fora do chord: ignora sem bloquear.
    }
    EvaluateChord();
  }

  void OnMouseButton(bool down) {
    chord_.main_down = down;
    EvaluateChord();
  }

  void EvaluateChord() {
    const bool engaged = chord_.Engaged();
    if (engaged && !chord_.active) {
      chord_.active = true;
      Emit("pressed");
    } else if (!engaged && chord_.active) {
      chord_.active = false;
      Emit("released");
    }
  }

  void Emit(const char* state) {
    if (!sink_) return;
    EncodableMap event;
    event[EncodableValue("state")] = EncodableValue(state);
    sink_->Success(EncodableValue(event));
  }

  static LRESULT CALLBACK KeyboardHook(int code, WPARAM message, LPARAM data) {
    if (code == HC_ACTION && instance_) {
      const auto* info = reinterpret_cast<KBDLLHOOKSTRUCT*>(data);
      if (message == WM_KEYDOWN || message == WM_SYSKEYDOWN) {
        instance_->OnKeyboardVk(static_cast<int>(info->vkCode), true);
      } else if (message == WM_KEYUP || message == WM_SYSKEYUP) {
        instance_->OnKeyboardVk(static_cast<int>(info->vkCode), false);
      }
    }
    // Nunca consome: atalhos de outros aplicativos passam intactos.
    // (Ctrl+Alt+Del sequer chega ao hook — é sequência de atenção segura do
    // SO — por isso a captura no Dart a rejeita com mensagem específica.)
    return CallNextHookEx(nullptr, code, message, data);
  }

  static LRESULT CALLBACK MouseHook(int code, WPARAM message, LPARAM data) {
    if (code == HC_ACTION && instance_) {
      const int button = instance_->chord_.mouse_button;
      const auto* info = reinterpret_cast<MSLLHOOKSTRUCT*>(data);
      const int xbutton = HIWORD(info->mouseData);
      const bool down =
          (button == 4 && message == WM_MBUTTONDOWN) ||
          (button == 8 && message == WM_XBUTTONDOWN && xbutton == XBUTTON1) ||
          (button == 16 && message == WM_XBUTTONDOWN && xbutton == XBUTTON2);
      const bool up =
          (button == 4 && message == WM_MBUTTONUP) ||
          (button == 8 && message == WM_XBUTTONUP && xbutton == XBUTTON1) ||
          (button == 16 && message == WM_XBUTTONUP && xbutton == XBUTTON2);
      if (down) {
        instance_->OnMouseButton(true);
      } else if (up) {
        instance_->OnMouseButton(false);
      }
    }
    return CallNextHookEx(nullptr, code, message, data);
  }

  static PushToTalkInput* instance_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> methods_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  HHOOK keyboard_hook_ = nullptr;
  HHOOK mouse_hook_ = nullptr;
  Chord chord_;
};

std::unique_ptr<PushToTalkInput> CreatePushToTalkInput(
    flutter::FlutterEngine* engine);

#endif  // RUNNER_PUSH_TO_TALK_INPUT_H_
