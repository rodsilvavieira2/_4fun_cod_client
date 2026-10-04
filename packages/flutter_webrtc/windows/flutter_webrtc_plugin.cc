#include "flutter_webrtc/flutter_web_r_t_c_plugin.h"

#include "flutter_common.h"
#include "flutter_webrtc.h"
#include "task_runner_windows.h"
#include "window_share_candidates.h"

#include <flutter/plugin_registrar_windows.h>

const char* kChannelName = "FlutterWebRTC.Method";
static flutter_webrtc_plugin::FlutterWebRTC* g_shared_instance = nullptr;

namespace flutter_webrtc_plugin {

// A webrtc plugin for windows/linux.
class FlutterWebRTCPluginImpl : public FlutterWebRTCPlugin {
 public:
  static void RegisterWithRegistrar(PluginRegistrar* registrar) {
    auto channel = std::make_unique<MethodChannel>(
        registrar->messenger(), kChannelName,
        &flutter::StandardMethodCodec::GetInstance());

    auto* channel_pointer = channel.get();

    // Uses new instead of make_unique due to private constructor.
    std::unique_ptr<FlutterWebRTCPluginImpl> plugin(
        new FlutterWebRTCPluginImpl(registrar, std::move(channel)));
    channel_pointer->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  virtual ~FlutterWebRTCPluginImpl() {}

  BinaryMessenger* messenger() { return messenger_; }

  TextureRegistrar* textures() { return textures_; }

  TaskRunner* task_runner() { return task_runner_.get(); }

 private:
  // Creates a plugin that communicates on the given channel.
  FlutterWebRTCPluginImpl(PluginRegistrar* registrar,
                          std::unique_ptr<MethodChannel> channel)
      : channel_(std::move(channel)),
        messenger_(registrar->messenger()),
        textures_(registrar->texture_registrar()),
        task_runner_(std::make_unique<TaskRunnerWindows>()) {
    webrtc_ = std::make_unique<FlutterWebRTC>(this);
    g_shared_instance = webrtc_.get();
  }

  // Called when a method is called on |channel_|;
  void HandleMethodCall(const MethodCall& method_call,
                        std::unique_ptr<MethodResult> result) {
    if (method_call.method_name() == "fourfunGetShareWindows") {
      EncodableList windows;
      for (const auto& window : EnumerateShareWindows()) {
        windows.emplace_back(EncodableMap{
            {EncodableValue("id"), EncodableValue(window.id)},
            {EncodableValue("name"), EncodableValue(window.name)},
            {EncodableValue("processId"), EncodableValue(int64_t(window.process_id))},
            {EncodableValue("minimized"), EncodableValue(window.minimized)},
        });
      }
      result->Success(EncodableValue(windows));
      return;
    }
    if (method_call.method_name() == "fourfunGetShareWindowState") {
      if (!method_call.arguments() ||
          !std::holds_alternative<EncodableMap>(*method_call.arguments())) {
        result->Error("Bad Arguments", "Window identity is required");
        return;
      }
      const auto& args = std::get<EncodableMap>(*method_call.arguments());
      const auto id = args.find(EncodableValue("id"));
      const auto pid = args.find(EncodableValue("processId"));
      if (id == args.end() || pid == args.end() ||
          !std::holds_alternative<std::string>(id->second) ||
          !(std::holds_alternative<int32_t>(pid->second) ||
            std::holds_alternative<int64_t>(pid->second))) {
        result->Error("Bad Arguments", "Invalid window identity");
        return;
      }
      const int64_t process_id = std::holds_alternative<int32_t>(pid->second)
          ? std::get<int32_t>(pid->second) : std::get<int64_t>(pid->second);
      if (process_id <= 0 || process_id > UINT32_MAX) {
        result->Error("Bad Arguments", "Invalid window process");
        return;
      }
      const auto state = ReadShareWindowState(std::get<std::string>(id->second),
                                              uint32_t(process_id));
      result->Success(EncodableValue(EncodableMap{
          {EncodableValue("valid"), EncodableValue(state.valid)},
          {EncodableValue("visible"), EncodableValue(state.visible)},
          {EncodableValue("minimized"), EncodableValue(state.minimized)},
          {EncodableValue("foreground"), EncodableValue(state.foreground)},
      }));
      return;
    }
    // handle method call and forward to webrtc native sdk.
    auto method_call_proxy = MethodCallProxy::Create(method_call);
    webrtc_->HandleMethodCall(*method_call_proxy.get(),
                              MethodResultProxy::Create(std::move(result)));
  }

 private:
  std::unique_ptr<MethodChannel> channel_;
  std::unique_ptr<FlutterWebRTC> webrtc_;
  BinaryMessenger* messenger_;
  TextureRegistrar* textures_;
  std::unique_ptr<TaskRunner> task_runner_;
};

}  // namespace flutter_webrtc_plugin


void FlutterWebRTCPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  flutter_webrtc_plugin::FlutterWebRTCPluginImpl::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}

flutter_webrtc_plugin::FlutterWebRTC* FlutterWebRTCPluginSharedInstance() {
  return g_shared_instance;
}
