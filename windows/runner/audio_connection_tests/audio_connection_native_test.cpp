#include "../audio_connection_model.h"
#include "../audio_connection_snapshot.h"
#include "../audio_connection_worker.h"
#include <atomic>
#include <chrono>
#include <future>
#include <thread>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <vector>
using namespace bdk_audio;
void Require(bool value, const char* label) { if (!value) throw std::runtime_error(label); }
AudioEvidence Verified() {
  AudioEvidence evidence;
  evidence.endpoints.push_back({"{container-a}", "Output", true, true});
  evidence.adapters.push_back({"{container-a}", "a1b2c3d4e5f6", BluetoothAudioProfile::kA2dpSink, true});
  evidence.bluetooth.push_back({"A1:B2:C3:D4:E5:F6", "BDK synthetic test", true});
  return evidence;
}
int main(int argc, char** argv) {
  if (argc == 2 && std::string(argv[1]) == "--inspect") {
    const auto start = std::chrono::steady_clock::now();
    auto completed = std::make_shared<std::promise<AudioSnapshotReport>>();
    auto snapshot = completed->get_future();
    AudioSnapshotWorker worker([] { return ReadWindowsAudioSnapshot(); });
    worker.Submit([completed](AudioSnapshotReport report) { completed->set_value(std::move(report)); });
    if (snapshot.wait_for(std::chrono::seconds(3)) != std::future_status::ready) {
      worker.Close();
      std::cout << "{\"status\":\"timeout\",\"canVerifyIdentity\":false,\"verifiedRouteCount\":0}\n";
      return 0;
    }
    const auto result = snapshot.get();
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
    const char* status = result.status == AudioSnapshotStatus::kReady ? "ready" : result.status == AudioSnapshotStatus::kUnsupported ? "unsupported" : "unavailable";
    std::cout << "{\"status\":\"" << status << "\",\"canVerifyIdentity\":" << (result.can_verify_identity ? "true" : "false")
      << ",\"activeRenderEndpoints\":" << result.active_render_endpoints << ",\"presentAudioAdapters\":" << result.present_audio_adapters
      << ",\"a2dpSinkAdapters\":" << result.a2dp_sink_adapters << ",\"connectedClassicDevices\":" << result.connected_classic_devices
      << ",\"verifiedRouteCount\":" << result.devices.size() << ",\"unsupportedActiveRoutes\":" << result.unsupported_active_routes
      << ",\"elapsedMs\":" << elapsed << "}\n";
    return 0;
  }
  std::vector<std::pair<const char*, std::function<void()>>> tests = {
    {"active render + A2DP sink + container + connected MAC joins verified identity", [] {
      auto result = ReduceAudioEvidence(Verified());
      Require(result.can_verify_identity && result.devices.size() == 1, "verified evidence excluded");
      Require(result.devices[0].id == "a1:b2:c3:d4:e5:f6", "address byte order changed");
      Require(result.devices[0].name == "BDK synthetic test", "display metadata lost");
    }},
    {"paired or present without actual connected flag is excluded", [] {
      auto evidence = Verified(); evidence.bluetooth[0].connected = false;
      Require(ReduceAudioEvidence(evidence).devices.empty(), "paired device treated connected");
    }},
    {"inactive and capture endpoints cannot authorize an audio route", [] {
      auto evidence = Verified(); evidence.endpoints[0].active = false;
      Require(ReduceAudioEvidence(evidence).devices.empty(), "inactive route admitted");
      evidence.endpoints[0].active = true; evidence.endpoints[0].render = false;
      Require(ReduceAudioEvidence(evidence).devices.empty(), "capture route admitted");
    }},
    {"USB HFP source and unknown profile are never A2DP sink proof", [] {
      for (auto profile : {BluetoothAudioProfile::kNotBluetooth, BluetoothAudioProfile::kHandsFree, BluetoothAudioProfile::kA2dpSource, BluetoothAudioProfile::kUnknownBluetooth}) {
        auto evidence = Verified(); evidence.adapters[0].profile = profile;
        Require(ReduceAudioEvidence(evidence).devices.empty(), "non-sink profile admitted");
      }
    }},
    {"name equality and a different container do not prove physical identity", [] {
      auto evidence = Verified(); evidence.adapters[0].container_id = "{other-container}";
      evidence.endpoints[0].name = evidence.bluetooth[0].name;
      Require(ReduceAudioEvidence(evidence).devices.empty(), "name match used as identity proof");
    }},
    {"ambiguous same-container addresses reject mapping rather than selecting first", [] {
      auto evidence = Verified(); evidence.adapters.push_back({"{container-a}", "123456789abc", BluetoothAudioProfile::kA2dpSink, true});
      evidence.bluetooth.push_back({"12:34:56:78:9a:bc", "Other synthetic device", true});
      auto result = ReduceAudioEvidence(evidence);
      Require(result.devices.empty() && !result.can_verify_identity, "ambiguous container admitted");
    }},
    {"invalid address and missing container produce unsupported mapping", [] {
      auto evidence = Verified(); evidence.adapters[0].address = "not-a-mac";
      auto result = ReduceAudioEvidence(evidence);
      Require(result.devices.empty() && !result.can_verify_identity, "invalid MAC mapped");
      evidence = Verified(); evidence.endpoints[0].container_id.clear();
      Require(!ReduceAudioEvidence(evidence).can_verify_identity, "missing container declared verified");
    }},
    {"duplicates collapse without crossing unrelated endpoint containers", [] {
      auto evidence = Verified(); evidence.endpoints.push_back(evidence.endpoints[0]);
      evidence.adapters.push_back(evidence.adapters[0]);
      Require(ReduceAudioEvidence(evidence).devices.size() == 1, "duplicate identities published");
    }},
    {"empty complete enumeration differs from failed enumeration", [] {
      AudioEvidence evidence;
      Require(ReduceAudioEvidence(evidence).can_verify_identity, "empty enumeration fabricated unsupported state");
      evidence.enumeration_complete = false;
      auto result = ReduceAudioEvidence(evidence);
      Require(!result.can_verify_identity && result.devices.empty(), "partial failed enumeration admitted");
    }},
    {"address normalization rejects truncation separators zero and broadcast", [] {
      Require(NormalizeBluetoothAddress("A1B2C3D4E5F6").value() == "a1:b2:c3:d4:e5:f6", "canonical MAC wrong");
      for (const auto* address : {"", "a1:b2:c3:d4:e5", "a1:b2-c3:d4:e5:f6", "000000000000", "ffffffffffff", "zzzzzzzzzzzz"})
        Require(!NormalizeBluetoothAddress(address), "malformed address accepted");
    }},
    {"generation gate rejects late duplicate timed-out and destroyed-window results", [] {
      AudioSnapshotRequestGate first;
      auto old = first.Begin(); Require(old.has_value() && !first.Begin(), "parallel request accepted");
      Require(first.Complete(*old), "current reply lost"); auto fresh = first.Begin();
      Require(!first.Complete(*old) && first.Complete(*fresh), "late result completed new request");
      first.Close(); Require(!first.Begin() && !first.Complete(*fresh), "closed gate revived");
      AudioSnapshotRequestGate second; auto next = second.Begin();
      Require(*next != *old && *next != *fresh, "new bridge reused old token");
    }},
    {"queued timer from expired request cannot expire its fresh replacement", [] {
      AudioSnapshotRequestGate gate;
      const auto first = gate.Begin(100, 20);
      Require(!gate.DeadlineElapsed(119) && gate.DeadlineElapsed(120), "deadline ignored");
      Require(gate.Complete(*first), "first request not expired");
      const auto next = gate.Begin(120, 20);
      Require(!gate.DeadlineElapsed(120), "old queued timer expired new request");
      Require(gate.DeadlineElapsed(140) && gate.Complete(*next), "new deadline lost");
      Require(!gate.DeadlineElapsed(141), "idle timer changed state");
    }},
    {"native worker bounds concurrent physical queries without blocking submit", [] {
      auto release = std::make_shared<std::promise<void>>(); auto released = release->get_future().share();
      auto started = std::make_shared<std::promise<void>>(); auto started_future = started->get_future();
      auto complete = std::make_shared<std::promise<void>>(); auto completed = complete->get_future();
      AudioSnapshotWorker worker([released, started] { started->set_value(); released.wait(); return ReduceAudioEvidence(Verified()); });
      Require(worker.Submit([complete](AudioSnapshotReport result) { Require(result.devices.size() == 1, "worker changed evidence"); complete->set_value(); }), "first query refused");
      Require(started_future.wait_for(std::chrono::seconds(1)) == std::future_status::ready, "worker did not start");
      const bool overlap = worker.Submit([](AudioSnapshotReport) {});
      release->set_value();
      Require(!overlap, "unbounded overlapping native query accepted");
      Require(completed.wait_for(std::chrono::seconds(1)) == std::future_status::ready, "worker completion missing");
    }},
    {"shutdown returns while query is blocked and suppresses its late completion", [] {
      auto release = std::make_shared<std::promise<void>>(); auto released = release->get_future().share();
      auto started = std::make_shared<std::promise<void>>(); auto started_future = started->get_future();
      auto called = std::make_shared<std::atomic<bool>>(false);
      AudioSnapshotWorker worker([released, started] { started->set_value(); released.wait(); return ReduceAudioEvidence(Verified()); });
      Require(worker.Submit([called](AudioSnapshotReport) { *called = true; }), "query refused");
      Require(started_future.wait_for(std::chrono::seconds(1)) == std::future_status::ready, "worker did not start");
      const auto began = std::chrono::steady_clock::now(); worker.Close();
      const auto elapsed = std::chrono::steady_clock::now() - began;
      release->set_value();
      Require(elapsed < std::chrono::milliseconds(200), "shutdown joined a blocked query");
      Require(!worker.Submit([](AudioSnapshotReport) {}), "closed worker revived");
      const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(1);
      while (worker.busy() && std::chrono::steady_clock::now() < deadline) std::this_thread::yield();
      Require(!worker.busy() && !*called, "late completion survived shutdown");
    }},
  };
  int failures = 0;
  for (const auto& test : tests) {
    try { test.second(); std::cout << "PASS " << test.first << '\n'; }
    catch (const std::exception& error) { failures++; std::cout << "FAIL " << test.first << ": " << error.what() << '\n'; }
  }
  return failures == 0 ? 0 : 1;
}
