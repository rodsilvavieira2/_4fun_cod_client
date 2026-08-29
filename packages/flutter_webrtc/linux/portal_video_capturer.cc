#include "portal_video_capturer.h"

#include <chrono>
#include <cstdint>
#include <sstream>
#include <unistd.h>
#include <utility>

#include <gio/gunixfdlist.h>
#include <gst/app/gstappsink.h>
#include <gst/video/video.h>

#include "rtc_video_frame.h"

namespace flutter_webrtc_plugin {
namespace {

constexpr char kPortalService[] = "org.freedesktop.portal.Desktop";
constexpr char kPortalPath[] = "/org/freedesktop/portal/desktop";
constexpr char kScreenCastInterface[] = "org.freedesktop.portal.ScreenCast";
constexpr char kRequestInterface[] = "org.freedesktop.portal.Request";
constexpr char kSessionInterface[] = "org.freedesktop.portal.Session";
constexpr char kRequestPathPrefix[] =
    "/org/freedesktop/portal/desktop/request/";
constexpr guint kPortalSourceMonitor = 1u;
constexpr guint kPortalSourceWindow = 2u;
constexpr guint kCursorModeEmbedded = 2u;

std::string NextToken(const char *prefix) {
  static std::atomic<uint64_t> sequence{0};
  std::ostringstream token;
  token << prefix << "_" << g_get_monotonic_time() << "_" << sequence++;
  return token.str();
}

std::string GErrorMessage(const char *operation, GError *error) {
  std::string message(operation);
  message += ": ";
  message += error == nullptr ? "unknown error" : error->message;
  return message;
}

std::string RequestPath(GDBusConnection *connection,
                        const std::string &handle_token) {
  const char *unique_name = g_dbus_connection_get_unique_name(connection);
  if (unique_name == nullptr || unique_name[0] != ':') {
    return {};
  }

  std::string sender(unique_name + 1);
  for (char &character : sender) {
    if (character == '.') {
      character = '_';
    }
  }
  return std::string(kRequestPathPrefix) + sender + "/" + handle_token;
}

} // namespace

struct PortalVideoCapturer::RequestWait {
  PortalVideoCapturer *capturer = nullptr;
  GMainLoop *loop = nullptr;
  std::string request_path;
  guint response = 2;
  GVariant *results = nullptr;
  bool completed = false;
};

PortalVideoCapturer::PortalVideoCapturer() = default;

PortalVideoCapturer::~PortalVideoCapturer() { StopCapture(); }

void PortalVideoCapturer::SetVideoSource(
    libwebrtc::scoped_refptr<libwebrtc::RTCVideoSource> source) {
  std::lock_guard<std::mutex> lock(mutex_);
  video_source_ = std::move(source);
}

bool PortalVideoCapturer::StartCapture() {
  std::unique_lock<std::mutex> lock(mutex_);
  if (capture_started_) {
    return true;
  }
  if (worker_.joinable()) {
    return false;
  }
  if (!video_source_) {
    last_error_ = "custom video source is not configured";
    return false;
  }

  stop_requested_ = false;
  setup_finished_ = false;
  setup_succeeded_ = false;
  last_error_.clear();
  worker_ = std::thread(&PortalVideoCapturer::Run, this);
  setup_condition_.wait(lock, [this] { return setup_finished_; });
  const bool success = setup_succeeded_;
  lock.unlock();

  if (!success && worker_.joinable()) {
    worker_.join();
  }
  return success;
}

bool PortalVideoCapturer::CaptureStarted() { return capture_started_.load(); }

void PortalVideoCapturer::StopCapture() {
  stop_requested_ = true;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (cancellable_ != nullptr) {
      g_cancellable_cancel(cancellable_);
    }
  }
  if (worker_.joinable() && worker_.get_id() != std::this_thread::get_id()) {
    worker_.join();
  }
  capture_started_ = false;
}

std::string PortalVideoCapturer::last_error() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return last_error_;
}

void PortalVideoCapturer::OnPortalResponse(GDBusConnection *, const gchar *,
                                           const gchar *object_path,
                                           const gchar *, const gchar *,
                                           GVariant *parameters,
                                           gpointer user_data) {
  auto *wait = static_cast<RequestWait *>(user_data);
  if (!wait->request_path.empty() && wait->request_path != object_path) {
    return;
  }

  GVariant *results = nullptr;
  g_variant_get(parameters, "(u@a{sv})", &wait->response, &results);
  if (wait->results != nullptr) {
    g_variant_unref(wait->results);
  }
  wait->results = results;
  wait->completed = true;
  g_main_loop_quit(wait->loop);
}

gboolean PortalVideoCapturer::CheckPortalWait(gpointer user_data) {
  auto *wait = static_cast<RequestWait *>(user_data);
  if (wait->capturer->stop_requested_) {
    g_main_loop_quit(wait->loop);
    return G_SOURCE_REMOVE;
  }
  return G_SOURCE_CONTINUE;
}

bool PortalVideoCapturer::RunPortalRequest(
    GDBusConnection *connection, GMainContext *context,
    const char *interface_name, const char *method_name,
    const std::string &handle_token, GVariant *parameters, GVariant **results) {
  RequestWait wait;
  wait.capturer = this;
  wait.loop = g_main_loop_new(context, FALSE);
  wait.request_path = RequestPath(connection, handle_token);
  if (wait.request_path.empty()) {
    SetError(std::string(method_name) + " could not build its request path");
    g_main_loop_unref(wait.loop);
    return false;
  }

  const guint subscription = g_dbus_connection_signal_subscribe(
      connection, kPortalService, kRequestInterface, "Response",
      wait.request_path.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      &PortalVideoCapturer::OnPortalResponse, &wait, nullptr);

  GError *error = nullptr;
  GVariant *reply = g_dbus_connection_call_sync(
      connection, kPortalService, kPortalPath, interface_name, method_name,
      parameters, G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1,
      cancellable_, &error);
  if (reply == nullptr) {
    SetError(GErrorMessage(method_name, error));
    g_clear_error(&error);
    g_dbus_connection_signal_unsubscribe(connection, subscription);
    g_main_loop_unref(wait.loop);
    return false;
  }

  const gchar *returned_request_path = nullptr;
  g_variant_get(reply, "(&o)", &returned_request_path);
  const bool request_path_matches = wait.request_path == returned_request_path;
  g_variant_unref(reply);
  if (!request_path_matches) {
    SetError(std::string(method_name) + " returned an unexpected request path");
    g_dbus_connection_signal_unsubscribe(connection, subscription);
    g_main_loop_unref(wait.loop);
    return false;
  }

  GSource *check_source = g_timeout_source_new(100);
  g_source_set_callback(check_source, &PortalVideoCapturer::CheckPortalWait,
                        &wait, nullptr);
  g_source_attach(check_source, context);
  g_main_loop_run(wait.loop);
  g_source_destroy(check_source);
  g_source_unref(check_source);

  g_dbus_connection_signal_unsubscribe(connection, subscription);
  g_main_loop_unref(wait.loop);

  if (!wait.completed || stop_requested_) {
    if (wait.results != nullptr) {
      g_variant_unref(wait.results);
    }
    SetError(std::string(method_name) + " was cancelled");
    return false;
  }
  if (wait.response != 0) {
    if (wait.results != nullptr) {
      g_variant_unref(wait.results);
    }
    SetError(std::string(method_name) + " was denied by the user");
    return false;
  }

  *results = wait.results;
  return true;
}

bool PortalVideoCapturer::OpenPortal(GDBusConnection *connection,
                                     GMainContext *context,
                                     std::string *session_handle,
                                     uint32_t *node_id, int *pipewire_fd) {
  GVariantBuilder create_options;
  g_variant_builder_init(&create_options, G_VARIANT_TYPE_VARDICT);
  const std::string create_token = NextToken("create");
  const std::string session_token = NextToken("session");
  g_variant_builder_add(&create_options, "{sv}", "handle_token",
                        g_variant_new_string(create_token.c_str()));
  g_variant_builder_add(&create_options, "{sv}", "session_handle_token",
                        g_variant_new_string(session_token.c_str()));

  GVariant *results = nullptr;
  if (!RunPortalRequest(connection, context, kScreenCastInterface,
                        "CreateSession", create_token,
                        g_variant_new("(a{sv})", &create_options), &results)) {
    return false;
  }

  const gchar *session = nullptr;
  // The value is an object path semantically, but the portal API originally
  // exposed it as a string and preserves that wire type for compatibility.
  const bool has_session =
      g_variant_lookup(results, "session_handle", "&s", &session);
  if (has_session) {
    *session_handle = session;
  }
  g_variant_unref(results);
  if (!has_session || session_handle->empty()) {
    SetError("CreateSession returned no session handle");
    return false;
  }

  GVariantBuilder select_options;
  g_variant_builder_init(&select_options, G_VARIANT_TYPE_VARDICT);
  const std::string select_token = NextToken("select");
  g_variant_builder_add(&select_options, "{sv}", "handle_token",
                        g_variant_new_string(select_token.c_str()));
  g_variant_builder_add(
      &select_options, "{sv}", "types",
      g_variant_new_uint32(kPortalSourceMonitor | kPortalSourceWindow));
  g_variant_builder_add(&select_options, "{sv}", "multiple",
                        g_variant_new_boolean(FALSE));
  g_variant_builder_add(&select_options, "{sv}", "cursor_mode",
                        g_variant_new_uint32(kCursorModeEmbedded));

  if (!RunPortalRequest(
          connection, context, kScreenCastInterface, "SelectSources",
          select_token,
          g_variant_new("(oa{sv})", session_handle->c_str(), &select_options),
          &results)) {
    return false;
  }
  g_variant_unref(results);

  GVariantBuilder start_options;
  g_variant_builder_init(&start_options, G_VARIANT_TYPE_VARDICT);
  const std::string start_token = NextToken("start");
  g_variant_builder_add(&start_options, "{sv}", "handle_token",
                        g_variant_new_string(start_token.c_str()));

  if (!RunPortalRequest(connection, context, kScreenCastInterface, "Start",
                        start_token,
                        g_variant_new("(osa{sv})", session_handle->c_str(), "",
                                      &start_options),
                        &results)) {
    return false;
  }

  GVariant *streams =
      g_variant_lookup_value(results, "streams", G_VARIANT_TYPE("a(ua{sv})"));
  if (streams == nullptr || g_variant_n_children(streams) == 0) {
    if (streams != nullptr) {
      g_variant_unref(streams);
    }
    g_variant_unref(results);
    SetError("Start returned no PipeWire streams");
    return false;
  }

  GVariant *stream = g_variant_get_child_value(streams, 0);
  GVariant *properties = nullptr;
  guint selected_node = 0;
  g_variant_get(stream, "(u@a{sv})", &selected_node, &properties);
  *node_id = selected_node;
  g_variant_unref(properties);
  g_variant_unref(stream);
  g_variant_unref(streams);
  g_variant_unref(results);

  GVariantBuilder remote_options;
  g_variant_builder_init(&remote_options, G_VARIANT_TYPE_VARDICT);
  GUnixFDList *fd_list = nullptr;
  GError *error = nullptr;
  GVariant *fd_reply = g_dbus_connection_call_with_unix_fd_list_sync(
      connection, kPortalService, kPortalPath, kScreenCastInterface,
      "OpenPipeWireRemote",
      g_variant_new("(oa{sv})", session_handle->c_str(), &remote_options),
      G_VARIANT_TYPE("(h)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &fd_list,
      cancellable_, &error);
  if (fd_reply == nullptr) {
    SetError(GErrorMessage("OpenPipeWireRemote", error));
    g_clear_error(&error);
    return false;
  }

  gint fd_index = -1;
  g_variant_get(fd_reply, "(h)", &fd_index);
  g_variant_unref(fd_reply);
  *pipewire_fd = g_unix_fd_list_get(fd_list, fd_index, &error);
  g_object_unref(fd_list);
  if (*pipewire_fd < 0) {
    SetError(GErrorMessage("Get PipeWire fd", error));
    g_clear_error(&error);
    return false;
  }
  return true;
}

bool PortalVideoCapturer::StartPipeline(uint32_t node_id, int pipewire_fd) {
  gst_init(nullptr, nullptr);

  std::ostringstream pipeline_description;
  pipeline_description << "pipewiresrc fd=" << pipewire_fd
                       << " path=" << node_id
                       << " do-timestamp=true ! videoconvert ! "
                          "video/x-raw,format=I420 ! appsink "
                          "name=portal_sink sync=false max-buffers=1 drop=true";

  GError *error = nullptr;
  GstElement *pipeline =
      gst_parse_launch(pipeline_description.str().c_str(), &error);
  if (pipeline == nullptr) {
    SetError(GErrorMessage("Create PipeWire pipeline", error));
    g_clear_error(&error);
    return false;
  }

  GstElement *sink = gst_bin_get_by_name(GST_BIN(pipeline), "portal_sink");
  if (sink == nullptr) {
    gst_object_unref(pipeline);
    SetError("PipeWire pipeline has no app sink");
    return false;
  }

  const GstStateChangeReturn state =
      gst_element_set_state(pipeline, GST_STATE_PLAYING);
  if (state == GST_STATE_CHANGE_FAILURE) {
    gst_object_unref(sink);
    gst_object_unref(pipeline);
    SetError("PipeWire pipeline failed to start");
    return false;
  }
  if (state == GST_STATE_CHANGE_ASYNC) {
    const GstStateChangeReturn settled =
        gst_element_get_state(pipeline, nullptr, nullptr, 5 * GST_SECOND);
    if (settled == GST_STATE_CHANGE_FAILURE ||
        settled == GST_STATE_CHANGE_ASYNC) {
      gst_element_set_state(pipeline, GST_STATE_NULL);
      gst_object_unref(sink);
      gst_object_unref(pipeline);
      SetError("PipeWire pipeline did not reach the playing state");
      return false;
    }
  }

  {
    std::lock_guard<std::mutex> lock(mutex_);
    pipeline_ = pipeline;
    app_sink_ = sink;
    pipewire_fd_ = pipewire_fd;
  }
  return true;
}

void PortalVideoCapturer::CaptureLoop() {
  while (!stop_requested_) {
    GstSample *sample = gst_app_sink_try_pull_sample(GST_APP_SINK(app_sink_),
                                                     100 * GST_MSECOND);
    if (sample == nullptr) {
      continue;
    }

    GstCaps *caps = gst_sample_get_caps(sample);
    GstBuffer *buffer = gst_sample_get_buffer(sample);
    GstVideoInfo info;
    gst_video_info_init(&info);
    if (caps == nullptr || buffer == nullptr ||
        !gst_video_info_from_caps(&info, caps)) {
      gst_sample_unref(sample);
      continue;
    }

    GstVideoFrame frame;
    if (!gst_video_frame_map(&frame, &info, buffer, GST_MAP_READ)) {
      gst_sample_unref(sample);
      continue;
    }

    const auto rtc_frame = libwebrtc::RTCVideoFrame::Create(
        GST_VIDEO_FRAME_WIDTH(&frame), GST_VIDEO_FRAME_HEIGHT(&frame),
        static_cast<const uint8_t *>(GST_VIDEO_FRAME_PLANE_DATA(&frame, 0)),
        GST_VIDEO_FRAME_PLANE_STRIDE(&frame, 0),
        static_cast<const uint8_t *>(GST_VIDEO_FRAME_PLANE_DATA(&frame, 1)),
        GST_VIDEO_FRAME_PLANE_STRIDE(&frame, 1),
        static_cast<const uint8_t *>(GST_VIDEO_FRAME_PLANE_DATA(&frame, 2)),
        GST_VIDEO_FRAME_PLANE_STRIDE(&frame, 2));
    if (rtc_frame && video_source_) {
      video_source_->OnCapturedFrame(rtc_frame);
    }

    gst_video_frame_unmap(&frame);
    gst_sample_unref(sample);
  }
}

void PortalVideoCapturer::Run() {
  GMainContext *context = g_main_context_new();
  g_main_context_push_thread_default(context);

  {
    std::lock_guard<std::mutex> lock(mutex_);
    cancellable_ = g_cancellable_new();
  }

  GError *error = nullptr;
  GDBusConnection *connection =
      g_bus_get_sync(G_BUS_TYPE_SESSION, cancellable_, &error);
  if (connection == nullptr) {
    FinishSetup(false, GErrorMessage("Connect to session bus", error));
    g_clear_error(&error);
    goto cleanup_context;
  }

  {
    std::string session_handle;
    uint32_t node_id = 0;
    int pipewire_fd = -1;
    if (!OpenPortal(connection, context, &session_handle, &node_id,
                    &pipewire_fd)) {
      FinishSetup(false, last_error());
    } else if (!StartPipeline(node_id, pipewire_fd)) {
      close(pipewire_fd);
      FinishSetup(false, last_error());
    } else {
      capture_started_ = true;
      FinishSetup(true);
      CaptureLoop();
      capture_started_ = false;

      GstElement *pipeline = nullptr;
      GstElement *sink = nullptr;
      int owned_pipewire_fd = -1;
      {
        std::lock_guard<std::mutex> lock(mutex_);
        pipeline = pipeline_;
        sink = app_sink_;
        owned_pipewire_fd = pipewire_fd_;
        pipeline_ = nullptr;
        app_sink_ = nullptr;
        pipewire_fd_ = -1;
      }
      if (pipeline != nullptr) {
        gst_element_set_state(pipeline, GST_STATE_NULL);
      }
      if (sink != nullptr) {
        gst_object_unref(sink);
      }
      if (pipeline != nullptr) {
        gst_object_unref(pipeline);
      }
      if (owned_pipewire_fd >= 0) {
        close(owned_pipewire_fd);
      }
    }

    if (!session_handle.empty()) {
      g_dbus_connection_call_sync(
          connection, kPortalService, session_handle.c_str(), kSessionInterface,
          "Close", nullptr, nullptr, G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
          nullptr);
    }
  }

  g_object_unref(connection);

cleanup_context: {
  std::lock_guard<std::mutex> lock(mutex_);
  if (cancellable_ != nullptr) {
    g_object_unref(cancellable_);
    cancellable_ = nullptr;
  }
}
  g_main_context_pop_thread_default(context);
  g_main_context_unref(context);
}

void PortalVideoCapturer::FinishSetup(bool success, const std::string &error) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!error.empty()) {
    last_error_ = error;
  }
  setup_succeeded_ = success;
  setup_finished_ = true;
  setup_condition_.notify_all();
}

void PortalVideoCapturer::SetError(const std::string &error) {
  std::lock_guard<std::mutex> lock(mutex_);
  last_error_ = error;
}

} // namespace flutter_webrtc_plugin
