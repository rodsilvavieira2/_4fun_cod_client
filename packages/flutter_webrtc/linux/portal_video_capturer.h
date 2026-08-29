#ifndef FLUTTER_WEBRTC_PORTAL_VIDEO_CAPTURER_H_
#define FLUTTER_WEBRTC_PORTAL_VIDEO_CAPTURER_H_

#include <atomic>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <string>
#include <thread>

#include <gio/gio.h>
#include <gst/gst.h>

#include "rtc_video_device.h"
#include "rtc_video_source.h"

namespace flutter_webrtc_plugin {

// Captures a single user-selected monitor or window through
// xdg-desktop-portal + PipeWire. The portal owns the only source-selection UI;
// unlike RTCDesktopMediaList, this path does not enumerate sources first.
// RefCountedObject<PortalVideoCapturer> supplies AddRef/Release, so this class
// must remain inheritable even though it is only instantiated through that
// wrapper.
class PortalVideoCapturer : public libwebrtc::RTCVideoCapturer {
public:
  PortalVideoCapturer();
  ~PortalVideoCapturer() override;

  void
  SetVideoSource(libwebrtc::scoped_refptr<libwebrtc::RTCVideoSource> source);

  using SetupCallback = std::function<void(bool success)>;

  // Starts the portal flow without waiting on the Flutter platform thread.
  // The callback runs after the portal session and PipeWire pipeline are ready
  // (or after setup fails).
  bool StartCaptureAsync(SetupCallback callback);

  bool StartCapture() override;
  bool CaptureStarted() override;
  void StopCapture() override;

  std::string last_error() const;

private:
  struct RequestWait;

  static void OnPortalResponse(GDBusConnection *connection,
                               const gchar *sender_name,
                               const gchar *object_path,
                               const gchar *interface_name,
                               const gchar *signal_name, GVariant *parameters,
                               gpointer user_data);
  static gboolean CheckPortalWait(gpointer user_data);

  bool RunPortalRequest(GDBusConnection *connection, GMainContext *context,
                        const char *interface_name, const char *method_name,
                        const std::string &handle_token, GVariant *parameters,
                        GVariant **results);
  bool OpenPortal(GDBusConnection *connection, GMainContext *context,
                  std::string *session_handle, uint32_t *node_id,
                  int *pipewire_fd);
  bool StartPipeline(uint32_t node_id, int pipewire_fd);
  void CaptureLoop();
  void Run(SetupCallback setup_callback);
  void FinishSetup(bool success, const std::string &error = std::string());
  void SetError(const std::string &error);

  mutable std::mutex mutex_;
  std::condition_variable setup_condition_;
  std::thread worker_;
  std::atomic<bool> stop_requested_{false};
  std::atomic<bool> capture_started_{false};
  bool setup_finished_ = false;
  bool setup_succeeded_ = false;
  std::string last_error_;

  libwebrtc::scoped_refptr<libwebrtc::RTCVideoSource> video_source_;
  GCancellable *cancellable_ = nullptr;
  GstElement *pipeline_ = nullptr;
  GstElement *app_sink_ = nullptr;
  int pipewire_fd_ = -1;
};

} // namespace flutter_webrtc_plugin

#endif // FLUTTER_WEBRTC_PORTAL_VIDEO_CAPTURER_H_
