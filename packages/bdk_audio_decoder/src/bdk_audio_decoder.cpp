#define MA_NO_DEVICE_IO
#define MA_NO_ENGINE
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_THREADING
#define MA_NO_CUSTOM
#define MA_NO_VORBIS
#define MINIAUDIO_IMPLEMENTATION
#include "bdk_audio_decoder.h"
#include "bdk_audio_platform.h"
#include "vendor/miniaudio/miniaudio.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <new>
#include <numeric>
#include <string>
#include <sys/stat.h>
#ifdef _WIN32
#include <io.h>
#include <windows.h>
#else
#include <unistd.h>
#endif

namespace {
constexpr uint64_t MaxFile = 64ULL * 1024 * 1024;
constexpr uint32_t MaxSamples = 102378;
constexpr int MaxPathBytes = 16384;
static_assert(MA_VERSION_MAJOR == 0 && MA_VERSION_MINOR == 11 &&
                  MA_VERSION_REVISION == 25,
              "Pinned miniaudio ABI changed");
bool validUtf8(const char *p, size_t n) {
  for (size_t i = 0; i < n;) {
    uint32_t first = uint8_t(p[i++]);
    if (!first)
      return false;
    if (first < 128)
      continue;
    unsigned more = first >= 0xc2 && first <= 0xdf   ? 1
                    : first >= 0xe0 && first <= 0xef ? 2
                    : first >= 0xf0 && first <= 0xf4 ? 3
                                                     : 99;
    if (more == 99 || i + more > n)
      return false;
    uint32_t value = first & ((1u << (6 - more)) - 1);
    for (unsigned j = 0; j < more; j++) {
      uint8_t v = uint8_t(p[i++]);
      if ((v & 0xc0) != 0x80)
        return false;
      value = (value << 6) | (v & 63);
    }
    if ((more == 1 && value < 0x80) || (more == 2 && value < 0x800) ||
        (more == 3 && value < 0x10000) || value > 0x10ffff ||
        (value >= 0xd800 && value <= 0xdfff))
      return false;
  }
  return true;
}
uint32_t little32(const uint8_t *p) {
  return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) |
         (uint32_t(p[3]) << 24);
}

// A per-call bounded VFS: one open file, no path reopen/TOCTOU, no reads beyond
// the size checked at open. Windows uses the wide decoder/VFS entry point.
struct Input {
  ma_vfs_callbacks callbacks{}; // miniaudio requires this as the first member.
  FILE *file = nullptr;
  uint64_t size = 0, cursor = 0;
  std::string path;
#ifdef _WIN32
  std::wstring wide;
#endif
  ma_encoding_format encoding = ma_encoding_format_unknown;
  ~Input() {
    if (file)
      std::fclose(file);
  }
  int seek(uint64_t where) {
#ifdef _WIN32
    return _fseeki64(file, static_cast<int64_t>(where), SEEK_SET);
#else
    return fseeko(file, static_cast<off_t>(where), SEEK_SET);
#endif
  }
  bool bytesAt(uint64_t offset, void *out, size_t count) {
    return offset <= size && count <= size - offset && seek(offset) == 0 &&
           std::fread(out, 1, count, file) == count;
  }
  int open(const char *raw, int bytes) {
    if (!raw || bytes <= 0 || bytes > MaxPathBytes)
      return BDK_AUDIO_INVALID_ARGUMENT;
    if (std::memchr(raw, 0, bytes))
      return BDK_AUDIO_INVALID_ARGUMENT;
    if (!validUtf8(raw, bytes))
      return BDK_AUDIO_INVALID_UTF8;
    path.assign(raw, bytes);
#ifdef _WIN32
    const auto count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, raw,
                                           bytes, nullptr, 0);
    if (count <= 0)
      return BDK_AUDIO_INVALID_UTF8;
    wide.resize(count);
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, raw, bytes, wide.data(),
                        count);
    if (_wfopen_s(&file, wide.c_str(), L"rb") || !file)
      return BDK_AUDIO_FILE_IO;
    struct _stat64 st{};
    if (_fstat64(_fileno(file), &st) || !(st.st_mode & _S_IFREG))
      return BDK_AUDIO_FILE_IO;
#else
    file = std::fopen(path.c_str(), "rb");
    if (!file)
      return BDK_AUDIO_FILE_IO;
    struct stat st{};
    if (fstat(fileno(file), &st) || !S_ISREG(st.st_mode))
      return BDK_AUDIO_FILE_IO;
#endif
    if (st.st_size < 0)
      return BDK_AUDIO_FILE_IO;
    size = uint64_t(st.st_size);
    if (size > MaxFile)
      return BDK_AUDIO_FILE_TOO_LARGE;
    uint8_t head[12]{};
    if (!bytesAt(0, head, sizeof head))
      return BDK_AUDIO_CORRUPT;
    if (!std::memcmp(head, "RIFF", 4) && !std::memcmp(head + 8, "WAVE", 4)) {
      encoding = ma_encoding_format_wav;
      const uint64_t end = uint64_t(little32(head + 4)) + 8;
      if (end > size || end < 44)
        return BDK_AUDIO_CORRUPT;
      bool fmt = false, data = false;
      for (uint64_t pos = 12; pos < end;) {
        uint8_t chunk[8];
        if (!bytesAt(pos, chunk, 8))
          return BDK_AUDIO_CORRUPT;
        uint64_t length = little32(chunk + 4);
        pos += 8;
        if (length > end - pos)
          return BDK_AUDIO_CORRUPT;
        if (!std::memcmp(chunk, "fmt ", 4)) {
          if (length < 16)
            return BDK_AUDIO_CORRUPT;
          fmt = true;
        }
        if (!std::memcmp(chunk, "data", 4)) {
          if (!length)
            return BDK_AUDIO_CORRUPT;
          data = true;
        }
        pos += length + (length & 1);
        if (pos > end)
          return BDK_AUDIO_CORRUPT;
      }
      if (!fmt || !data)
        return BDK_AUDIO_CORRUPT;
    } else if (!std::memcmp(head, "fLaC", 4))
      encoding = ma_encoding_format_flac;
    else if ((!std::memcmp(head, "ID3", 3) &&
              bdk_adts_offset({file, size, path.c_str()}) == UINT64_MAX) ||
             (head[0] == 255 && (head[1] & 0xe0) == 0xe0 &&
              (head[1] & 0x06) != 0))
      encoding = ma_encoding_format_mp3;
    // Only bounded media containers go to native demuxers, never URL playlists.
    if (encoding == ma_encoding_format_unknown &&
        std::memcmp(head + 4, "ftyp", 4) && std::memcmp(head, "OggS", 4) &&
        bdk_adts_offset({file, size, path.c_str()}) == UINT64_MAX)
      return BDK_AUDIO_UNSUPPORTED;
    seek(0);
    cursor = 0;
    callbacks.onOpen = [](ma_vfs *v, const char *, ma_uint32 mode,
                          ma_vfs_file *out) {
      if (mode != MA_OPEN_MODE_READ)
        return MA_ACCESS_DENIED;
      *out = static_cast<Input *>(v)->file;
      return MA_SUCCESS;
    };
    callbacks.onOpenW = [](ma_vfs *v, const wchar_t *, ma_uint32 mode,
                           ma_vfs_file *out) {
      if (mode != MA_OPEN_MODE_READ)
        return MA_ACCESS_DENIED;
      *out = static_cast<Input *>(v)->file;
      return MA_SUCCESS;
    };
    callbacks.onClose = [](ma_vfs *, ma_vfs_file) { return MA_SUCCESS; };
    callbacks.onRead = [](ma_vfs *v, ma_vfs_file, void *out, size_t count,
                          size_t *got) {
      auto &f = *static_cast<Input *>(v);
      count = std::min<size_t>(count, size_t(f.size - f.cursor));
      *got = std::fread(out, 1, count, f.file);
      f.cursor += *got;
      return std::ferror(f.file) ? MA_IO_ERROR : *got ? MA_SUCCESS : MA_AT_END;
    };
    callbacks.onSeek = [](ma_vfs *v, ma_vfs_file, ma_int64 delta,
                          ma_seek_origin origin) {
      auto &f = *static_cast<Input *>(v);
      int64_t base = origin == ma_seek_origin_start     ? 0
                     : origin == ma_seek_origin_current ? int64_t(f.cursor)
                                                        : int64_t(f.size);
      if (delta < -base || delta > int64_t(f.size) - base)
        return MA_BAD_SEEK;
      auto next = uint64_t(base + delta);
      if (f.seek(next))
        return MA_IO_ERROR;
      f.cursor = next;
      return MA_SUCCESS;
    };
    callbacks.onTell = [](ma_vfs *v, ma_vfs_file, ma_int64 *out) {
      *out = ma_int64(static_cast<Input *>(v)->cursor);
      return MA_SUCCESS;
    };
    callbacks.onInfo = [](ma_vfs *v, ma_vfs_file, ma_file_info *out) {
      out->sizeInBytes = static_cast<Input *>(v)->size;
      return MA_SUCCESS;
    };
    return BDK_AUDIO_OK;
  }
};
struct Decoder {
  ma_decoder value{};
  bool initialized = false;
  ~Decoder() {
    if (initialized)
      ma_decoder_uninit(&value);
  }
  int init(Input &input, uint32_t rate) {
    auto config = ma_decoder_config_init(ma_format_f32, rate ? 1 : 0, rate);
    config.encodingFormat = input.encoding;
    config.channelMixMode = ma_channel_mix_mode_simple;
#ifdef _WIN32
    auto result =
        ma_decoder_init_vfs_w(&input, input.wide.c_str(), &config, &value);
#else
    auto result =
        ma_decoder_init_vfs(&input, input.path.c_str(), &config, &value);
#endif
    initialized = result == MA_SUCCESS;
    return initialized                  ? BDK_AUDIO_OK
           : result == MA_OUT_OF_MEMORY ? BDK_AUDIO_OUT_OF_MEMORY
                                        : BDK_AUDIO_CORRUPT;
  }
  int info(bdk_audio_info &out) {
    ma_uint32 channels = 0, rate = 0;
    ma_uint64 frames = 0;
    if (ma_data_source_get_data_format(value.pBackend, nullptr, &channels,
                                       &rate, nullptr, 0) != MA_SUCCESS ||
        ma_data_source_get_length_in_pcm_frames(value.pBackend, &frames) !=
            MA_SUCCESS ||
        !frames || !channels || channels > 32 || rate < 1000 || rate > 768000)
      return BDK_AUDIO_CORRUPT;
    const long double seconds = static_cast<long double>(frames) / rate;
    if (!std::isfinite(seconds) || seconds <= 0 ||
        seconds > static_cast<long double>(INT64_MAX) / 1000000)
      return BDK_AUDIO_RANGE;
    out = {rate, channels, frames};
    return BDK_AUDIO_OK;
  }
};
int decode(const char *path, int bytes, uint32_t rate, uint64_t start,
           uint32_t count, int16_t *output, uint32_t capacity) {
  if (!output || !count || count > MaxSamples || capacity > MaxSamples)
    return BDK_AUDIO_INVALID_ARGUMENT;
  if (capacity < count)
    return BDK_AUDIO_BUFFER_TOO_SMALL;
  if (rate != 22050 && rate != 16000 && rate != 11025 && rate != 8000)
    return BDK_AUDIO_INVALID_ARGUMENT;
  Input input;
  auto code = input.open(path, bytes);
  if (code)
    return code;
  if (input.encoding == ma_encoding_format_unknown) {
    return bdk_platform_decode({input.file, input.size, input.path.c_str()},
                               rate, start, count, output);
  }
  Decoder decoder;
  code = decoder.init(input, rate);
  if (code)
    return code;
  bdk_audio_info info{};
  code = decoder.info(info);
  if (code)
    return code;
  const uint64_t seconds = info.frames / info.sample_rate;
  if (seconds > UINT64_MAX / rate)
    return BDK_AUDIO_RANGE;
  const uint64_t available = seconds * rate + (info.frames % info.sample_rate) *
                                                  rate / info.sample_rate;
  if (start > available || count > available - start)
    return BDK_AUDIO_RANGE;
  // Align resampler phase to an exact input/output ratio boundary, and warm
  // its low-pass history. Work is <=2048+one ratio period output frames.
  const uint64_t period = rate / std::gcd(rate, info.sample_rate);
  const uint64_t warm = (start > 2048 ? start - 2048 : 0) / period * period;
  if (ma_decoder_seek_to_pcm_frame(&decoder.value, warm) != MA_SUCCESS)
    return BDK_AUDIO_DECODE_FAILED;
  float scratch[1024];
  uint64_t skipped = warm;
  while (skipped < start) {
    auto request = std::min<uint64_t>(1024, start - skipped);
    ma_uint64 read = 0;
    ma_decoder_read_pcm_frames(&decoder.value, scratch, request, &read);
    if (read != request)
      return BDK_AUDIO_DECODE_FAILED;
    skipped += read;
  }
  uint32_t done = 0;
  while (done < count) {
    auto request = std::min<uint32_t>(1024, count - done);
    ma_uint64 read = 0;
    auto result =
        ma_decoder_read_pcm_frames(&decoder.value, scratch, request, &read);
    if ((result != MA_SUCCESS && result != MA_AT_END) || read != request)
      return BDK_AUDIO_DECODE_FAILED;
    for (uint32_t i = 0; i < request; i++)
      if (!std::isfinite(scratch[i]))
        return BDK_AUDIO_CORRUPT;
    for (uint32_t i = 0; i < request; i++) {
      const double value = std::clamp(double(scratch[i]), -1.0, 1.0);
      output[done + i] = int16_t(
          std::clamp<long>(std::lround(value * 32768.0), -32768, 32767));
    }
    done += request;
  }
  return BDK_AUDIO_OK;
}
} // namespace
int32_t bdk_audio_probe(const char *path, int32_t bytes, bdk_audio_info *out) {
  if (!out)
    return BDK_AUDIO_INVALID_ARGUMENT;
  *out = {};
  try {
    Input input;
    auto code = input.open(path, bytes);
    if (code)
      return code;
    if (input.encoding == ma_encoding_format_unknown) {
      return bdk_platform_probe({input.file, input.size, input.path.c_str()},
                                *out);
    }
    Decoder decoder;
    code = decoder.init(input, 0);
    if (code)
      return code;
    return decoder.info(*out);
  } catch (const std::bad_alloc &) {
    return BDK_AUDIO_OUT_OF_MEMORY;
  } catch (...) {
    return BDK_AUDIO_DECODE_FAILED;
  }
}

int bdk_resample_window(const std::vector<float> &mono, uint32_t sourceRate,
                        uint32_t outputRate, uint32_t skip, uint32_t count,
                        bool completeEnd, int16_t *output) {
  auto config = ma_data_converter_config_init(ma_format_f32, ma_format_f32, 1,
                                              1, sourceRate, outputRate);
  ma_data_converter converter{};
  if (ma_data_converter_init(&config, nullptr, &converter) != MA_SUCCESS)
    return BDK_AUDIO_DECODE_FAILED;
  struct Cleanup {
    ma_data_converter *value;
    ~Cleanup() { ma_data_converter_uninit(value, nullptr); }
  } cleanup{&converter};
  std::vector<float> input = mono;
  // Filter boundary extension is allowed only after every declared source frame
  // in this window was actually decoded. Missing source data never gets padded.
  if (completeEnd)
    input.resize(input.size() + 64, 0);
  std::vector<float> result(size_t(skip) + count);
  ma_uint64 in = input.size(), out = result.size();
  auto status = ma_data_converter_process_pcm_frames(&converter, input.data(),
                                                     &in, result.data(), &out);
  if (status != MA_SUCCESS || out != result.size())
    return BDK_AUDIO_DECODE_FAILED;
  for (uint32_t i = 0; i < count; ++i) {
    auto value = result[skip + i];
    if (!std::isfinite(value))
      return BDK_AUDIO_CORRUPT;
    output[i] = int16_t(std::clamp<long>(
        std::lround(std::clamp(double(value), -1.0, 1.0) * 32768.0), -32768,
        32767));
  }
  return BDK_AUDIO_OK;
}
int32_t bdk_audio_decode_segment(const char *path, int32_t bytes, uint32_t rate,
                                 uint64_t start, uint32_t count, int16_t *out,
                                 uint32_t capacity, uint32_t *written) {
  if (!written)
    return BDK_AUDIO_INVALID_ARGUMENT;
  *written = 0;
  try {
    auto code = decode(path, bytes, rate, start, count, out, capacity);
    if (!code)
      *written = count;
    return code;
  } catch (const std::bad_alloc &) {
    return BDK_AUDIO_OUT_OF_MEMORY;
  } catch (...) {
    return BDK_AUDIO_DECODE_FAILED;
  }
}
