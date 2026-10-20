#ifndef BDK_AUDIO_CONNECTION_BRIDGE_H_
#define BDK_AUDIO_CONNECTION_BRIDGE_H_
#include <Windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include "audio_connection_model.h"
namespace bdk_audio {
class AudioConnectionBridge {
 public:
  AudioConnectionBridge(flutter::BinaryMessenger* messenger, HWND window);
  ~AudioConnectionBridge();
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);
 private:
  struct Receiver;
  void Snapshot(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Fail(const std::string& code, const std::string& message);
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> pending_;
  std::shared_ptr<Receiver> receiver_;
  AudioSnapshotRequestGate gate_;
  uint64_t pending_token_ = 0;
  HWND window_;
};
}
#endif
