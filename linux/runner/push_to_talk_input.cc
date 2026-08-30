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

struct PttInput {
  FlEventChannel* events = nullptr;
  bool listening = false;
  GDBusConnection* bus = nullptr;
  gchar* session = nullptr;
  guint activated_subscription = 0;
  guint deactivated_subscription = 0;
  guint request_subscription = 0;
  std::atomic<bool> mouse_running{false};
  GThread* mouse_thread = nullptr;
  int mouse_code = 0;
};

PttInput* input = nullptr;

void send_event(const char* state) {
  if (input == nullptr || !input->listening) return;
  g_autoptr(FlValue) value = fl_value_new_map();
  fl_value_set_string_take(value, "state", fl_value_new_string(state));
  g_autoptr(GError) error = nullptr;
  if (!fl_event_channel_send(input->events, value, nullptr, &error)) {
    g_warning("Push to Talk event failed: %s", error->message);
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
  if (udev_context == nullptr) return result;
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
      if (fd >= 0) result.push_back(fd);
    }
    udev_device_unref(device);
  }
  udev_enumerate_unref(enumerate);
  udev_unref(udev_context);
  return result;
}

gpointer mouse_thread_main(gpointer) {
  std::vector<int> fds = open_mouse_devices();
  while (input != nullptr && input->mouse_running) {
    if (fds.empty()) {
      g_usleep(500000);
      fds = open_mouse_devices();
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
          if (event.value == 1) send_event_from_worker("pressed");
          if (event.value == 0) send_event_from_worker("released");
        }
      }
    }
  }
  for (const int fd : fds) close(fd);
  return nullptr;
}

void stop_mouse_listener() {
  if (input == nullptr || input->mouse_thread == nullptr) return;
  input->mouse_running = false;
  g_thread_join(input->mouse_thread);
  input->mouse_thread = nullptr;
  input->mouse_code = 0;
}

bool configure_mouse(int button) {
  const int code = evdev_code_for_mouse_button(button);
  if (code == 0) return false;
  // Verifica a permissão antes de responder ao Dart. O worker abre de novo
  // para manter os descritores isolados da thread de UI.
  std::vector<int> fds = open_mouse_devices();
  for (const int fd : fds) close(fd);
  if (fds.empty()) return false;
  input->mouse_code = code;
  input->mouse_running = true;
  input->mouse_thread = g_thread_new("fourfun-ptt-mouse", mouse_thread_main, nullptr);
  return true;
}

void close_session() {
  if (input == nullptr) return;
  stop_mouse_listener();
  if (input->bus == nullptr) return;
  if (input->activated_subscription != 0) {
    g_dbus_connection_signal_unsubscribe(input->bus,
                                         input->activated_subscription);
    input->activated_subscription = 0;
  }
  if (input->deactivated_subscription != 0) {
    g_dbus_connection_signal_unsubscribe(input->bus,
                                         input->deactivated_subscription);
    input->deactivated_subscription = 0;
  }
  if (input->request_subscription != 0) {
    g_dbus_connection_signal_unsubscribe(input->bus,
                                         input->request_subscription);
    input->request_subscription = 0;
  }
  if (input->session != nullptr) {
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
  return key;  // F1..F24 and named XKB keys already use this spelling.
}

std::string preferred_trigger(FlValue* arguments) {
  const FlValue* label_value = fl_value_lookup_string(arguments, "label");
  const char* label = label_value == nullptr
                          ? nullptr
                          : fl_value_get_string(const_cast<FlValue*>(label_value));
  std::string trigger = portal_key(label);
  const auto append = [&trigger](FlValue* value, const char* prefix) {
    if (value != nullptr && fl_value_get_bool(value)) trigger = std::string(prefix) + "+" + trigger;
  };
  append(fl_value_lookup_string(arguments, "shift"), "SHIFT");
  append(fl_value_lookup_string(arguments, "alt"), "ALT");
  append(fl_value_lookup_string(arguments, "control"), "CTRL");
  return trigger;
}

void on_shortcut_signal(GDBusConnection*, const gchar*, const gchar*,
                        const gchar*, const gchar*, GVariant* parameters,
                        gpointer user_data) {
  const bool pressed = GPOINTER_TO_INT(user_data) != 0;
  const gchar* session = nullptr;
  const gchar* shortcut_id = nullptr;
  g_variant_get(parameters, "(&o&st@a{sv})", &session, &shortcut_id, nullptr,
                nullptr);
  if (input != nullptr && input->session != nullptr &&
      g_strcmp0(session, input->session) == 0 &&
      g_strcmp0(shortcut_id, kPttId) == 0) {
    send_event(pressed ? "pressed" : "released");
  }
}

void bind_response(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                   const gchar*, GVariant* parameters, gpointer) {
  guint32 response = 2;
  g_autoptr(GVariant) results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &response, &results);
  if (response != 0) send_event("failed");
}

void bind_shortcut(const std::string& trigger) {
  if (input == nullptr || input->bus == nullptr || input->session == nullptr) {
    send_event("failed");
    return;
  }
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
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      input->bus, kPortalBus, kPortalPath, kPortalInterface, "BindShortcuts",
      g_variant_new("(o@a(sa{sv})s@a{sv})", input->session,
                    g_variant_builder_end(&shortcuts), "",
                    g_variant_builder_end(&options)), G_VARIANT_TYPE("(o)"),
      G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
  if (reply == nullptr) {
    g_warning("Push to Talk portal bind failed: %s", error->message);
    send_event("failed");
    return;
  }
  const gchar* request_path = nullptr;
  g_variant_get(reply, "(&o)", &request_path);
  input->request_subscription = g_dbus_connection_signal_subscribe(
      input->bus, kPortalBus, "org.freedesktop.portal.Request", "Response",
      request_path, nullptr, G_DBUS_SIGNAL_FLAGS_NONE, bind_response, nullptr,
      nullptr);
  input->activated_subscription = g_dbus_connection_signal_subscribe(
      input->bus, kPortalBus, kPortalInterface, "Activated", nullptr, nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, on_shortcut_signal, GINT_TO_POINTER(1), nullptr);
  input->deactivated_subscription = g_dbus_connection_signal_subscribe(
      input->bus, kPortalBus, kPortalInterface, "Deactivated", nullptr, nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, on_shortcut_signal, nullptr, nullptr);
}

void create_response(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                     const gchar*, GVariant* parameters, gpointer user_data) {
  guint32 response = 2;
  g_autoptr(GVariant) results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &response, &results);
  if (response != 0) {
    send_event("failed");
    return;
  }
  const gchar* session = nullptr;
  if (!g_variant_lookup(results, "session_handle", "&s", &session)) {
    send_event("failed");
    return;
  }
  input->session = g_strdup(session);
  bind_shortcut(static_cast<const char*>(user_data));
}

bool configure_keyboard(FlValue* arguments) {
  g_autoptr(GError) error = nullptr;
  input->bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (input->bus == nullptr) {
    g_warning("Push to Talk portal unavailable: %s", error->message);
    return false;
  }
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  const gchar* token = "fourfun_ptt";
  g_variant_builder_add(&options, "{sv}", "handle_token", g_variant_new_string(token));
  g_variant_builder_add(&options, "{sv}", "session_handle_token", g_variant_new_string("fourfun_ptt_session"));
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      input->bus, kPortalBus, kPortalPath, kPortalInterface, "CreateSession",
      g_variant_new("(@a{sv})", g_variant_builder_end(&options)),
      G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
  if (reply == nullptr) {
    g_warning("Push to Talk portal session failed: %s", error->message);
    return false;
  }
  const gchar* request_path = nullptr;
  g_variant_get(reply, "(&o)", &request_path);
  const std::string trigger = preferred_trigger(arguments);
  input->request_subscription = g_dbus_connection_signal_subscribe(
      input->bus, kPortalBus, "org.freedesktop.portal.Request", "Response",
      request_path, nullptr, G_DBUS_SIGNAL_FLAGS_NONE, create_response,
      g_strdup(trigger.c_str()), g_free);
  return true;
}

FlMethodErrorResponse* on_listen(FlEventChannel*, FlValue*, gpointer) {
  input->listening = true;
  return nullptr;
}

FlMethodErrorResponse* on_cancel(FlEventChannel*, FlValue*, gpointer) {
  input->listening = false;
  return nullptr;
}

void method_call(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "configure") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  close_session();
  FlValue* arguments = fl_method_call_get_args(call);
  if (arguments == nullptr || fl_value_get_type(arguments) == FL_VALUE_TYPE_NULL) {
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
  FlValue* mouse_button = fl_value_lookup_string(arguments, "mouseButton");
  const bool configured = keyboard
      ? configure_keyboard(arguments)
      : mouse && mouse_button != nullptr &&
          configure_mouse(static_cast<int>(fl_value_get_int(mouse_button)));
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(configured)));
  fl_method_call_respond(call, response, nullptr);
}

}  // namespace

void push_to_talk_input_register(FlBinaryMessenger* messenger) {
  input = new PttInput();
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* methods = fl_method_channel_new(
      messenger, "fourfun_cod/push_to_talk", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(methods, method_call, nullptr, nullptr);
  input->events = fl_event_channel_new(messenger, "fourfun_cod/push_to_talk_events",
                                       FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(input->events, on_listen, on_cancel,
                                       nullptr, nullptr);
}
