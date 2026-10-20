#pragma once
#include <stdint.h>
#if defined(_WIN32)
#define BDK_AUDIO_EXPORT __declspec(dllexport)
#else
#define BDK_AUDIO_EXPORT __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
enum bdk_audio_result {
  BDK_AUDIO_OK = 0,
  BDK_AUDIO_INVALID_ARGUMENT = 1,
  BDK_AUDIO_FILE_IO = 2,
  BDK_AUDIO_FILE_TOO_LARGE = 3,
  BDK_AUDIO_UNSUPPORTED = 4,
  BDK_AUDIO_CORRUPT = 5,
  BDK_AUDIO_RANGE = 6,
  BDK_AUDIO_BUFFER_TOO_SMALL = 7,
  BDK_AUDIO_OUT_OF_MEMORY = 8,
  BDK_AUDIO_DECODE_FAILED = 9,
  BDK_AUDIO_INVALID_UTF8 = 10
};
typedef struct bdk_audio_info {
  uint32_t sample_rate;
  uint32_t channels;
  uint64_t frames;
} bdk_audio_info;
/* path_bytes excludes the terminator; paths may not contain embedded NUL. */
BDK_AUDIO_EXPORT int32_t bdk_audio_probe(const char *path, int32_t path_bytes,
                                         bdk_audio_info *info);
/* All positions/counts/capacities are mono OUTPUT frames, not source
   frames/bytes. Success writes exactly count samples; on error written=0 and
   output is invalid. */
BDK_AUDIO_EXPORT int32_t bdk_audio_decode_segment(
    const char *path, int32_t path_bytes, uint32_t output_rate,
    uint64_t start_frame, uint32_t count, int16_t *output, uint32_t capacity,
    uint32_t *written);
#ifdef __cplusplus
}
#endif
