#include "flutter_media_stream.h"

#include "flutter_utf8_sanitize.h"
#include "task_runner.h"

#include <thread>

#define DEFAULT_WIDTH 1280
#define DEFAULT_HEIGHT 720
#define DEFAULT_FPS 30

namespace flutter_webrtc_plugin {

namespace {

std::string SanitizeDeviceIdFromAudioBuffers(const char *name,
                                             const char *guid) {
  const std::string raw = (guid != nullptr && strlen(guid) > 0)
                              ? std::string(guid)
                              : std::string(name != nullptr ? name : "");
  return SanitizeUtf8ForFlutter(raw);
}

std::string SanitizeLabel(const char *name) {
  return SanitizeUtf8ForFlutter(std::string(name != nullptr ? name : ""));
}

std::string SanitizeDeviceIdFromVideoBuffers(const char *name,
                                             const char *guid) {
  const std::string raw = (guid != nullptr && strlen(guid) > 0)
                              ? std::string(guid)
                              : std::string(name != nullptr ? name : "");
  return SanitizeUtf8ForFlutter(raw);
}

} // namespace

FlutterMediaStream::FlutterMediaStream(FlutterWebRTCBase *base) : base_(base) {
  base_->audio_device_->OnDeviceChange([&] {
    EncodableMap info;
    info[EncodableValue("event")] = "onDeviceChange";
    base_->event_channel()->Success(EncodableValue(info), false);
  });
}

void FlutterMediaStream::GetUserMedia(
    const EncodableMap &constraints,
    std::unique_ptr<MethodResultProxy> result) {
  std::string uuid = base_->GenerateUUID();
  scoped_refptr<RTCMediaStream> stream =
      base_->factory_->CreateStream(uuid.c_str());

  EncodableMap params;
  params[EncodableValue("streamId")] = EncodableValue(uuid);

  auto it = constraints.find(EncodableValue("audio"));
  if (it != constraints.end()) {
    EncodableValue audio = it->second;
    if (TypeIs<bool>(audio)) {
      if (true == GetValue<bool>(audio)) {
        GetUserAudio(constraints, stream, params);
      }
    } else if (TypeIs<EncodableMap>(audio)) {
      GetUserAudio(constraints, stream, params);
    } else {
      params[EncodableValue("audioTracks")] = EncodableValue(EncodableList());
    }
  } else {
    params[EncodableValue("audioTracks")] = EncodableValue(EncodableList());
  }

  it = constraints.find(EncodableValue("video"));
  params[EncodableValue("videoTracks")] = EncodableValue(EncodableList());
  if (it != constraints.end()) {
    EncodableValue video = it->second;
    if (TypeIs<bool>(video)) {
      if (true == GetValue<bool>(video)) {
        GetUserVideo(constraints, stream, uuid, std::move(params),
                     std::move(result));
        return;
      }
    } else if (TypeIs<EncodableMap>(video)) {
      GetUserVideo(constraints, stream, uuid, std::move(params),
                   std::move(result));
      return;
    }
  }

  base_->local_streams_[uuid] = stream;
  result->Success(EncodableValue(params));
}

void addDefaultAudioConstraints(
    scoped_refptr<RTCMediaConstraints> audioConstraints) {
  audioConstraints->AddOptionalConstraint("googNoiseSuppression", "true");
  audioConstraints->AddOptionalConstraint("googEchoCancellation", "true");
  audioConstraints->AddOptionalConstraint("echoCancellation", "true");
  audioConstraints->AddOptionalConstraint("googEchoCancellation2", "true");
  audioConstraints->AddOptionalConstraint("googDAEchoCancellation", "true");
}

// Reads a boolean audio-processing flag from the audio constraint map.
// Supports flat W3C keys, mandatory sub-map keys, and optional list entries
// (each a single-pair map, the format used by the LiveKit SDK and others).
// Accepts bool values or "true"/"false" strings. Falls back to defaultValue
// when the key is absent (W3C default is true for AEC/NS/AGC).
static bool getAudioProcessingFlag(const EncodableMap &audioMap,
                                   const std::vector<std::string> &keys,
                                   bool defaultValue) {
  auto readBoolValue = [](const EncodableValue &v, bool def) -> bool {
    if (TypeIs<bool>(v))
      return GetValue<bool>(v);
    if (TypeIs<std::string>(v)) {
      const std::string &s = GetValue<std::string>(v);
      if (s == "true")
        return true;
      if (s == "false")
        return false;
    }
    return def;
  };

  for (const std::string &key : keys) {
    // Flat W3C key at the top level.
    auto it = audioMap.find(EncodableValue(key));
    if (it != audioMap.end()) {
      return readBoolValue(it->second, defaultValue);
    }

    // Inside "mandatory" sub-map.
    auto mandatoryIt = audioMap.find(EncodableValue("mandatory"));
    if (mandatoryIt != audioMap.end() &&
        TypeIs<EncodableMap>(mandatoryIt->second)) {
      const EncodableMap &mandatory =
          GetValue<EncodableMap>(mandatoryIt->second);
      auto mit = mandatory.find(EncodableValue(key));
      if (mit != mandatory.end()) {
        return readBoolValue(mit->second, defaultValue);
      }
    }

    // Inside "optional" list — each entry is a single-pair map.
    auto optionalIt = audioMap.find(EncodableValue("optional"));
    if (optionalIt != audioMap.end() &&
        TypeIs<EncodableList>(optionalIt->second)) {
      const EncodableList &list = GetValue<EncodableList>(optionalIt->second);
      for (const EncodableValue &item : list) {
        if (!TypeIs<EncodableMap>(item))
          continue;
        const EncodableMap &entry = GetValue<EncodableMap>(item);
        auto eit = entry.find(EncodableValue(key));
        if (eit != entry.end()) {
          return readBoolValue(eit->second, defaultValue);
        }
      }
    }
  }
  return defaultValue;
}

std::string getSourceIdConstraint(const EncodableMap &mediaConstraints) {
  auto it = mediaConstraints.find(EncodableValue("optional"));
  if (it != mediaConstraints.end() && TypeIs<EncodableList>(it->second)) {
    EncodableList optional = GetValue<EncodableList>(it->second);
    for (size_t i = 0, size = optional.size(); i < size; i++) {
      if (TypeIs<EncodableMap>(optional[i])) {
        EncodableMap option = GetValue<EncodableMap>(optional[i]);
        auto it2 = option.find(EncodableValue("sourceId"));
        if (it2 != option.end() && TypeIs<std::string>(it2->second)) {
          return GetValue<std::string>(it2->second);
        }
      }
    }
  }
  return "";
}

std::string getDeviceIdConstraint(const EncodableMap &mediaConstraints) {
  auto it = mediaConstraints.find(EncodableValue("deviceId"));
  if (it != mediaConstraints.end() && TypeIs<std::string>(it->second)) {
    return GetValue<std::string>(it->second);
  }
  return "";
}

void FlutterMediaStream::GetUserAudio(const EncodableMap &constraints,
                                      scoped_refptr<RTCMediaStream> stream,
                                      EncodableMap &params) {
  bool enable_audio = false;
  scoped_refptr<RTCMediaConstraints> audioConstraints;
  RTCAudioOptions audio_options;
  std::string sourceId;
  std::string deviceId;
  auto it = constraints.find(EncodableValue("audio"));
  if (it != constraints.end()) {
    EncodableValue audio = it->second;
    if (TypeIs<bool>(audio)) {
      audioConstraints = RTCMediaConstraints::Create();
      addDefaultAudioConstraints(audioConstraints);
      enable_audio = GetValue<bool>(audio);
      sourceId = "";
      deviceId = "";
      // audio: true — keep software processing on (W3C/WebRTC default).
      audio_options.echo_cancellation = true;
      audio_options.noise_suppression = true;
      audio_options.auto_gain_control = true;
      audio_options.highpass_filter = false;
    }
    if (TypeIs<EncodableMap>(audio)) {
      EncodableMap localMap = GetValue<EncodableMap>(audio);
      sourceId = getSourceIdConstraint(localMap);
      deviceId = getDeviceIdConstraint(localMap);
      audioConstraints = base_->ParseMediaConstraints(localMap);
      enable_audio = true;
      // Map W3C/goog-prefixed constraint keys to RTCAudioOptions so the
      // software AEC/NS/AGC can actually be toggled from the Dart side.
      audio_options.echo_cancellation = getAudioProcessingFlag(
          localMap, {"echoCancellation", "googEchoCancellation"}, true);
      audio_options.noise_suppression = getAudioProcessingFlag(
          localMap, {"noiseSuppression", "googNoiseSuppression"}, true);
      audio_options.auto_gain_control = getAudioProcessingFlag(
          localMap, {"autoGainControl", "googAutoGainControl"}, true);
      audio_options.highpass_filter = getAudioProcessingFlag(
          localMap, {"highpassFilter", "googHighpassFilter"}, false);
    }
  }

  // Selecting audio input device by sourceId and audio output device by
  // deviceId

  if (enable_audio) {
    char strRecordingName[256];
    char strRecordingGuid[256];
    int playout_devices = base_->audio_device_->PlayoutDevices();
    int recording_devices = base_->audio_device_->RecordingDevices();

    for (uint16_t i = 0; i < recording_devices; i++) {
      base_->audio_device_->RecordingDeviceName(i, strRecordingName,
                                                strRecordingGuid);
      if (sourceId != "" &&
          sourceId == SanitizeDeviceIdFromAudioBuffers(strRecordingName,
                                                       strRecordingGuid)) {
        base_->audio_device_->SetRecordingDevice(i);
      }
    }

    if (sourceId == "") {
      base_->audio_device_->RecordingDeviceName(0, strRecordingName,
                                                strRecordingGuid);
      sourceId =
          SanitizeDeviceIdFromAudioBuffers(strRecordingName, strRecordingGuid);
      base_->audio_device_->SetRecordingDevice(0);
    }

    char strPlayoutName[256];
    char strPlayoutGuid[256];
    for (uint16_t i = 0; i < playout_devices; i++) {
      base_->audio_device_->PlayoutDeviceName(i, strPlayoutName,
                                              strPlayoutGuid);
      if (deviceId != "" && deviceId == SanitizeDeviceIdFromAudioBuffers(
                                            strPlayoutName, strPlayoutGuid)) {
        base_->audio_device_->SetPlayoutDevice(i);
      }
    }

    scoped_refptr<RTCAudioSource> source = base_->factory_->CreateAudioSource(
        "audio_input", RTCAudioSource::SourceType::kMicrophone, audio_options);
    std::string uuid = base_->GenerateUUID();
    scoped_refptr<RTCAudioTrack> track =
        base_->factory_->CreateAudioTrack(source, uuid.c_str());

    std::string track_id = track->id().std_string();

    EncodableMap track_info;
    track_info[EncodableValue("id")] = EncodableValue(track->id().std_string());
    track_info[EncodableValue("label")] =
        EncodableValue(track->id().std_string());
    track_info[EncodableValue("kind")] =
        EncodableValue(track->kind().std_string());
    track_info[EncodableValue("enabled")] = EncodableValue(track->enabled());

    EncodableMap settings;
    settings[EncodableValue("deviceId")] =
        EncodableValue(SanitizeUtf8ForFlutter(sourceId));
    settings[EncodableValue("kind")] = EncodableValue("audioinput");
    settings[EncodableValue("autoGainControl")] =
        EncodableValue(audio_options.auto_gain_control);
    settings[EncodableValue("echoCancellation")] =
        EncodableValue(audio_options.echo_cancellation);
    settings[EncodableValue("noiseSuppression")] =
        EncodableValue(audio_options.noise_suppression);
    settings[EncodableValue("channelCount")] = EncodableValue(1);
    settings[EncodableValue("latency")] = EncodableValue(0);
    track_info[EncodableValue("settings")] = EncodableValue(settings);

    EncodableList audioTracks;
    audioTracks.push_back(EncodableValue(track_info));
    params[EncodableValue("audioTracks")] = EncodableValue(audioTracks);
    stream->AddTrack(track);

    base_->local_tracks_[track->id().std_string()] = track;
  }
}

std::string getFacingMode(const EncodableMap &mediaConstraints) {
  return mediaConstraints.find(EncodableValue("facingMode")) !=
                 mediaConstraints.end()
             ? GetValue<std::string>(
                   mediaConstraints.find(EncodableValue("facingMode"))->second)
             : "";
}

EncodableValue getConstrainInt(const EncodableMap &constraints,
                               const std::string &key) {
  EncodableValue value;
  auto it = constraints.find(EncodableValue(key));
  if (it != constraints.end()) {
    if (TypeIs<int>(it->second)) {
      return it->second;
    }

    if (TypeIs<EncodableMap>(it->second)) {
      EncodableMap innerMap = GetValue<EncodableMap>(it->second);
      auto it2 = innerMap.find(EncodableValue("ideal"));
      if (it2 != innerMap.end() && TypeIs<int>(it2->second)) {
        return it2->second;
      }
    }
  }

  return EncodableValue();
}

void FlutterMediaStream::GetUserVideo(
    const EncodableMap &constraints, scoped_refptr<RTCMediaStream> stream,
    const std::string &stream_id, EncodableMap params,
    std::unique_ptr<MethodResultProxy> result) {
  EncodableMap video_constraints;
  EncodableMap video_mandatory;
  auto it = constraints.find(EncodableValue("video"));
  if (it != constraints.end() && TypeIs<EncodableMap>(it->second)) {
    video_constraints = GetValue<EncodableMap>(it->second);
    if (video_constraints.find(EncodableValue("mandatory")) !=
        video_constraints.end()) {
      video_mandatory = GetValue<EncodableMap>(
          video_constraints.find(EncodableValue("mandatory"))->second);
    }
  }

  std::string facing_mode = getFacingMode(video_constraints);
  // bool isFacing = facing_mode == "" || facing_mode != "environment";
  std::string sourceId = getSourceIdConstraint(video_constraints);

  EncodableValue widthValue = getConstrainInt(video_constraints, "width");

  if (widthValue == EncodableValue())
    widthValue = findEncodableValue(video_mandatory, "minWidth");

  if (widthValue == EncodableValue())
    widthValue = findEncodableValue(video_mandatory, "width");

  EncodableValue heightValue = getConstrainInt(video_constraints, "height");

  if (heightValue == EncodableValue())
    heightValue = findEncodableValue(video_mandatory, "minHeight");

  if (heightValue == EncodableValue())
    heightValue = findEncodableValue(video_mandatory, "height");

  EncodableValue fpsValue = getConstrainInt(video_constraints, "frameRate");

  if (fpsValue == EncodableValue())
    fpsValue = findEncodableValue(video_mandatory, "minFrameRate");

  if (fpsValue == EncodableValue())
    fpsValue = findEncodableValue(video_mandatory, "frameRate");

  int32_t width = toInt(widthValue, DEFAULT_WIDTH);
  int32_t height = toInt(heightValue, DEFAULT_HEIGHT);
  int32_t fps = toInt(fpsValue, DEFAULT_FPS);
  // A enumeração e a abertura V4L2 podem bloquear no primeiro acesso à
  // webcam. Não toque nelas na thread da plataforma: o bottom sheet precisa
  // continuar pintando e respondendo enquanto a câmera inicializa.
  auto *base = base_;
  auto video_device = base_->video_device_;
  auto result_ptr = std::shared_ptr<MethodResultProxy>(result.release());
  std::thread([base, video_device, stream, stream_id,
               video_constraints = std::move(video_constraints),
               source_id = std::move(sourceId), width, height, fps,
               params = std::move(params), result_ptr]() mutable {
    scoped_refptr<RTCVideoCapturer> video_capturer;
    char device_name[256] = {0};
    char device_guid[256] = {0};
    const uint32_t device_count = video_device->NumberOfDevices();

    for (uint32_t i = 0; i < device_count; ++i) {
      video_device->GetDeviceName(i, device_name, sizeof(device_name),
                                  device_guid, sizeof(device_guid));
      if (!source_id.empty() &&
          source_id == SanitizeDeviceIdFromVideoBuffers(device_name,
                                                         device_guid)) {
        video_capturer =
            video_device->Create(device_name, i, width, height, fps);
        break;
      }
    }

    if (video_capturer == nullptr && device_count > 0) {
      video_device->GetDeviceName(0, device_name, sizeof(device_name),
                                  device_guid, sizeof(device_guid));
      source_id = SanitizeDeviceIdFromVideoBuffers(device_name, device_guid);
      video_capturer =
          video_device->Create(device_name, 0, width, height, fps);
    }

    const bool capture_started =
        video_capturer != nullptr && video_capturer->StartCapture();
    auto finish_on_platform_thread =
        [base, video_capturer, capture_started, stream, stream_id,
         video_constraints = std::move(video_constraints),
         source_id = std::move(source_id), width, height, fps,
         params = std::move(params), result_ptr]() mutable {
      if (!capture_started) {
        if (video_capturer != nullptr && video_capturer->CaptureStarted()) {
          video_capturer->StopCapture();
        }
        result_ptr->Error("GetUserMedia",
                          "Não foi possível iniciar a câmera.");
        return;
      }

      const char *video_source_label = "video_input";
      scoped_refptr<RTCVideoSource> source = base->factory_->CreateVideoSource(
          video_capturer, video_source_label,
          base->ParseMediaConstraints(video_constraints));
      if (source == nullptr) {
        video_capturer->StopCapture();
        result_ptr->Error("GetUserMedia",
                          "Não foi possível criar a source de vídeo.");
        return;
      }

      std::string uuid = base->GenerateUUID();
      scoped_refptr<RTCVideoTrack> track =
          base->factory_->CreateVideoTrack(source, uuid.c_str());
      if (track == nullptr) {
        video_capturer->StopCapture();
        result_ptr->Error("GetUserMedia",
                          "Não foi possível criar a track de vídeo.");
        return;
      }

      EncodableList videoTracks;
      EncodableMap info;
      info[EncodableValue("id")] = EncodableValue(track->id().std_string());
      info[EncodableValue("label")] = EncodableValue(track->id().std_string());
      info[EncodableValue("kind")] = EncodableValue(track->kind().std_string());
      info[EncodableValue("enabled")] = EncodableValue(track->enabled());

      EncodableMap settings;
      settings[EncodableValue("deviceId")] =
          EncodableValue(SanitizeUtf8ForFlutter(source_id));
      settings[EncodableValue("kind")] = EncodableValue("videoinput");
      settings[EncodableValue("width")] = EncodableValue(width);
      settings[EncodableValue("height")] = EncodableValue(height);
      settings[EncodableValue("frameRate")] = EncodableValue(fps);
      info[EncodableValue("settings")] = EncodableValue(settings);

      videoTracks.push_back(EncodableValue(info));
      params[EncodableValue("videoTracks")] = EncodableValue(videoTracks);

      stream->AddTrack(track);
      // O renderer e o disposal local localizam a stream por este mapa. Sem
      // ele o preview fica preto e StopCapture nunca é alcançado no close.
      base->local_streams_[stream_id] = stream;
      base->local_tracks_[track->id().std_string()] = track;
      base->video_capturers_[track->id().std_string()] = video_capturer;
      result_ptr->Success(EncodableValue(params));
    };

    if (base->task_runner_ != nullptr) {
      base->task_runner_->EnqueueTask(std::move(finish_on_platform_thread));
    } else {
      finish_on_platform_thread();
    }
  }).detach();
}

void FlutterMediaStream::GetSources(std::unique_ptr<MethodResultProxy> result) {
  EncodableList sources;

  int nb_audio_devices = base_->audio_device_->RecordingDevices();
  char strNameUTF8[RTCAudioDevice::kAdmMaxDeviceNameSize + 1] = {0};
  char strGuidUTF8[RTCAudioDevice::kAdmMaxGuidSize + 1] = {0};

  for (uint16_t i = 0; i < nb_audio_devices; i++) {
    base_->audio_device_->RecordingDeviceName(i, strNameUTF8, strGuidUTF8);
    std::string device_id =
        SanitizeDeviceIdFromAudioBuffers(strNameUTF8, strGuidUTF8);
    EncodableMap audio;
    audio[EncodableValue("label")] = EncodableValue(SanitizeLabel(strNameUTF8));
    audio[EncodableValue("deviceId")] = EncodableValue(device_id);
    audio[EncodableValue("facing")] = "";
    audio[EncodableValue("kind")] = "audioinput";
    sources.push_back(EncodableValue(audio));
  }

  nb_audio_devices = base_->audio_device_->PlayoutDevices();
  for (uint16_t i = 0; i < nb_audio_devices; i++) {
    base_->audio_device_->PlayoutDeviceName(i, strNameUTF8, strGuidUTF8);
    std::string device_id =
        SanitizeDeviceIdFromAudioBuffers(strNameUTF8, strGuidUTF8);
    EncodableMap audio;
    audio[EncodableValue("label")] = EncodableValue(SanitizeLabel(strNameUTF8));
    audio[EncodableValue("deviceId")] = EncodableValue(device_id);
    audio[EncodableValue("facing")] = "";
    audio[EncodableValue("kind")] = "audiooutput";
    sources.push_back(EncodableValue(audio));
  }

  int nb_video_devices = base_->video_device_->NumberOfDevices();
  for (int i = 0; i < nb_video_devices; i++) {
    base_->video_device_->GetDeviceName(i, strNameUTF8, 128, strGuidUTF8, 128);
    EncodableMap video;
    video[EncodableValue("label")] = EncodableValue(SanitizeLabel(strNameUTF8));
    video[EncodableValue("deviceId")] = EncodableValue(
        SanitizeDeviceIdFromVideoBuffers(strNameUTF8, strGuidUTF8));
    video[EncodableValue("facing")] = i == 1 ? "front" : "back";
    video[EncodableValue("kind")] = "videoinput";
    sources.push_back(EncodableValue(video));
  }
  EncodableMap params;
  params[EncodableValue("sources")] = EncodableValue(sources);
  result->Success(EncodableValue(params));
}

void FlutterMediaStream::SelectAudioOutput(
    const std::string &device_id, std::unique_ptr<MethodResultProxy> result) {
  char deviceName[256];
  char deviceGuid[256];
  int playout_devices = base_->audio_device_->PlayoutDevices();
  bool found = false;
  for (uint16_t i = 0; i < playout_devices; i++) {
    base_->audio_device_->PlayoutDeviceName(i, deviceName, deviceGuid);
    std::string cur_device_id =
        SanitizeDeviceIdFromAudioBuffers(deviceName, deviceGuid);
    if (device_id != "" && device_id == cur_device_id) {
      base_->audio_device_->SetPlayoutDevice(i);
      found = true;
      break;
    }
  }
  if (!found) {
    result->Error("Bad Arguments",
                  "Not found device id: " + SanitizeUtf8ForFlutter(device_id));
    return;
  }
  result->Success();
}

void FlutterMediaStream::SelectAudioInput(
    const std::string &device_id, std::unique_ptr<MethodResultProxy> result) {
  char deviceName[256];
  char deviceGuid[256];
  int playout_devices = base_->audio_device_->RecordingDevices();
  bool found = false;
  for (uint16_t i = 0; i < playout_devices; i++) {
    base_->audio_device_->RecordingDeviceName(i, deviceName, deviceGuid);
    std::string cur_device_id =
        SanitizeDeviceIdFromAudioBuffers(deviceName, deviceGuid);
    if (device_id != "" && device_id == cur_device_id) {
      base_->audio_device_->SetRecordingDevice(i);
      found = true;
      break;
    }
  }
  if (!found) {
    result->Error("Bad Arguments",
                  "Not found device id: " + SanitizeUtf8ForFlutter(device_id));
    return;
  }
  result->Success();
}

void FlutterMediaStream::MediaStreamGetTracks(
    const std::string &stream_id, std::unique_ptr<MethodResultProxy> result) {
  scoped_refptr<RTCMediaStream> stream = base_->MediaStreamForId(stream_id);

  if (stream) {
    EncodableMap params;
    EncodableList audioTracks;

    auto audio_tracks = stream->audio_tracks();
    for (auto track : audio_tracks.std_vector()) {
      base_->local_tracks_[track->id().std_string()] = track;
      EncodableMap info;
      info[EncodableValue("id")] = EncodableValue(track->id().std_string());
      info[EncodableValue("label")] = EncodableValue(track->id().std_string());
      info[EncodableValue("kind")] = EncodableValue(track->kind().std_string());
      info[EncodableValue("enabled")] = EncodableValue(track->enabled());
      info[EncodableValue("remote")] = EncodableValue(true);
      info[EncodableValue("readyState")] = "live";
      audioTracks.push_back(EncodableValue(info));
    }
    params[EncodableValue("audioTracks")] = EncodableValue(audioTracks);

    EncodableList videoTracks;
    auto video_tracks = stream->video_tracks();
    for (auto track : video_tracks.std_vector()) {
      base_->local_tracks_[track->id().std_string()] = track;
      EncodableMap info;
      info[EncodableValue("id")] = EncodableValue(track->id().std_string());
      info[EncodableValue("label")] = EncodableValue(track->id().std_string());
      info[EncodableValue("kind")] = EncodableValue(track->kind().std_string());
      info[EncodableValue("enabled")] = EncodableValue(track->enabled());
      info[EncodableValue("remote")] = EncodableValue(true);
      info[EncodableValue("readyState")] = "live";
      videoTracks.push_back(EncodableValue(info));
    }

    params[EncodableValue("videoTracks")] = EncodableValue(videoTracks);

    result->Success(EncodableValue(params));
  } else {
    result->Error("MediaStreamGetTracksFailed",
                  "MediaStreamGetTracks() media stream is null !");
  }
}

void FlutterMediaStream::MediaStreamDispose(
    const std::string &stream_id, std::unique_ptr<MethodResultProxy> result) {
  scoped_refptr<RTCMediaStream> stream = base_->MediaStreamForId(stream_id);

  if (!stream) {
    result->Error("MediaStreamDisposeFailed",
                  "stream [" + stream_id + "] not found!");
    return;
  }

  vector<scoped_refptr<RTCAudioTrack>> audio_tracks = stream->audio_tracks();

  for (auto track : audio_tracks.std_vector()) {
    stream->RemoveTrack(track);
    base_->local_tracks_.erase(track->id().std_string());
  }

  vector<scoped_refptr<RTCVideoTrack>> video_tracks = stream->video_tracks();
  for (auto track : video_tracks.std_vector()) {
    stream->RemoveTrack(track);
    base_->local_tracks_.erase(track->id().std_string());
    if (base_->video_capturers_.find(track->id().std_string()) !=
        base_->video_capturers_.end()) {
      auto video_capture = base_->video_capturers_[track->id().std_string()];
      if (video_capture->CaptureStarted()) {
        video_capture->StopCapture();
      }
      base_->video_capturers_.erase(track->id().std_string());
    }
  }

  base_->RemoveStreamForId(stream_id);
  result->Success();
}

void FlutterMediaStream::CreateLocalMediaStream(
    std::unique_ptr<MethodResultProxy> result) {
  std::string uuid = base_->GenerateUUID();
  scoped_refptr<RTCMediaStream> stream =
      base_->factory_->CreateStream(uuid.c_str());

  EncodableMap params;
  params[EncodableValue("streamId")] = EncodableValue(uuid);

  base_->local_streams_[uuid] = stream;
  result->Success(EncodableValue(params));
}

void FlutterMediaStream::MediaStreamTrackSetEnable(
    const std::string &track_id, std::unique_ptr<MethodResultProxy> result) {
  result->NotImplemented();
}

void FlutterMediaStream::MediaStreamTrackSwitchCamera(
    const std::string &track_id, std::unique_ptr<MethodResultProxy> result) {
  result->NotImplemented();
}

void FlutterMediaStream::MediaStreamTrackDispose(
    const std::string &track_id, std::unique_ptr<MethodResultProxy> result) {
  for (auto it : base_->local_streams_) {
    auto stream = it.second;
    auto audio_tracks = stream->audio_tracks();
    for (auto track : audio_tracks.std_vector()) {
      if (track->id().std_string() == track_id) {
        stream->RemoveTrack(track);
      }
    }
    auto video_tracks = stream->video_tracks();
    for (auto track : video_tracks.std_vector()) {
      if (track->id().std_string() == track_id) {
        stream->RemoveTrack(track);

        if (base_->video_capturers_.find(track_id) !=
            base_->video_capturers_.end()) {
          auto video_capture = base_->video_capturers_[track_id];
          if (video_capture->CaptureStarted()) {
            video_capture->StopCapture();
          }
          base_->video_capturers_.erase(track_id);
        }
      }
    }
  }
  base_->RemoveMediaTrackForId(track_id);
  result->Success();
}
} // namespace flutter_webrtc_plugin
