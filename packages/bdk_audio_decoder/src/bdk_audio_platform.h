#pragma once
#include "bdk_audio_decoder.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <numeric>
#include <vector>

struct BdkAudioFile {
  FILE *file;
  uint64_t size;
  const char *name;
  uint64_t offset = 0;
};

// ID3 can prefix ADTS AAC as well as MPEG audio. Detect the actual audio header
// without reopening the file; native demuxers receive only the bounded ADTS
// view.
inline uint64_t bdk_adts_offset(BdkAudioFile file) {
  uint8_t head[10]{};
  if (std::fseek(file.file, long(file.offset), SEEK_SET) ||
      std::fread(head, 1, 10, file.file) != 10)
    return UINT64_MAX;
  uint64_t prefix = 0;
  if (!std::memcmp(head, "ID3", 3)) {
    if ((head[6] | head[7] | head[8] | head[9]) & 0x80)
      return UINT64_MAX;
    prefix = 10 + (uint64_t(head[6]) << 21) + (uint64_t(head[7]) << 14) +
             (uint64_t(head[8]) << 7) + head[9];
    if (head[3] == 4 && (head[5] & 0x10))
      prefix += 10;
    if (prefix > file.size || file.size - prefix < 2 ||
        std::fseek(file.file, long(file.offset + prefix), SEEK_SET) ||
        std::fread(head, 1, 2, file.file) != 2)
      return UINT64_MAX;
  }
  return head[0] == 255 && (head[1] & 0xf6) == 0xf0 ? prefix : UINT64_MAX;
}
int bdk_platform_probe(BdkAudioFile file, bdk_audio_info &info);
int bdk_platform_decode(BdkAudioFile file, uint32_t rate, uint64_t start,
                        uint32_t count, int16_t *output);
int bdk_resample_window(const std::vector<float> &mono, uint32_t sourceRate,
                        uint32_t outputRate, uint32_t skip, uint32_t count,
                        bool completeSourceEnd, int16_t *output);

inline uint64_t bdk_scale(uint64_t frames, uint32_t to, uint32_t from) {
  if (!from || frames / from > UINT64_MAX / to)
    return UINT64_MAX;
  return frames / from * to + (frames % from) * to / from;
}
inline int bdk_validate_info(const bdk_audio_info &info) {
  if (info.sample_rate < 1000 || info.sample_rate > 192000 || !info.channels ||
      info.channels > 32 || !info.frames)
    return BDK_AUDIO_UNSUPPORTED;
  if (static_cast<long double>(info.frames) / info.sample_rate >
      static_cast<long double>(INT64_MAX) / 1000000)
    return BDK_AUDIO_RANGE;
  return BDK_AUDIO_OK;
}

// Only the selected mono source window is retained, not whole decoded media.
// Timestamped native PCM is copied without filling holes or concealing short
// EOF.
class BdkPcmWindow {
public:
  int init(bdk_audio_info info, uint32_t outputRate, uint64_t start,
           uint32_t count) {
    auto code = bdk_validate_info(info);
    if (code)
      return code;
    info_ = info;
    rate_ = outputRate;
    count_ = count;
    auto available = bdk_scale(info.frames, outputRate, info.sample_rate);
    if (start > available || count > available - start)
      return BDK_AUDIO_RANGE;
    auto period = outputRate / std::gcd(outputRate, info.sample_rate);
    auto warm = (start > 2048 ? start - 2048 : 0) / period * period;
    begin_ = bdk_scale(warm, info.sample_rate, outputRate);
    const auto endOutput = start + count;
    auto end = bdk_scale(endOutput, info.sample_rate, outputRate);
    if (endOutput % outputRate * info.sample_rate % outputRate)
      ++end;
    end_ = std::min<uint64_t>(info.frames, end + 64);
    skip_ = uint32_t(start - warm);
    if (end_ < begin_ || end_ - begin_ > 4000000)
      return BDK_AUDIO_RANGE;
    mono_.reserve(size_t(end_ - begin_));
    return BDK_AUDIO_OK;
  }
  uint64_t firstSourceFrame() const { return begin_; }
  uint32_t sourceRate() const { return info_.sample_rate; }
  uint32_t channels() const { return info_.channels; }
  bool complete() const { return mono_.size() == end_ - begin_; }
  int add(const uint8_t *pcm, size_t frames, uint32_t channels, bool floating,
          int64_t firstFrame) {
    if (channels != info_.channels || !pcm || frames > 4000000)
      return BDK_AUDIO_DECODE_FAILED;
    if (lastEnd_ != INT64_MIN && std::llabs(firstFrame - lastEnd_) <= 1)
      firstFrame = lastEnd_;
    if (firstFrame > INT64_MAX - int64_t(frames))
      return BDK_AUDIO_RANGE;
    lastEnd_ = firstFrame + int64_t(frames);
    const int64_t wanted = int64_t(begin_ + mono_.size());
    if (lastEnd_ <= wanted)
      return BDK_AUDIO_OK;
    if (firstFrame > wanted)
      return BDK_AUDIO_DECODE_FAILED;
    auto offset = size_t(wanted - firstFrame);
    auto stride = channels * (floating ? 4 : 2);
    for (size_t frame = offset; frame < frames && !complete(); ++frame) {
      double sum = 0;
      for (uint32_t channel = 0; channel < channels; ++channel) {
        if (floating) {
          float v;
          std::memcpy(&v, pcm + frame * stride + channel * 4, 4);
          if (!std::isfinite(v))
            return BDK_AUDIO_CORRUPT;
          sum += v;
        } else {
          int16_t v;
          std::memcpy(&v, pcm + frame * stride + channel * 2, 2);
          sum += double(v) / 32768.0;
        }
      }
      mono_.push_back(float(sum / channels));
    }
    return BDK_AUDIO_OK;
  }
  int finish(int16_t *output) const {
    if (!complete())
      return BDK_AUDIO_DECODE_FAILED;
    return bdk_resample_window(mono_, info_.sample_rate, rate_, skip_, count_,
                               end_ == info_.frames, output);
  }

private:
  bdk_audio_info info_{};
  uint32_t rate_ = 0, count_ = 0, skip_ = 0;
  uint64_t begin_ = 0, end_ = 0;
  int64_t lastEnd_ = INT64_MIN;
  std::vector<float> mono_;
};
