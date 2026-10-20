#include "audio_connection_bridge.h"
#include <flutter/standard_method_codec.h>
#include <mutex>
#include <optional>
#include <utility>
#include "audio_connection_snapshot.h"
#include "audio_connection_worker.h"
namespace bdk_audio {
namespace {
constexpr UINT kSnapshotMessage = WM_APP + 0xBD;
constexpr UINT_PTR kSnapshotTimer = 0xBDAC;
constexpr UINT kDeadlineMilliseconds = 3000;
AudioSnapshotWorker& Worker() {
  static AudioSnapshotWorker worker([] { return ReadWindowsAudioSnapshot(); });
  return worker;
}
flutter::EncodableValue Encode(const AudioSnapshotReport& report) {
  using flutter::EncodableValue;
  flutter::EncodableList devices;
  for (const auto& device : report.devices) {
    devices.emplace_back(flutter::EncodableMap{{EncodableValue("id"), EncodableValue(device.id)}, {EncodableValue("name"), EncodableValue(device.name)}});
  }
  return EncodableValue(flutter::EncodableMap{
    {EncodableValue("protocolVersion"), EncodableValue(1)},
    {EncodableValue("state"), EncodableValue(report.status == AudioSnapshotStatus::kUnsupported ? "unsupported" : "ready")},
    {EncodableValue("canVerifyIdentity"), EncodableValue(report.can_verify_identity)},
    {EncodableValue("devices"), EncodableValue(std::move(devices))},
    {EncodableValue("message"), EncodableValue(report.message)}});
}
}
struct AudioConnectionBridge::Receiver {
  std::mutex mutex;
  bool alive = true;
  HWND window = nullptr;
  uint64_t token = 0;
  std::optional<AudioSnapshotReport> report;
};
AudioConnectionBridge::AudioConnectionBridge(flutter::BinaryMessenger* messenger, HWND window)
    : receiver_(std::make_shared<Receiver>()), window_(window) {
  receiver_->window = window;
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger, "bdk_audio/audio_connection", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "snapshot") Snapshot(std::move(result));
    else result->NotImplemented();
  });
}
AudioConnectionBridge::~AudioConnectionBridge() {
  channel_->SetMethodCallHandler(nullptr);
  gate_.Close(); KillTimer(window_, kSnapshotTimer);
  {
    std::lock_guard<std::mutex> lock(receiver_->mutex);
    receiver_->alive = false; receiver_->report.reset();
  }
  // FlutterWindow destroys this bridge before destroying its engine/messenger.
  if (pending_) pending_->Error("audio_check_cancelled", "Windows audio check was cancelled.");
}
void AudioConnectionBridge::Snapshot(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto token = gate_.Begin(GetTickCount64(), kDeadlineMilliseconds);
  if (!token) { result->Error("audio_check_busy", "A Windows audio check is already pending."); return; }
  pending_token_ = *token; pending_ = std::move(result);
  if (!SetTimer(window_, kSnapshotTimer, kDeadlineMilliseconds, nullptr)) {
    Fail("audio_check_unavailable", "Windows could not start the audio check deadline."); return;
  }
  const std::weak_ptr<Receiver> weak = receiver_;
  if (!Worker().Submit([weak, token = *token](AudioSnapshotReport report) {
    const auto receiver = weak.lock();
    if (!receiver) return;
    HWND window = nullptr;
    {
      std::lock_guard<std::mutex> lock(receiver->mutex);
      if (!receiver->alive) return;
      receiver->token = token; receiver->report = std::move(report); window = receiver->window;
    }
    // Only a unique token is posted, never an allocation or Flutter object.
    // Reused HWNDs cannot accept a previous bridge's token.
    PostMessage(window, kSnapshotMessage, static_cast<WPARAM>(token), 0);
  })) Fail("audio_check_busy", "Windows is still completing an earlier audio check. Try again.");
}
void AudioConnectionBridge::Fail(const std::string& code, const std::string& message) {
  if (!pending_ || !gate_.Complete(pending_token_)) return;
  KillTimer(window_, kSnapshotTimer);
  auto result = std::move(pending_); result->Error(code, message);
}
bool AudioConnectionBridge::HandleMessage(UINT message, WPARAM wparam, LPARAM) {
  if (message == WM_TIMER && wparam == kSnapshotTimer) {
    if (gate_.DeadlineElapsed(GetTickCount64())) {
      Fail("audio_check_timeout", "Windows audio verification timed out. Try again.");
    }
    return true;
  }
  if (message != kSnapshotMessage) return false;
  if (!pending_ || static_cast<uint64_t>(wparam) != pending_token_) return true;
  std::optional<AudioSnapshotReport> report;
  {
    std::lock_guard<std::mutex> lock(receiver_->mutex);
    if (!receiver_->alive || receiver_->token != pending_token_ || !receiver_->report) return true;
    report = std::move(receiver_->report); receiver_->report.reset();
  }
  if (!gate_.Complete(pending_token_)) return true;
  KillTimer(window_, kSnapshotTimer);
  auto result = std::move(pending_);
  if (report->status == AudioSnapshotStatus::kUnavailable) result->Error("audio_check_incomplete", report->message);
  else result->Success(Encode(*report));
  return true;
}
}
