#ifndef BDK_AUDIO_CONNECTION_MODEL_H_
#define BDK_AUDIO_CONNECTION_MODEL_H_
#include <cstdint>
#include <optional>
#include <string>
#include <vector>
namespace bdk_audio {
enum class BluetoothAudioProfile { kA2dpSink, kA2dpSource, kHandsFree, kUnknownBluetooth, kNotBluetooth };
struct AudioEndpointEvidence { std::string container_id; std::string name; bool render = true; bool active = true; };
struct AudioAdapterEvidence { std::string container_id; std::string address; BluetoothAudioProfile profile = BluetoothAudioProfile::kNotBluetooth; bool present = true; };
struct BluetoothConnectionEvidence { std::string address; std::string name; bool connected = false; };
struct AudioEvidence { std::vector<AudioEndpointEvidence> endpoints; std::vector<AudioAdapterEvidence> adapters; std::vector<BluetoothConnectionEvidence> bluetooth; bool enumeration_complete = true; };
struct AudioIdentity { std::string id; std::string name; };
enum class AudioSnapshotStatus { kReady, kUnsupported, kUnavailable };
struct AudioSnapshotReport {
  AudioSnapshotStatus status = AudioSnapshotStatus::kUnavailable;
  bool can_verify_identity = false;
  std::vector<AudioIdentity> devices;
  std::string message;
  uint32_t active_render_endpoints = 0, present_audio_adapters = 0, a2dp_sink_adapters = 0, connected_classic_devices = 0, unsupported_active_routes = 0;
};
std::optional<std::string> NormalizeBluetoothAddress(const std::string& input);
AudioSnapshotReport ReduceAudioEvidence(const AudioEvidence& input);
// UI-thread request ownership. Tokens are unique across bridge/window lifetimes.
class AudioSnapshotRequestGate {
 public:
  std::optional<uint64_t> Begin(uint64_t now_ms = 0, uint64_t timeout_ms = 3000);
  bool DeadlineElapsed(uint64_t now_ms) const;
  bool Complete(uint64_t token);
  void Close();
 private:
  bool closed_ = false;
  std::optional<uint64_t> pending_;
  uint64_t deadline_ms_ = 0;
};
}  // namespace bdk_audio
#endif
