// Offline C ABI diagnostics only. No audio device, playback, or route APIs.
#include "bdk_audio_decoder.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#ifdef __ANDROID__
#include <dlfcn.h>
#endif

int main(int argc, char **argv) {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
#ifdef __ANDROID__
  // Shell executables do not inherit an Android app's Binder pool. This is
  // harness-only setup; the production decoder never starts process globals.
  auto *binder = dlopen("libbinder_ndk.so", RTLD_NOW | RTLD_LOCAL);
  auto startPool = binder ? reinterpret_cast<void (*)()>(
                                dlsym(binder, "ABinderProcess_startThreadPool"))
                          : nullptr;
  if (!startPool) {
    std::fprintf(stderr,
                 "Native harness requires Binder thread pool support\n");
    return 69;
  }
  startPool();
#endif
  if (argc != 2 && argc != 5 && argc != 6) {
    std::fprintf(stderr,
                 "Usage: bdk_decoder_qa path [rate start count [--compare]]\n");
    return 64;
  }
  const char *path = argv[1];
  bdk_audio_info info{};
  const auto probe = bdk_audio_probe(path, int32_t(std::strlen(path)), &info);
  std::printf("probe code=%d rate=%u channels=%u frames=%llu path=%s\n", probe,
              info.sample_rate, info.channels,
              static_cast<unsigned long long>(info.frames), path);
  if (probe || argc == 2)
    return probe;
  const auto rate = uint32_t(std::strtoul(argv[2], nullptr, 10));
  const auto start = uint64_t(std::strtoull(argv[3], nullptr, 10));
  const auto count = uint32_t(std::strtoul(argv[4], nullptr, 10));
  if (!count || count > 102378)
    return 64;
  std::vector<int16_t> samples(size_t(count) + 2, 12345);
  uint32_t written = 999;
  const auto code =
      bdk_audio_decode_segment(path, int32_t(std::strlen(path)), rate, start,
                               count, samples.data() + 1, count, &written);
  uint32_t nonzero = 0, peak = 0;
  uint64_t hash = 14695981039346656037ULL;
  if (written <= count) {
    for (size_t i = 1; i <= written; ++i) {
      nonzero += samples[i] != 0;
      peak = std::max(peak, uint32_t(std::abs(int(samples[i]))));
      hash = (hash ^ uint16_t(samples[i])) * 1099511628211ULL;
    }
  }
  const bool guards = samples.front() == 12345 && samples.back() == 12345;
  std::printf("decode code=%d rate=%u start=%llu count=%u written=%u "
              "nonzero=%u peak=%u hash=%016llx guards=%d\n",
              code, rate, static_cast<unsigned long long>(start), count,
              written, nonzero, peak, static_cast<unsigned long long>(hash),
              guards);
  if (argc == 6 && !code && guards) {
    if (std::strcmp(argv[5], "--compare") || start + count > 102378)
      return 64;
    std::vector<int16_t> reference(size_t(start + count));
    uint32_t fullWritten = 0;
    auto fullCode = bdk_audio_decode_segment(
        path, int32_t(std::strlen(path)), rate, 0, uint32_t(start + count),
        reference.data(), uint32_t(reference.size()), &fullWritten);
    int maxDelta = 0;
    size_t worst = 0, different = 0;
    if (!fullCode && fullWritten == reference.size()) {
      for (size_t i = 0; i < count; ++i) {
        auto delta =
            std::abs(int(samples[i + 1]) - reference[size_t(start) + i]);
        different += delta > 2;
        if (delta > maxDelta) {
          maxDelta = delta;
          worst = i;
        }
      }
    } else {
      maxDelta = 65536;
    }
    std::printf(
        "compare code=%d written=%u maxDelta=%d different=%zu worst=%zu "
        "actual=%d reference=%d\n",
        fullCode, fullWritten, maxDelta, different, worst, samples[worst + 1],
        reference[size_t(start) + worst]);
    if (maxDelta > 2)
      return 66;
  }
  return !guards || (code == 0 && (written != count || !nonzero)) ? 65 : code;
}
