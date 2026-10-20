#ifndef BDK_AUDIO_CONNECTION_WORKER_H_
#define BDK_AUDIO_CONNECTION_WORKER_H_
#include "audio_connection_model.h"
#include <functional>
#include <memory>
namespace bdk_audio {
// One non-overlapping read-only native job. The process-scoped production worker
// never owns Flutter objects, and shutdown never joins an uninterruptible OS call.
class AudioSnapshotWorker {
 public:
  using Query = std::function<AudioSnapshotReport()>;
  using Completion = std::function<void(AudioSnapshotReport)>;
  explicit AudioSnapshotWorker(Query query);
  ~AudioSnapshotWorker();
  bool Submit(Completion completion);
  void Close();
  bool busy() const;
 private:
  struct State;
  std::shared_ptr<State> state_;
};
}
#endif
