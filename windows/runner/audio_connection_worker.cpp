#include "audio_connection_worker.h"
#include <condition_variable>
#include <mutex>
#include <thread>
#include <utility>
namespace bdk_audio {
struct AudioSnapshotWorker::State {
  mutable std::mutex mutex;
  std::condition_variable changed;
  bool closed = false, busy = false;
  Completion completion;
};
AudioSnapshotWorker::AudioSnapshotWorker(Query query) : state_(std::make_shared<State>()) {
  // The worker owns only its State/query. The production singleton bounds this
  // at one thread/query per process, including while an OS call outlives a UI
  // deadline. No Flutter object is retained or touched off the platform thread.
  std::thread([state = state_, query = std::move(query)] {
    for (;;) {
      Completion completion;
      {
        std::unique_lock<std::mutex> lock(state->mutex);
        state->changed.wait(lock, [&] { return state->closed || static_cast<bool>(state->completion); });
        if (state->closed) { state->busy = false; return; }
        completion = std::move(state->completion);
      }
      AudioSnapshotReport result;
      try { result = query(); }
      catch (...) { result.message = "Windows could not check Bluetooth audio. Try again."; }
      bool deliver = false;
      {
        std::lock_guard<std::mutex> lock(state->mutex);
        state->busy = false; deliver = !state->closed;
      }
      // The receiver also checks its own alive flag/generation, closing the race
      // between this delivery decision and window/channel destruction.
      if (deliver) { try { completion(std::move(result)); } catch (...) {} }
    }
  }).detach();
}
AudioSnapshotWorker::~AudioSnapshotWorker() { Close(); }
bool AudioSnapshotWorker::Submit(Completion completion) {
  std::lock_guard<std::mutex> lock(state_->mutex);
  if (state_->closed || state_->busy || !completion) return false;
  state_->busy = true; state_->completion = std::move(completion);
  state_->changed.notify_one(); return true;
}
void AudioSnapshotWorker::Close() {
  std::lock_guard<std::mutex> lock(state_->mutex);
  state_->closed = true; state_->completion = nullptr; state_->changed.notify_one();
}
bool AudioSnapshotWorker::busy() const {
  std::lock_guard<std::mutex> lock(state_->mutex); return state_->busy;
}
}
