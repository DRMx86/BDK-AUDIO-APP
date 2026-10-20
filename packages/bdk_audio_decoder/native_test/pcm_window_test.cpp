#undef NDEBUG
#include "bdk_audio_platform.h"
#include <cassert>
#include <limits>

int main() {
  bdk_audio_info info{8000, 2, 10000};
  BdkPcmWindow valid;
  assert(valid.init(info, 8000, 2000, 100) == 0);
  std::vector<float> pcm(5000 * 2);
  for (size_t i = 0; i < 5000; i++) {
    pcm[i * 2] = 10000.0f / 32768;
    pcm[i * 2 + 1] = -2000.0f / 32768;
  }
  // A real decoder may return a payload offset inside a larger output buffer.
  std::vector<uint8_t> offset(16 + pcm.size() * 4);
  std::memcpy(offset.data() + 16, pcm.data(), pcm.size() * 4);
  assert(valid.add(offset.data() + 16, 5000, 2, true, 0) == 0);
  int16_t output[100];
  assert(valid.finish(output) == 0);
  for (auto sample : output)
    assert(sample == 4000);
  BdkPcmWindow gap;
  assert(gap.init(info, 8000, 0, 100) == 0);
  assert(gap.add(reinterpret_cast<const uint8_t *>(pcm.data()), 50, 2, true,
                 0) == 0);
  assert(gap.add(reinterpret_cast<const uint8_t *>(pcm.data()), 100, 2, true,
                 60) == BDK_AUDIO_DECODE_FAILED);
  assert(gap.finish(output) == BDK_AUDIO_DECODE_FAILED);
  BdkPcmWindow shortRead;
  assert(shortRead.init(info, 8000, 0, 100) == 0);
  assert(shortRead.add(reinterpret_cast<const uint8_t *>(pcm.data()), 50, 2,
                       true, 0) == 0);
  assert(shortRead.finish(output) == BDK_AUDIO_DECODE_FAILED);
  BdkPcmWindow invalid;
  assert(invalid.init(info, 8000, UINT64_MAX, 100) == BDK_AUDIO_RANGE);
  BdkPcmWindow changed;
  assert(changed.init(info, 8000, 0, 100) == 0);
  assert(changed.add(reinterpret_cast<const uint8_t *>(pcm.data()), 100, 1,
                     true, 0) == BDK_AUDIO_DECODE_FAILED);
  BdkPcmWindow nonfinite;
  assert(nonfinite.init(info, 8000, 0, 100) == 0);
  pcm[0] = std::numeric_limits<float>::quiet_NaN();
  assert(nonfinite.add(reinterpret_cast<const uint8_t *>(pcm.data()), 100, 2,
                       true, 0) == BDK_AUDIO_CORRUPT);
}
