#include "push_to_talk_input.h"

#include <gio/gio.h>
#include <fcntl.h>
#include <libudev.h>
#include <linux/input.h>
#include <poll.h>
#include <unistd.h>

#include <atomic>
#include <string>
#include <vector>

namespace {

constexpr char kPortalBus[] = "org.freedesktop.portal.Desktop";
constexpr char kPortalPath[] = "/org/freedesktop/portal/desktop";
constexpr char kPortalInterface[] = "org.freedesktop.portal.GlobalShortcuts";
constexpr char kPttId[] = "push-to-talk";
constexpr char kGnomeShellBus[] = "org.gnome.Shell";
constexpr char kGnomeShellPath[] = "/org/gnome/Shell";
constexpr char kGnomeShellInterface[] = "org.gnome.Shell";
constexpr guint kGnomeShellModeNormal = 1;
constexpr guint kGnomeShellTriggerRelease = 128;

struct PttInput {
  FlEventChannel* events = nullptr;
  bool listening = false;
  GDBusConnection* bus = nullptr;
  gchar* session = nullptr;
  guint activated_subscription = 0;
  guint deactivated_subscription = 0;
  guint request_subscription = 0;
  guint gnome_activated_subscription = 0;
  guint gnome_deactivated_subscription = 0;
  guint gnome_action = 0;
  FlMethodCall* pending_configure = nullptr;
  std::atomic<bool> keyboard_running{false};
  GThread* keyboard_thread = nullptr;
  int key_code = 0;
  bool key_need_ctrl = false;
  bool key_need_alt = false;
  bool key_need_shift = false;
  bool key_ctrl_down = false;
  bool key_alt_down = false;
  bool key_shift_down = false;
  bool key_meta_down = false;
  bool key_main_down = false;
  bool key_active = false;
  std::atomic<bool> mouse_running{false};
  GThread* mouse_thread = nullptr;
  int mouse_code = 0;
};

PttInput* input = nullptr;
std::atomic_uint portal_token_counter{0};

std::string next_portal_token(const char* prefix) {
  return std::string(prefix) + "_" +
         std::to_string(portal_token_counter.fetch_add(1) + 1);
}

void send_event(const char* state) {
  if (input == nullptr || !input->listening) {
    g_message("[ptt/linux] event dropped state=%s reason=%s", state,
              input == nullptr ? "no_input" : "no_dart_listener");
    return;
  }
  g_message("[ptt/linux] send event state=%s", state);
  g_autoptr(FlValue) value = fl_value_new_map();
  fl_value_set_string_take(value, "state", fl_value_new_string(state));
  g_autoptr(GError) error = nullptr;
  if (!fl_event_channel_send(input->events, value, nullptr, &error)) {
    g_warning("[ptt/linux] event failed: %s", error->message);
  }
}

gboolean send_event_on_main(gpointer data) {
  send_event(static_cast<const char*>(data));
  g_free(data);
  return G_SOURCE_REMOVE;
}

void send_event_from_worker(const char* state) {
  g_main_context_invoke(nullptr, send_event_on_main, g_strdup(state));
}

bool respond_pending_configure_success() {
  if (input == nullptr || input->pending_configure == nullptr) return false;
  g_message("[ptt/linux] configure response success");
  g_autoptr(FlValue) result = fl_value_new_bool(true);
  fl_method_call_respond_success(input->pending_configure, result, nullptr);
  g_clear_object(&input->pending_configure);
  return true;
}

bool respond_pending_configure_error(const char* message) {
  if (input == nullptr || input->pending_configure == nullptr) return false;
  g_message("[ptt/linux] configure response error: %s", message);
  fl_method_call_respond_error(input->pending_configure, "register_failed",
                               message, nullptr, nullptr);
  g_clear_object(&input->pending_configure);
  return true;
}

void fail_pending_configure_or_emit(const char* message) {
  g_message("[ptt/linux] configure failed or emit failure: %s", message);
  if (!respond_pending_configure_error(message)) send_event("failed");
}

void cancel_pending_configure() {
  if (input != nullptr && input->pending_configure != nullptr) {
    g_message("[ptt/linux] pending configure cancelled");
  }
  respond_pending_configure_error("Registro global de Push to Talk cancelado.");
}

void clear_request_subscription() {
  if (input == nullptr || input->bus == nullptr ||
      input->request_subscription == 0) {
    return;
  }
  g_dbus_connection_signal_unsubscribe(input->bus,
                                       input->request_subscription);
  g_message("[ptt/linux] portal request unsubscribed");
  input->request_subscription = 0;
}

std::string portal_request_path(const std::string& token) {
  if (input == nullptr || input->bus == nullptr) return "";
  const gchar* unique_name = g_dbus_connection_get_unique_name(input->bus);
  if (unique_name == nullptr) return "";
  std::string sender = unique_name;
  if (!sender.empty() && sender[0] == ':') sender.erase(0, 1);
  for (char& c : sender) {
    if (c == '.') c = '_';
  }
  return "/org/freedesktop/portal/desktop/request/" + sender + "/" + token;
}

GDBusConnection* ensure_session_bus(const char* purpose) {
  if (input == nullptr) return nullptr;
  if (input->bus != nullptr) return input->bus;
  g_autoptr(GError) error = nullptr;
  input->bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (input->bus == nullptr) {
    g_warning("[ptt/linux] session bus unavailable for %s: %s", purpose,
              error == nullptr ? "unknown" : error->message);
  }
  return input->bus;
}

bool arg_bool(FlValue* arguments, const char* key) {
  FlValue* value = fl_value_lookup_string(arguments, key);
  return value != nullptr && fl_value_get_bool(value);
}

int evdev_code_for_hid_usage(guint64 usage) {
  const guint32 page = static_cast<guint32>(usage) & 0xffff0000;
  const guint32 id = static_cast<guint32>(usage) & 0xffff;
  if (page == 0x000c0000) {
    if (id == 0xe2) return KEY_MUTE;
    if (id == 0xe9) return KEY_VOLUMEUP;
    if (id == 0xea) return KEY_VOLUMEDOWN;
    return 0;
  }
  if (page != 0 && page != 0x00070000) return 0;
  if (id >= 0x04 && id <= 0x1d) return KEY_A + id - 0x04;
  if (id >= 0x1e && id <= 0x26) return KEY_1 + id - 0x1e;
  if (id == 0x27) return KEY_0;
  if (id == 0x28) return KEY_ENTER;
  if (id == 0x29) return KEY_ESC;
  if (id == 0x2a) return KEY_BACKSPACE;
  if (id == 0x2b) return KEY_TAB;
  if (id == 0x2c) return KEY_SPACE;
  if (id == 0x2d) return KEY_MINUS;
  if (id == 0x2e) return KEY_EQUAL;
  if (id == 0x2f) return KEY_LEFTBRACE;
  if (id == 0x30) return KEY_RIGHTBRACE;
  if (id == 0x31) return KEY_BACKSLASH;
  if (id == 0x32) return KEY_102ND;
  if (id == 0x33) return KEY_SEMICOLON;
  if (id == 0x34) return KEY_APOSTROPHE;
  if (id == 0x35) return KEY_GRAVE;
  if (id == 0x36) return KEY_COMMA;
  if (id == 0x37) return KEY_DOT;
  if (id == 0x38) return KEY_SLASH;
  if (id == 0x39) return KEY_CAPSLOCK;
  if (id >= 0x3a && id <= 0x45) return KEY_F1 + id - 0x3a;
  if (id == 0x46) return KEY_SYSRQ;
  if (id == 0x47) return KEY_SCROLLLOCK;
  if (id == 0x48) return KEY_PAUSE;
  if (id == 0x49) return KEY_INSERT;
  if (id == 0x4a) return KEY_HOME;
  if (id == 0x4b) return KEY_PAGEUP;
  if (id == 0x4c) return KEY_DELETE;
  if (id == 0x4d) return KEY_END;
  if (id == 0x4e) return KEY_PAGEDOWN;
  if (id == 0x4f) return KEY_RIGHT;
  if (id == 0x50) return KEY_LEFT;
  if (id == 0x51) return KEY_DOWN;
  if (id == 0x52) return KEY_UP;
  if (id >= 0x59 && id <= 0x61) return KEY_KP1 + id - 0x59;
  if (id == 0x62) return KEY_KP0;
  if (id == 0x63) return KEY_KPDOT;
  if (id == 0x64) return KEY_102ND;
  if (id >= 0x68 && id <= 0x73) return KEY_F13 + id - 0x68;
  return 0;
}

int evdev_code_for_mouse_button(int button) {
  switch (button) {
    case 4:
      return BTN_MIDDLE;
    case 8:
      return BTN_SIDE;
    case 16:
      return BTN_EXTRA;
    default:
      return 0;
  }
}

std::vector<int> open_mouse_devices() {
  std::vector<int> result;
  udev* udev_context = udev_new();
  if (udev_context == nullptr) {
    g_message("[ptt/linux] mouse devices: udev unavailable");
    return result;
  }
  udev_enumerate* enumerate = udev_enumerate_new(udev_context);
  udev_enumerate_add_match_subsystem(enumerate, "input");
  udev_enumerate_scan_devices(enumerate);
  udev_list_entry* devices = udev_enumerate_get_list_entry(enumerate);
  udev_list_entry* entry = nullptr;
  udev_list_entry_foreach(entry, devices) {
    udev_device* device = udev_device_new_from_syspath(
        udev_context, udev_list_entry_get_name(entry));
    const char* devnode = udev_device_get_devnode(device);
    const char* is_mouse = udev_device_get_property_value(device, "ID_INPUT_MOUSE");
    if (devnode != nullptr && g_strcmp0(is_mouse, "1") == 0) {
      const int fd = open(devnode, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
      if (fd >= 0) {
        result.push_back(fd);
      } else {
        g_message("[ptt/linux] mouse device open failed devnode=%s", devnode);
      }
    }
    udev_device_unref(device);
  }
  udev_enumerate_unref(enumerate);
  udev_unref(udev_context);
  return result;
}

std::vector<int> open_keyboard_devices() {
  std::vector<int> result;
  udev* udev_context = udev_new();
  if (udev_context == nullptr) {
    g_message("[ptt/linux] keyboard devices: udev unavailable");
    return result;
  }
  udev_enumerate* enumerate = udev_enumerate_new(udev_context);
  udev_enumerate_add_match_subsystem(enumerate, "input");
  udev_enumerate_scan_devices(enumerate);
  udev_list_entry* devices = udev_enumerate_get_list_entry(enumerate);
  udev_list_entry* entry = nullptr;
  udev_list_entry_foreach(entry, devices) {
    udev_device* device = udev_device_new_from_syspath(
        udev_context, udev_list_entry_get_name(entry));
    const char* devnode = udev_device_get_devnode(device);
    const char* is_keyboard =
        udev_device_get_property_value(device, "ID_INPUT_KEYBOARD");
    if (devnode != nullptr && g_strcmp0(is_keyboard, "1") == 0) {
      const int fd = open(devnode, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
      if (fd >= 0) {
        result.push_back(fd);
      } else {
        g_message("[ptt/linux] keyboard device open failed devnode=%s",
                  devnode);
      }
    }
    udev_device_unref(device);
  }
  udev_enumerate_unref(enumerate);
  udev_unref(udev_context);
  return result;
}

bool key_modifiers_exact() {
  return input->key_ctrl_down == input->key_need_ctrl &&
         input->key_alt_down == input->key_need_alt &&
         input->key_shift_down == input->key_need_shift;
}

bool key_engaged() {
  const bool main_satisfied = input->key_code == 0 || input->key_main_down;
  return main_satisfied && key_modifiers_exact() && !input->key_meta_down;
}

void update_keyboard_event(int code, bool down) {
  if (code == KEY_LEFTCTRL || code == KEY_RIGHTCTRL) {
    input->key_ctrl_down = down;
  } else if (code == KEY_LEFTALT || code == KEY_RIGHTALT) {
    input->key_alt_down = down;
  } else if (code == KEY_LEFTSHIFT || code == KEY_RIGHTSHIFT) {
    input->key_shift_down = down;
  } else if (code == KEY_LEFTMETA || code == KEY_RIGHTMETA) {
    input->key_meta_down = down;
  } else if (input->key_code != 0 && code == input->key_code) {
    input->key_main_down = down;
  } else {
    return;
  }

  const bool engaged = key_engaged();
  if (engaged == input->key_active) return;
  input->key_active = engaged;
  g_message(
      "[ptt/linux] keyboard evdev state changed state=%s code=%d "
      "ctrl=%d alt=%d shift=%d meta=%d main=%d",
      engaged ? "pressed" : "released", code, input->key_ctrl_down,
      input->key_alt_down, input->key_shift_down, input->key_meta_down,
      input->key_main_down);
  send_event_from_worker(engaged ? "pressed" : "released");
}

gpointer keyboard_thread_main(gpointer) {
  g_message("[ptt/linux] keyboard thread started code=%d ctrl=%d alt=%d shift=%d",
            input->key_code, input->key_need_ctrl, input->key_need_alt,
            input->key_need_shift);
  std::vector<int> fds = open_keyboard_devices();
  g_message("[ptt/linux] keyboard thread initial devices=%zu", fds.size());
  bool logged_empty = fds.empty();
  while (input != nullptr && input->keyboard_running) {
    if (fds.empty()) {
      if (!logged_empty) {
        g_message("[ptt/linux] keyboard thread lost devices; retrying");
        logged_empty = true;
      }
      g_usleep(500000);
      fds = open_keyboard_devices();
      if (!fds.empty()) {
        g_message("[ptt/linux] keyboard thread devices reopened=%zu",
                  fds.size());
        logged_empty = false;
      }
      continue;
    }
    std::vector<pollfd> poll_fds;
    for (const int fd : fds) poll_fds.push_back({fd, POLLIN, 0});
    poll(poll_fds.data(), poll_fds.size(), 150);
    for (const auto& poll_fd : poll_fds) {
      if ((poll_fd.revents & POLLIN) == 0) continue;
      input_event event{};
      while (read(poll_fd.fd, &event, sizeof(event)) == sizeof(event)) {
        if (event.type == EV_KEY && (event.value == 0 || event.value == 1)) {
          update_keyboard_event(event.code, event.value == 1);
        }
      }
    }
  }
  for (const int fd : fds) close(fd);
  g_message("[ptt/linux] keyboard thread stopped");
  return nullptr;
}

void stop_keyboard_listener() {
  if (input == nullptr || input->keyboard_thread == nullptr) return;
  g_message("[ptt/linux] keyboard listener stopping");
  input->keyboard_running = false;
  g_thread_join(input->keyboard_thread);
  if (input->key_active) {
    input->key_active = false;
    send_event("released");
  }
  input->keyboard_thread = nullptr;
  input->key_code = 0;
  input->key_need_ctrl = false;
  input->key_need_alt = false;
  input->key_need_shift = false;
  input->key_ctrl_down = false;
  input->key_alt_down = false;
  input->key_shift_down = false;
  input->key_meta_down = false;
  input->key_main_down = false;
}

bool configure_keyboard_evdev(FlValue* arguments) {
  FlValue* physical_key = fl_value_lookup_string(arguments, "physicalKeyUsage");
  const int code = physical_key == nullptr
                       ? 0
                       : evdev_code_for_hid_usage(fl_value_get_int(physical_key));
  input->key_need_ctrl = arg_bool(arguments, "control");
  input->key_need_alt = arg_bool(arguments, "alt");
  input->key_need_shift = arg_bool(arguments, "shift");
  g_message("[ptt/linux] configure keyboard evdev usage=%s code=%d ctrl=%d "
            "alt=%d shift=%d",
            physical_key == nullptr ? "<modifier-only>" : "set", code,
            input->key_need_ctrl, input->key_need_alt, input->key_need_shift);
  if (physical_key != nullptr && code == 0) {
    g_message("[ptt/linux] configure keyboard evdev failed: unsupported key");
    return false;
  }
  if (physical_key == nullptr &&
      (!(input->key_need_ctrl || input->key_need_alt) ||
       input->key_need_shift)) {
    g_message("[ptt/linux] configure keyboard evdev failed: invalid modifier-only");
    return false;
  }
  std::vector<int> fds = open_keyboard_devices();
  g_message("[ptt/linux] configure keyboard evdev probe devices=%zu", fds.size());
  for (const int fd : fds) close(fd);
  if (fds.empty()) {
    g_message("[ptt/linux] configure keyboard evdev failed: no readable devices");
    return false;
  }
  input->key_code = code;
  input->keyboard_running = true;
  input->keyboard_thread =
      g_thread_new("fourfun-ptt-keyboard", keyboard_thread_main, nullptr);
  g_message("[ptt/linux] configure keyboard evdev success");
  return true;
}

gpointer mouse_thread_main(gpointer) {
  g_message("[ptt/linux] mouse thread started code=%d", input->mouse_code);
  std::vector<int> fds = open_mouse_devices();
  g_message("[ptt/linux] mouse thread initial devices=%zu", fds.size());
  bool logged_empty = fds.empty();
  while (input != nullptr && input->mouse_running) {
    if (fds.empty()) {
      if (!logged_empty) {
        g_message("[ptt/linux] mouse thread lost devices; retrying");
        logged_empty = true;
      }
      g_usleep(500000);
      fds = open_mouse_devices();
      if (!fds.empty()) {
        g_message("[ptt/linux] mouse thread devices reopened=%zu", fds.size());
        logged_empty = false;
      }
      continue;
    }
    std::vector<pollfd> poll_fds;
    for (const int fd : fds) poll_fds.push_back({fd, POLLIN, 0});
    poll(poll_fds.data(), poll_fds.size(), 150);
    for (const auto& poll_fd : poll_fds) {
      if ((poll_fd.revents & POLLIN) == 0) continue;
      input_event event{};
      while (read(poll_fd.fd, &event, sizeof(event)) == sizeof(event)) {
        if (event.type == EV_KEY && event.code == input->mouse_code) {
          if (event.value == 1) {
            g_message("[ptt/linux] mouse event pressed code=%d", event.code);
            send_event_from_worker("pressed");
          }
          if (event.value == 0) {
            g_message("[ptt/linux] mouse event released code=%d", event.code);
            send_event_from_worker("released");
          }
        }
      }
    }
  }
  for (const int fd : fds) close(fd);
  g_message("[ptt/linux] mouse thread stopped");
  return nullptr;
}

void stop_mouse_listener() {
  if (input == nullptr || input->mouse_thread == nullptr) return;
  g_message("[ptt/linux] mouse listener stopping");
  input->mouse_running = false;
  g_thread_join(input->mouse_thread);
  input->mouse_thread = nullptr;
  input->mouse_code = 0;
}

void stop_gnome_accelerator() {
  if (input == nullptr || input->bus == nullptr) return;
  if (input->gnome_activated_subscription != 0) {
    g_dbus_connection_signal_unsubscribe(input->bus,
                                         input->gnome_activated_subscription);
    input->gnome_activated_subscription = 0;
    g_message("[ptt/linux] gnome accelerator activated unsubscribed");
  }
  if (input->gnome_deactivated_subscription != 0) {
    g_dbus_connection_signal_unsubscribe(
        input->bus, input->gnome_deactivated_subscription);
    input->gnome_deactivated_subscription = 0;
    g_message("[ptt/linux] gnome accelerator deactivated unsubscribed");
  }
  if (input->gnome_action == 0) return;
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      input->bus, kGnomeShellBus, kGnomeShellPath, kGnomeShellInterface,
      "UngrabAccelerator", g_variant_new("(u)", input->gnome_action),
      G_VARIANT_TYPE("(b)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
  if (reply == nullptr) {
    g_warning("[ptt/linux] gnome ungrab failed action=%u: %s",
              input->gnome_action,
              error == nullptr ? "unknown" : error->message);
  } else {
    gboolean success = FALSE;
    g_variant_get(reply, "(b)", &success);
    g_message("[ptt/linux] gnome ungrab action=%u success=%d",
              input->gnome_action, success);
  }
  input->gnome_action = 0;
}

bool configure_mouse(int button) {
  const int code = evdev_code_for_mouse_button(button);
  g_message("[ptt/linux] configure mouse button=%d code=%d", button, code);
  if (code == 0) return false;
  // Verifica a permissão antes de responder ao Dart. O worker abre de novo
  // para manter os descritores isolados da thread de UI.
  std::vector<int> fds = open_mouse_devices();
  g_message("[ptt/linux] configure mouse probe devices=%zu", fds.size());
  for (const int fd : fds) close(fd);
  if (fds.empty()) {
    g_message("[ptt/linux] configure mouse failed: no readable devices");
    return false;
  }
  input->mouse_code = code;
  input->mouse_running = true;
  input->mouse_thread = g_thread_new("fourfun-ptt-mouse", mouse_thread_main, nullptr);
  g_message("[ptt/linux] configure mouse success");
  return true;
}

void close_session() {
  if (input == nullptr) return;
  if (input->bus != nullptr || input->mouse_thread != nullptr ||
      input->keyboard_thread != nullptr || input->pending_configure != nullptr ||
      input->gnome_action != 0) {
    g_message("[ptt/linux] close session");
  }
  cancel_pending_configure();
  stop_keyboard_listener();
  stop_mouse_listener();
  if (input->bus == nullptr) return;
  stop_gnome_accelerator();
  if (input->activated_subscription != 0) {
    g_dbus_connection_signal_unsubscribe(input->bus,
                                         input->activated_subscription);
    g_message("[ptt/linux] portal activated unsubscribed");
    input->activated_subscription = 0;
  }
  if (input->deactivated_subscription != 0) {
    g_dbus_connection_signal_unsubscribe(input->bus,
                                         input->deactivated_subscription);
    g_message("[ptt/linux] portal deactivated unsubscribed");
    input->deactivated_subscription = 0;
  }
  clear_request_subscription();
  if (input->session != nullptr) {
    g_message("[ptt/linux] portal session close path=%s", input->session);
    g_dbus_connection_call(input->bus, kPortalBus, input->session,
                           "org.freedesktop.portal.Session", "Close", nullptr,
                           nullptr, G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr,
                           nullptr);
    g_clear_pointer(&input->session, g_free);
  }
  g_clear_object(&input->bus);
}

std::string portal_key(const char* label) {
  std::string key = label == nullptr ? "" : label;
  if (key == "Space") return "space";
  if (key == "Enter") return "Return";
  if (key == "Tab") return "Tab";
  if (key == "Escape") return "Escape";
  if (key.size() == 1) return std::string(1, g_ascii_tolower(key[0]));
  // Nomes de exibição do Dart para teclas sem keyLabel lógico.
  if (key == "Page Up") return "Prior";
  if (key == "Page Down") return "Next";
  if (key == "Caps Lock") return "Caps_Lock";
  return key;  // F1..F24 and named XKB keys already use this spelling.
}

std::string preferred_trigger(FlValue* arguments) {
  const FlValue* label_value = fl_value_lookup_string(arguments, "label");
  const char* label = label_value == nullptr
                          ? nullptr
                          : fl_value_get_string(const_cast<FlValue*>(label_value));
  std::string trigger = portal_key(label);
  if (arg_bool(arguments, "shift")) trigger = "SHIFT+" + trigger;
  if (arg_bool(arguments, "alt")) trigger = "ALT+" + trigger;
  if (arg_bool(arguments, "control")) trigger = "CTRL+" + trigger;
  return trigger;
}

std::string gnome_accelerator(FlValue* arguments) {
  if (fl_value_lookup_string(arguments, "physicalKeyUsage") == nullptr) {
    g_message("[ptt/linux] configure gnome skipped: modifier-only binding");
    return "";
  }
  const FlValue* label_value = fl_value_lookup_string(arguments, "label");
  const char* label = label_value == nullptr
                          ? nullptr
                          : fl_value_get_string(const_cast<FlValue*>(label_value));
  std::string trigger = portal_key(label);
  if (trigger.empty()) return "";
  std::string accelerator;
  if (arg_bool(arguments, "control")) accelerator += "<Control>";
  if (arg_bool(arguments, "alt")) accelerator += "<Alt>";
  if (arg_bool(arguments, "shift")) accelerator += "<Shift>";
  accelerator += trigger;
  return accelerator;
}

void on_gnome_accelerator_signal(GDBusConnection*, const gchar*, const gchar*,
                                 const gchar*, const gchar*, GVariant* parameters,
                                 gpointer user_data) {
  const bool pressed = GPOINTER_TO_INT(user_data) != 0;
  guint action = 0;
  g_autoptr(GVariant) options = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &action, &options);
  if (input != nullptr && input->gnome_action != 0 &&
      action == input->gnome_action) {
    g_message("[ptt/linux] gnome accelerator signal state=%s action=%u",
              pressed ? "pressed" : "released", action);
    send_event(pressed ? "pressed" : "released");
    return;
  }
  g_message("[ptt/linux] gnome accelerator signal ignored state=%s action=%u",
            pressed ? "pressed" : "released", action);
}

void subscribe_gnome_accelerator_events() {
  if (input == nullptr || input->bus == nullptr) return;
  input->gnome_activated_subscription = g_dbus_connection_signal_subscribe(
      input->bus, kGnomeShellBus, kGnomeShellInterface, "AcceleratorActivated",
      kGnomeShellPath, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      on_gnome_accelerator_signal, GINT_TO_POINTER(1), nullptr);
  input->gnome_deactivated_subscription = g_dbus_connection_signal_subscribe(
      input->bus, kGnomeShellBus, kGnomeShellInterface, "AcceleratorDeactivated",
      kGnomeShellPath, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      on_gnome_accelerator_signal, nullptr, nullptr);
  g_message("[ptt/linux] gnome accelerator events subscribed active=%u "
            "inactive=%u",
            input->gnome_activated_subscription,
            input->gnome_deactivated_subscription);
}

bool configure_gnome_shell(FlValue* arguments) {
  const std::string accelerator = gnome_accelerator(arguments);
  if (accelerator.empty()) {
    g_message("[ptt/linux] configure gnome skipped: empty accelerator");
    return false;
  }
  if (ensure_session_bus("gnome shell") == nullptr) return false;
  g_message("[ptt/linux] configure gnome accelerator=%s mode=%u flags=%u",
            accelerator.c_str(), kGnomeShellModeNormal,
            kGnomeShellTriggerRelease);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      input->bus, kGnomeShellBus, kGnomeShellPath, kGnomeShellInterface,
      "GrabAccelerator",
      g_variant_new("(suu)", accelerator.c_str(), kGnomeShellModeNormal,
                    kGnomeShellTriggerRelease),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
  if (reply == nullptr) {
    g_message("[ptt/linux] configure gnome failed: %s",
              error == nullptr ? "unknown" : error->message);
    return false;
  }
  guint action = 0;
  g_variant_get(reply, "(u)", &action);
  if (action == 0) {
    g_message("[ptt/linux] configure gnome failed: action=0");
    return false;
  }
  input->gnome_action = action;
  subscribe_gnome_accelerator_events();
  g_message("[ptt/linux] configure gnome success action=%u", action);
  return true;
}

void on_shortcut_signal(GDBusConnection*, const gchar*, const gchar*,
                        const gchar*, const gchar*, GVariant* parameters,
                        gpointer user_data) {
  const bool pressed = GPOINTER_TO_INT(user_data) != 0;
  const gchar* session = nullptr;
  const gchar* shortcut_id = nullptr;
  guint64 timestamp = 0;
  g_autoptr(GVariant) options = nullptr;
  g_variant_get(parameters, "(&o&st@a{sv})", &session, &shortcut_id,
                &timestamp, &options);
  if (input != nullptr && input->session != nullptr &&
      g_strcmp0(session, input->session) == 0 &&
      g_strcmp0(shortcut_id, kPttId) == 0) {
    g_message("[ptt/linux] portal shortcut signal state=%s timestamp=%llu",
              pressed ? "pressed" : "released",
              static_cast<unsigned long long>(timestamp));
    send_event(pressed ? "pressed" : "released");
  } else {
    g_message("[ptt/linux] portal shortcut signal ignored state=%s shortcut=%s",
              pressed ? "pressed" : "released",
              shortcut_id == nullptr ? "<null>" : shortcut_id);
  }
}

bool response_includes_ptt_shortcut(GVariant* results) {
  g_autoptr(GVariant) shortcuts = nullptr;
  if (!g_variant_lookup(results, "shortcuts", "@a(sa{sv})", &shortcuts)) {
    g_message("[ptt/linux] bind response has no shortcuts");
    return false;
  }
  GVariantIter iter;
  g_variant_iter_init(&iter, shortcuts);
  const gchar* shortcut_id = nullptr;
  GVariant* options = nullptr;
  while (g_variant_iter_next(&iter, "(&s@a{sv})", &shortcut_id, &options)) {
    const bool matches = g_strcmp0(shortcut_id, kPttId) == 0;
    if (options != nullptr) g_variant_unref(options);
    if (matches) {
      g_message("[ptt/linux] bind response includes ptt shortcut");
      return true;
    }
  }
  g_message("[ptt/linux] bind response missing ptt shortcut");
  return false;
}

void subscribe_shortcut_events() {
  if (input == nullptr || input->bus == nullptr) return;
  input->activated_subscription = g_dbus_connection_signal_subscribe(
      input->bus, kPortalBus, kPortalInterface, "Activated", nullptr, nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, on_shortcut_signal, GINT_TO_POINTER(1),
      nullptr);
  input->deactivated_subscription = g_dbus_connection_signal_subscribe(
      input->bus, kPortalBus, kPortalInterface, "Deactivated", nullptr, nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, on_shortcut_signal, nullptr, nullptr);
  g_message("[ptt/linux] portal shortcut events subscribed active=%u inactive=%u",
            input->activated_subscription, input->deactivated_subscription);
}

void bind_response(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                   const gchar*, GVariant* parameters, gpointer) {
  guint32 response = 2;
  g_autoptr(GVariant) results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &response, &results);
  g_message("[ptt/linux] bind response code=%u", response);
  clear_request_subscription();
  if (response != 0) {
    fail_pending_configure_or_emit(
        "Permissão de atalho global recusada pelo portal.");
    close_session();
    return;
  }
  if (!response_includes_ptt_shortcut(results)) {
    fail_pending_configure_or_emit(
        "O portal não vinculou o atalho global de Push to Talk.");
    close_session();
    return;
  }
  subscribe_shortcut_events();
  respond_pending_configure_success();
}

void subscribe_request(const std::string& request_path,
                       GDBusSignalCallback callback, gpointer user_data,
                       GDestroyNotify destroy) {
  if (input == nullptr || input->bus == nullptr || request_path.empty()) {
    g_message("[ptt/linux] portal request subscribe skipped path=%s",
              request_path.empty() ? "<empty>" : request_path.c_str());
    if (destroy != nullptr && user_data != nullptr) destroy(user_data);
    return;
  }
  clear_request_subscription();
  g_message("[ptt/linux] portal request subscribed path=%s",
            request_path.c_str());
  input->request_subscription = g_dbus_connection_signal_subscribe(
      input->bus, kPortalBus, "org.freedesktop.portal.Request", "Response",
      request_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE, callback,
      user_data, destroy);
}

void bind_shortcut(const std::string& trigger) {
  if (input == nullptr || input->bus == nullptr || input->session == nullptr) {
    fail_pending_configure_or_emit(
        "Sessão de atalho global indisponível no portal.");
    return;
  }
  g_message("[ptt/linux] bind shortcut trigger=%s session=%s", trigger.c_str(),
            input->session);
  GVariantBuilder shortcut_options;
  g_variant_builder_init(&shortcut_options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&shortcut_options, "{sv}", "description",
                        g_variant_new_string("Push to Talk"));
  g_variant_builder_add(&shortcut_options, "{sv}", "preferred_trigger",
                        g_variant_new_string(trigger.c_str()));
  GVariantBuilder shortcuts;
  g_variant_builder_init(&shortcuts, G_VARIANT_TYPE("a(sa{sv})"));
  g_variant_builder_add(&shortcuts, "(s@a{sv})", kPttId,
                        g_variant_builder_end(&shortcut_options));
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  const std::string handle_token = next_portal_token("fourfun_ptt_bind");
  const std::string expected_request_path = portal_request_path(handle_token);
  g_message("[ptt/linux] bind shortcut token=%s expected_request=%s",
            handle_token.c_str(), expected_request_path.c_str());
  // Assinar antes da chamada evita perder Response em portais que respondem
  // rápido demais; se o handle retornado divergir, atualizamos abaixo.
  subscribe_request(expected_request_path, bind_response, nullptr, nullptr);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(handle_token.c_str()));
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      input->bus, kPortalBus, kPortalPath, kPortalInterface, "BindShortcuts",
      g_variant_new("(o@a(sa{sv})s@a{sv})", input->session,
                    g_variant_builder_end(&shortcuts), "",
                    g_variant_builder_end(&options)), G_VARIANT_TYPE("(o)"),
      G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
  if (reply == nullptr) {
    g_warning("[ptt/linux] portal bind failed: %s", error->message);
    clear_request_subscription();
    fail_pending_configure_or_emit(
        "Não foi possível vincular o atalho global no portal.");
    return;
  }
  const gchar* request_path = nullptr;
  g_variant_get(reply, "(&o)", &request_path);
  g_message("[ptt/linux] bind shortcut reply request=%s", request_path);
  if (input->pending_configure != nullptr &&
      input->activated_subscription == 0 &&
      g_strcmp0(request_path, expected_request_path.c_str()) != 0) {
    subscribe_request(request_path, bind_response, nullptr, nullptr);
  }
}

void create_response(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                     const gchar*, GVariant* parameters, gpointer user_data) {
  guint32 response = 2;
  g_autoptr(GVariant) results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &response, &results);
  g_message("[ptt/linux] create session response code=%u", response);
  clear_request_subscription();
  if (response != 0) {
    fail_pending_configure_or_emit(
        "Permissão de sessão de atalho global recusada pelo portal.");
    close_session();
    return;
  }
  const gchar* session = nullptr;
  if (!g_variant_lookup(results, "session_handle", "&s", &session)) {
    fail_pending_configure_or_emit(
        "O portal não retornou uma sessão de atalho global válida.");
    close_session();
    return;
  }
  input->session = g_strdup(session);
  g_message("[ptt/linux] create session success session=%s", input->session);
  bind_shortcut(static_cast<const char*>(user_data));
}

void configure_keyboard_portal(FlValue* arguments) {
  g_message("[ptt/linux] configure keyboard portal start");
  if (ensure_session_bus("portal") == nullptr) {
    respond_pending_configure_error(
        "Portal de atalhos globais indisponível nesta sessão.");
    close_session();
    return;
  }
  g_autoptr(GError) error = nullptr;
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  const std::string handle_token = next_portal_token("fourfun_ptt");
  const std::string session_token = next_portal_token("fourfun_ptt_session");
  const std::string trigger = preferred_trigger(arguments);
  const std::string expected_request_path = portal_request_path(handle_token);
  g_message("[ptt/linux] configure keyboard trigger=%s token=%s session_token=%s "
            "expected_request=%s",
            trigger.c_str(), handle_token.c_str(), session_token.c_str(),
            expected_request_path.c_str());
  // Mesmo sendo um object path, a spec mantém session_handle como string por
  // compatibilidade. A assinatura antecipada segue a recomendação do Request.
  subscribe_request(expected_request_path, create_response,
                    g_strdup(trigger.c_str()), g_free);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(handle_token.c_str()));
  g_variant_builder_add(&options, "{sv}", "session_handle_token",
                        g_variant_new_string(session_token.c_str()));
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      input->bus, kPortalBus, kPortalPath, kPortalInterface, "CreateSession",
      g_variant_new("(@a{sv})", g_variant_builder_end(&options)),
      G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
  if (reply == nullptr) {
    g_warning("[ptt/linux] portal session failed: %s", error->message);
    clear_request_subscription();
    respond_pending_configure_error(
        "Não foi possível criar a sessão de atalho global no portal.");
    close_session();
    return;
  }
  const gchar* request_path = nullptr;
  g_variant_get(reply, "(&o)", &request_path);
  g_message("[ptt/linux] create session reply request=%s", request_path);
  if (input->pending_configure != nullptr && input->session == nullptr &&
      g_strcmp0(request_path, expected_request_path.c_str()) != 0) {
    subscribe_request(request_path, create_response, g_strdup(trigger.c_str()),
                      g_free);
  }
}

void configure_keyboard(FlValue* arguments) {
  g_message("[ptt/linux] configure keyboard start");
  const bool modifier_only =
      fl_value_lookup_string(arguments, "physicalKeyUsage") == nullptr;
  const bool gnome_configured = configure_gnome_shell(arguments);
  const bool evdev_configured = configure_keyboard_evdev(arguments);
  if (gnome_configured || evdev_configured) {
    g_message("[ptt/linux] configure keyboard global success gnome=%d evdev=%d",
              gnome_configured, evdev_configured);
    respond_pending_configure_success();
    return;
  }
  if (modifier_only) {
    respond_pending_configure_error(
        "Atalhos só de modificadores no Linux exigem acesso global por evdev. "
        "Execute linux/ptt/install-input-access.sh e entre novamente na sessão.");
    close_session();
    return;
  }
  g_message("[ptt/linux] configure keyboard falling back to portal");
  configure_keyboard_portal(arguments);
}

FlMethodErrorResponse* on_listen(FlEventChannel*, FlValue*, gpointer) {
  input->listening = true;
  g_message("[ptt/linux] event channel listen");
  return nullptr;
}

FlMethodErrorResponse* on_cancel(FlEventChannel*, FlValue*, gpointer) {
  input->listening = false;
  g_message("[ptt/linux] event channel cancel");
  return nullptr;
}

void method_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "configure") != 0) {
    g_message("[ptt/linux] method not implemented: %s", method);
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  g_message("[ptt/linux] configure method received");
  close_session();
  FlValue* arguments = fl_method_call_get_args(call);
  if (arguments == nullptr || fl_value_get_type(arguments) == FL_VALUE_TYPE_NULL) {
    g_message("[ptt/linux] configure null: listener disabled");
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(true)));
    fl_method_call_respond(call, response, nullptr);
    return;
  }
  FlValue* kind = fl_value_lookup_string(arguments, "kind");
  const bool keyboard = kind != nullptr &&
      g_strcmp0(fl_value_get_string(kind), "keyboard") == 0;
  const bool mouse = kind != nullptr &&
      g_strcmp0(fl_value_get_string(kind), "mouse") == 0;
  g_message("[ptt/linux] configure kind=%s keyboard=%d mouse=%d",
            kind == nullptr ? "<null>" : fl_value_get_string(kind), keyboard,
            mouse);
  if (keyboard) {
    input->pending_configure = FL_METHOD_CALL(g_object_ref(call));
    configure_keyboard(arguments);
    return;
  }
  FlValue* mouse_button = fl_value_lookup_string(arguments, "mouseButton");
  const bool configured = mouse && mouse_button != nullptr &&
      configure_mouse(static_cast<int>(fl_value_get_int(mouse_button)));
  g_message("[ptt/linux] configure mouse result=%d", configured);
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(configured)));
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

void push_to_talk_input_register(FlBinaryMessenger* messenger) {
  input = new PttInput();
  g_message("[ptt/linux] plugin registered");
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* methods = fl_method_channel_new(
      messenger, "fourfun_cod/push_to_talk", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(methods, method_call, nullptr, nullptr);
  input->events = fl_event_channel_new(messenger, "fourfun_cod/push_to_talk_events",
                                       FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(input->events, on_listen, on_cancel,
                                       nullptr, nullptr);
}
