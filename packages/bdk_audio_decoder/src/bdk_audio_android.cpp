#include "bdk_audio_platform.h"
#include <chrono>
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaExtractor.h>
#include <media/NdkMediaFormat.h>
#include <string>
#include <unistd.h>

namespace {
#ifdef BDK_DECODER_DIAGNOSTICS
#define BDK_TRACE(...) std::fprintf(stderr, __VA_ARGS__)
#else
#define BDK_TRACE(...) ((void)0)
#endif
struct Packet {
  std::vector<uint8_t> bytes;
  int64_t time = 0;
  bool floating = false;
};
struct Reader {
  AMediaExtractor *extractor = nullptr;
  AMediaCodec *codec = nullptr;
  AMediaFormat *track = nullptr;
  bool started = false, inputEos = false, outputEos = false, rawAdts = false,
       seenPcm = false;
  uint32_t rate = 0, channels = 0;
  int encoding = 2;
  int64_t durationUs = 0;
  Packet primed;
  std::chrono::steady_clock::time_point deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(30);
  ~Reader() { close(); }
  void close() {
    BDK_TRACE("reader cleanup started=%d\n", started);
    if (codec) {
      if (started)
        AMediaCodec_stop(codec);
      AMediaCodec_delete(codec);
    }
    if (track)
      AMediaFormat_delete(track);
    if (extractor)
      AMediaExtractor_delete(extractor);
    codec = nullptr;
    track = nullptr;
    extractor = nullptr;
    started = false;
  }
  int open(BdkAudioFile file) {
    BDK_TRACE("open bytes=%llu\n", (unsigned long long)file.size);
    extractor = AMediaExtractor_new();
    if (!extractor)
      return BDK_AUDIO_OUT_OF_MEMORY;
    auto prefix = bdk_adts_offset(file);
    rawAdts = prefix != UINT64_MAX;
    if (rawAdts) {
      file.offset += prefix;
      file.size -= prefix;
    }
    if (AMediaExtractor_setDataSourceFd(extractor, fileno(file.file),
                                        off64_t(file.offset),
                                        off64_t(file.size)) != AMEDIA_OK)
      return BDK_AUDIO_UNSUPPORTED;
    std::string mime;
    bool selected = false;
    for (size_t i = 0; i < AMediaExtractor_getTrackCount(extractor); ++i) {
      auto *candidate = AMediaExtractor_getTrackFormat(extractor, i);
      const char *type = nullptr;
      if (candidate &&
          AMediaFormat_getString(candidate, AMEDIAFORMAT_KEY_MIME, &type) &&
          type && !std::strncmp(type, "audio/", 6)) {
        track = candidate;
        mime = type;
        if (AMediaExtractor_selectTrack(extractor, i) != AMEDIA_OK)
          return BDK_AUDIO_DECODE_FAILED;
        selected = true;
        break;
      }
      if (candidate)
        AMediaFormat_delete(candidate);
    }
    if (!selected)
      return BDK_AUDIO_UNSUPPORTED;
    BDK_TRACE("track %s\n", AMediaFormat_toString(track));
    int32_t sampleRate = 0, channelCount = 0;
    if (!AMediaFormat_getInt32(track, AMEDIAFORMAT_KEY_SAMPLE_RATE,
                               &sampleRate) ||
        !AMediaFormat_getInt32(track, AMEDIAFORMAT_KEY_CHANNEL_COUNT,
                               &channelCount) ||
        sampleRate < 1000 || sampleRate > 192000 || channelCount < 1 ||
        channelCount > 32)
      return BDK_AUDIO_UNSUPPORTED;
    rate = uint32_t(sampleRate);
    channels = uint32_t(channelCount);
    AMediaFormat_getInt64(track, AMEDIAFORMAT_KEY_DURATION, &durationUs);
    codec = AMediaCodec_createDecoderByType(mime.c_str());
    if (!codec)
      return BDK_AUDIO_UNSUPPORTED;
    AMediaFormat_setInt32(track, "pcm-encoding",
                          2); // Normal decoded signed PCM16 request.
    BDK_TRACE("codec configure/start\n");
    if (AMediaCodec_configure(codec, track, nullptr, nullptr, 0) != AMEDIA_OK ||
        AMediaCodec_start(codec) != AMEDIA_OK)
      return BDK_AUDIO_UNSUPPORTED;
    started = true;
    BDK_TRACE("codec priming\n");
    auto code = next(primed);
    if (code)
      return code;
    if (primed.bytes.empty())
      return BDK_AUDIO_CORRUPT;
    return BDK_AUDIO_OK;
  }
  int outputFormat() {
    auto *value = AMediaCodec_getOutputFormat(codec);
    if (!value)
      return BDK_AUDIO_DECODE_FAILED;
    BDK_TRACE("output format %s\n", AMediaFormat_toString(value));
    int32_t r = 0, c = 0, e = 2;
    bool valid =
        AMediaFormat_getInt32(value, AMEDIAFORMAT_KEY_SAMPLE_RATE, &r) &&
        AMediaFormat_getInt32(value, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &c);
    AMediaFormat_getInt32(value, "pcm-encoding", &e);
    AMediaFormat_delete(value);
    if (!valid || r < 1000 || r > 192000 || c < 1 || c > 32 ||
        (e != 2 && e != 4))
      return BDK_AUDIO_UNSUPPORTED;
    if (seenPcm && (uint32_t(r) != rate || uint32_t(c) != channels))
      return BDK_AUDIO_DECODE_FAILED;
    rate = uint32_t(r);
    channels = uint32_t(c);
    encoding = e;
    return BDK_AUDIO_OK;
  }
  int next(Packet &packet) {
    packet.bytes.clear();
    while (!outputEos && std::chrono::steady_clock::now() < deadline) {
      if (!inputEos) {
        auto index = AMediaCodec_dequeueInputBuffer(codec, 0);
        if (index >= 0) {
          size_t capacity = 0;
          auto *input =
              AMediaCodec_getInputBuffer(codec, size_t(index), &capacity);
          if (!input || !capacity)
            return BDK_AUDIO_DECODE_FAILED;
          auto bytes =
              AMediaExtractor_readSampleData(extractor, input, capacity);
          auto time = AMediaExtractor_getSampleTime(extractor);
          BDK_TRACE("input bytes=%zd pts=%lld\n", bytes, (long long)time);
          if (bytes < 0) {
            if (time != -1)
              return BDK_AUDIO_DECODE_FAILED;
            inputEos = true;
            if (AMediaCodec_queueInputBuffer(
                    codec, size_t(index), 0, 0, 0,
                    AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) != AMEDIA_OK)
              return BDK_AUDIO_DECODE_FAILED;
          } else {
            // At EOF some extractors return all bits set for sample flags.
            // Interpret flags only after readSampleData confirms a sample.
            const auto flags = AMediaExtractor_getSampleFlags(extractor);
            if (flags & AMEDIAEXTRACTOR_SAMPLE_FLAG_ENCRYPTED)
              return BDK_AUDIO_UNSUPPORTED;
            if (size_t(bytes) > capacity || time == -1)
              return BDK_AUDIO_DECODE_FAILED;
            if (AMediaCodec_queueInputBuffer(codec, size_t(index), 0,
                                             size_t(bytes), uint64_t(time),
                                             0) != AMEDIA_OK)
              return BDK_AUDIO_DECODE_FAILED;
            AMediaExtractor_advance(extractor);
          }
        }
      }
      AMediaCodecBufferInfo info{};
      auto index = AMediaCodec_dequeueOutputBuffer(codec, &info, 10000);
      if (index == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED) {
        auto code = outputFormat();
        if (code)
          return code;
        continue;
      }
      if (index < 0)
        continue;
      size_t capacity = 0;
      auto *pcm = AMediaCodec_getOutputBuffer(codec, size_t(index), &capacity);
      BDK_TRACE("output bytes=%d offset=%d capacity=%zu pts=%lld flags=%u\n",
                info.size, info.offset, capacity,
                (long long)info.presentationTimeUs, info.flags);
      const bool eos =
          (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) != 0;
      int code = BDK_AUDIO_OK;
      if (info.offset < 0 || info.size < 0 ||
          uint64_t(info.offset) + uint64_t(info.size) > capacity ||
          info.size > 4 * 1024 * 1024)
        code = BDK_AUDIO_CORRUPT;
      else if (info.size &&
               !(info.flags & AMEDIACODEC_BUFFER_FLAG_CODEC_CONFIG)) {
        if (!pcm || size_t(info.size) % (channels * (encoding == 4 ? 4 : 2)))
          code = BDK_AUDIO_CORRUPT;
        else {
          packet.bytes.assign(pcm + info.offset, pcm + info.offset + info.size);
          packet.time = info.presentationTimeUs;
          packet.floating = encoding == 4;
          seenPcm = true;
        }
      }
      AMediaCodec_releaseOutputBuffer(codec, size_t(index), false);
      outputEos = eos;
      if (code)
        return code;
      if (!packet.bytes.empty())
        return BDK_AUDIO_OK;
    }
    return outputEos ? BDK_AUDIO_OK : BDK_AUDIO_DECODE_FAILED;
  }
  int info(bdk_audio_info &out) {
    BDK_TRACE("metadata duration=%lld rawAdts=%d\n", (long long)durationUs,
              rawAdts);
    if (durationUs > 0 && !rawAdts)
      out = {rate, channels, bdk_scale(uint64_t(durationUs), rate, 1000000)};
    else {
      auto endOf = [&](const Packet &p) -> uint64_t {
        auto first = int64_t(
            std::llround(static_cast<long double>(p.time) * rate / 1000000));
        auto end =
            first + int64_t(p.bytes.size() / (channels * (p.floating ? 4 : 2)));
        return end > 0 ? uint64_t(end) : 0;
      };
      uint64_t end = endOf(primed);
      Packet p;
      while (!outputEos) {
        auto code = next(p);
        if (code)
          return code;
        if (!p.bytes.empty())
          end = std::max(end, endOf(p));
      }
      out = {rate, channels, end};
    }
    return bdk_validate_info(out);
  }
  int prepareSegment(BdkAudioFile file) {
    // Keep the complete native decoder history from origin. Seeking to zero
    // drops negative AAC pre-roll; flush also reapplies encoder-delay and
    // resets decoder history, changing later selected PCM. The window
    // discards earlier frames without retaining them. The 30-second deadline
    // still bounds the whole call, including a metadata scan when necessary.
    if (!rawAdts && durationUs > 0)
      return BDK_AUDIO_OK;
    close();
    inputEos = outputEos = rawAdts = seenPcm = false;
    rate = channels = 0;
    encoding = 2;
    durationUs = 0;
    primed.bytes.clear();
    // Recreate demuxer/codec against the same already-open file descriptor,
    // never reopen the pathname or reset the deadline.
    return open(file);
  }
};
} // namespace
int bdk_platform_probe(BdkAudioFile file, bdk_audio_info &info) {
  Reader reader;
  auto code = reader.open(file);
  if (code)
    return code;
  return reader.info(info);
}
int bdk_platform_decode(BdkAudioFile file, uint32_t rate, uint64_t start,
                        uint32_t count, int16_t *output) {
  Reader reader;
  auto code = reader.open(file);
  if (code)
    return code;
  bdk_audio_info info{};
  code = reader.info(info);
  if (code)
    return code;
  BdkPcmWindow window;
  code = window.init(info, rate, start, count);
  if (code)
    return code;
  code = reader.prepareSegment(file);
  if (code)
    return code;
  auto add = [&](const Packet &packet) {
    if (reader.rate != info.sample_rate || reader.channels != info.channels)
      return int(BDK_AUDIO_DECODE_FAILED);
    auto frame = int64_t(std::llround(static_cast<long double>(packet.time) *
                                      info.sample_rate / 1000000));
    auto result = window.add(packet.bytes.data(),
                             packet.bytes.size() /
                                 (info.channels * (packet.floating ? 4 : 2)),
                             info.channels, packet.floating, frame);
    BDK_TRACE("window add first=%lld frames=%zu code=%d complete=%d\n",
              (long long)frame,
              packet.bytes.size() / (info.channels * (packet.floating ? 4 : 2)),
              result, window.complete());
    return result;
  };
  if (!reader.primed.bytes.empty()) {
    code = add(reader.primed);
    if (code)
      return code;
    reader.primed.bytes.clear();
  }
  while (!reader.outputEos && !window.complete()) {
    Packet packet;
    code = reader.next(packet);
    if (code)
      return code;
    if (!packet.bytes.empty()) {
      code = add(packet);
      if (code)
        return code;
    }
  }
  return window.finish(output);
}
