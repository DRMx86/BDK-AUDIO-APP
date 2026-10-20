#include "audio_connection_model.h"
#include <algorithm>
#include <atomic>
#include <cctype>
#include <map>
#include <limits>
#include <set>
namespace bdk_audio {
namespace {
std::string Lower(std::string text) {
  std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return text;
}
std::atomic<uint64_t> next_request{1};
}
std::optional<std::string> NormalizeBluetoothAddress(const std::string& input) {
  std::string digits;
  if (input.size() == 12) digits = input;
  else if (input.size() == 17) {
    const char separator = input[2];
    if (separator != ':' && separator != '-') return std::nullopt;
    for (size_t i = 0; i < input.size(); ++i) {
      if (i % 3 == 2) { if (input[i] != separator) return std::nullopt; }
      else digits.push_back(input[i]);
    }
  } else return std::nullopt;
  if (!std::all_of(digits.begin(), digits.end(), [](unsigned char c) { return std::isxdigit(c) != 0; })) return std::nullopt;
  digits = Lower(digits);
  if (digits == "000000000000" || digits == "ffffffffffff") return std::nullopt;
  std::string address;
  for (size_t i = 0; i < digits.size(); i += 2) { if (i) address += ':'; address += digits.substr(i, 2); }
  return address;
}
AudioSnapshotReport ReduceAudioEvidence(const AudioEvidence& input) {
  AudioSnapshotReport result;
  result.present_audio_adapters = static_cast<uint32_t>(std::count_if(input.adapters.begin(), input.adapters.end(), [](const auto& a) { return a.present; }));
  result.a2dp_sink_adapters = static_cast<uint32_t>(std::count_if(input.adapters.begin(), input.adapters.end(), [](const auto& a) { return a.present && a.profile == BluetoothAudioProfile::kA2dpSink; }));
  result.connected_classic_devices = static_cast<uint32_t>(std::count_if(input.bluetooth.begin(), input.bluetooth.end(), [](const auto& b) { return b.connected; }));
  if (!input.enumeration_complete) {
    result.message = "Windows audio connection information is incomplete. Try again.";
    return result;
  }
  std::map<std::string, std::string> connected;
  for (const auto& device : input.bluetooth) {
    const auto address = NormalizeBluetoothAddress(device.address);
    if (device.connected && address) connected.emplace(*address, device.name);
  }
  std::map<std::string, AudioIdentity> verified;
  for (const auto& endpoint : input.endpoints) {
    if (!endpoint.active || !endpoint.render) continue;
    result.active_render_endpoints++;
    if (endpoint.container_id.empty()) { result.unsupported_active_routes++; continue; }
    std::set<std::string> candidate_addresses;
    bool unsupported = false;
    for (const auto& adapter : input.adapters) {
      if (!adapter.present || adapter.container_id.empty() || Lower(adapter.container_id) != Lower(endpoint.container_id)) continue;
      if (adapter.profile == BluetoothAudioProfile::kUnknownBluetooth) unsupported = true;
      if (adapter.profile != BluetoothAudioProfile::kA2dpSink) continue;
      const auto address = NormalizeBluetoothAddress(adapter.address);
      if (!address) unsupported = true;
      else candidate_addresses.insert(*address);
    }
    if (unsupported || candidate_addresses.size() > 1) { result.unsupported_active_routes++; continue; }
    if (candidate_addresses.size() != 1) continue;
    const auto address = *candidate_addresses.begin();
    const auto device = connected.find(address);
    if (device == connected.end()) continue;
    auto name = device->second.empty() ? endpoint.name : device->second;
    if (name.empty()) name = "Bluetooth audio device";
    verified.emplace(address, AudioIdentity{address, name});
  }
  for (auto& item : verified) result.devices.push_back(std::move(item.second));
  result.can_verify_identity = result.unsupported_active_routes == 0 || !result.devices.empty();
  result.status = result.unsupported_active_routes > 0 ? AudioSnapshotStatus::kUnsupported : AudioSnapshotStatus::kReady;
  if (result.unsupported_active_routes > 0) result.message = "This Windows audio driver does not expose a verified Bluetooth speaker identity. Connect a supported audio route and try again.";
  else if (result.devices.empty()) result.message = "Connect your speaker for Bluetooth audio in Windows Settings, then return here.";
  return result;
}
std::optional<uint64_t> AudioSnapshotRequestGate::Begin(uint64_t now_ms, uint64_t timeout_ms) {
  if (closed_ || pending_) return std::nullopt;
  deadline_ms_ = timeout_ms > std::numeric_limits<uint64_t>::max() - now_ms ?
    std::numeric_limits<uint64_t>::max() : now_ms + timeout_ms;
  pending_ = next_request.fetch_add(1); return pending_;
}
bool AudioSnapshotRequestGate::DeadlineElapsed(uint64_t now_ms) const {
  return !closed_ && pending_.has_value() && now_ms >= deadline_ms_;
}
bool AudioSnapshotRequestGate::Complete(uint64_t token) {
  if (closed_ || !pending_ || *pending_ != token) return false;
  pending_.reset(); return true;
}
void AudioSnapshotRequestGate::Close() { closed_ = true; pending_.reset(); }
}  // namespace bdk_audio
