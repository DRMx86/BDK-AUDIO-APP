#define NOMINMAX
#include "bdk_audio_platform.h"
#include <atomic>
#include <memory>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mutex>
#include <propvarutil.h>
#include <string>
#include <windows.h>
#include <wrl/client.h>
using Microsoft::WRL::ComPtr;

namespace {
struct Runtime {
  HMODULE platformModule=LoadLibraryExW(L"mfplat.dll",nullptr,LOAD_LIBRARY_SEARCH_SYSTEM32);
  HMODULE readerModule=LoadLibraryExW(L"mfreadwrite.dll",nullptr,LOAD_LIBRARY_SEARCH_SYSTEM32);
  HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  HRESULT mf = !platformModule || !readerModule ? E_NOTIMPL :
               FAILED(com) && com != RPC_E_CHANGED_MODE ? com
                   : MFStartup(MF_VERSION, MFSTARTUP_LITE);
  ~Runtime() {
    if (SUCCEEDED(mf))
      MFShutdown();
    if (SUCCEEDED(com))
      CoUninitialize();
    if(readerModule)FreeLibrary(readerModule);
    if(platformModule)FreeLibrary(platformModule);
  }
};
struct FileState {
  BdkAudioFile file;
  std::mutex mutex;
  bool closed = false;
};
class Stream final : public IStream {
public:
  explicit Stream(std::shared_ptr<FileState> state)
      : state_(std::move(state)) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void **out) override {
    if (!out)
      return E_POINTER;
    *out = nullptr;
    if (id == IID_IUnknown || id == IID_ISequentialStream ||
        id == IID_IStream) {
      *out = static_cast<IStream *>(this);
      AddRef();
      return S_OK;
    }
    return E_NOINTERFACE;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++refs_; }
  ULONG STDMETHODCALLTYPE Release() override {
    auto n = --refs_;
    if (!n)
      delete this;
    return n;
  }
  HRESULT STDMETHODCALLTYPE Read(void *out, ULONG count, ULONG *got) override {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (got)
      *got = 0;
    if (state_->closed)
      return STG_E_REVERTED;
    if (!count)
      return S_OK;
    if (!out)
      return E_POINTER;
    auto request =
        position_ >= state_->file.size
            ? 0
            : std::min<uint64_t>(count, state_->file.size - position_);
    if (!request)
      return S_FALSE;
    if (_fseeki64(state_->file.file, int64_t(state_->file.offset + position_),
                  SEEK_SET))
      return STG_E_READFAULT;
    auto n = std::fread(out, 1, size_t(request), state_->file.file);
    position_ += n;
    if (got)
      *got = ULONG(n);
    if (std::ferror(state_->file.file))
      return STG_E_READFAULT;
    return n == count ? S_OK : S_FALSE;
  }
  HRESULT STDMETHODCALLTYPE Seek(LARGE_INTEGER delta, DWORD origin,
                                 ULARGE_INTEGER *out) override {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (state_->closed)
      return STG_E_REVERTED;
    int64_t base = origin == STREAM_SEEK_SET   ? 0
                   : origin == STREAM_SEEK_CUR ? int64_t(position_)
                   : origin == STREAM_SEEK_END ? int64_t(state_->file.size)
                                               : -1;
    if (base < 0 || delta.QuadPart < -base || delta.QuadPart > INT64_MAX - base)
      return STG_E_INVALIDFUNCTION;
    position_ = uint64_t(base + delta.QuadPart);
    if (out)
      out->QuadPart = position_;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Stat(STATSTG *out, DWORD) override {
    if (!out)
      return E_POINTER;
    *out = {};
    out->type = STGTY_STREAM;
    out->cbSize.QuadPart = state_->file.size;
    out->grfMode = STGM_READ;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Clone(IStream **out) override {
    if (!out)
      return E_POINTER;
    std::lock_guard<std::mutex> lock(state_->mutex);
    auto *clone = new (std::nothrow) Stream(state_);
    if (!clone)
      return E_OUTOFMEMORY;
    clone->position_ = position_;
    *out = clone;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Write(const void *, ULONG, ULONG *) override {
    return STG_E_ACCESSDENIED;
  }
  HRESULT STDMETHODCALLTYPE SetSize(ULARGE_INTEGER) override {
    return STG_E_ACCESSDENIED;
  }
  HRESULT STDMETHODCALLTYPE CopyTo(IStream *, ULARGE_INTEGER, ULARGE_INTEGER *,
                                   ULARGE_INTEGER *) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE Commit(DWORD) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE Revert() override { return E_NOTIMPL; }
  HRESULT STDMETHODCALLTYPE LockRegion(ULARGE_INTEGER, ULARGE_INTEGER,
                                       DWORD) override {
    return E_NOTIMPL;
  }
  HRESULT STDMETHODCALLTYPE UnlockRegion(ULARGE_INTEGER, ULARGE_INTEGER,
                                         DWORD) override {
    return E_NOTIMPL;
  }

private:
  std::atomic<ULONG> refs_{1};
  std::shared_ptr<FileState> state_;
  uint64_t position_ = 0;
};
struct Reader {
  Runtime runtime;
  std::shared_ptr<FileState> state;
  ComPtr<IMFByteStream> stream;
  ComPtr<IMFSourceReader> reader;
  uint32_t rate = 0, channels = 0;
  bool rawAdts = false;
  uint64_t primedEnd = 0;
  ~Reader() {
    reader.Reset();
    if (stream)
      stream->Close();
    stream.Reset();
    if (state) {
      std::lock_guard<std::mutex> lock(state->mutex);
      state->closed = true;
    }
  }
  int open(BdkAudioFile file) {
    if (FAILED(runtime.mf))
      return BDK_AUDIO_UNSUPPORTED;
    const auto prefix = bdk_adts_offset(file);
    rawAdts = prefix != UINT64_MAX;
    if (rawAdts) {
      file.offset += prefix;
      file.size -= prefix;
    }
    state = std::make_shared<FileState>();
    state->file = file;
    ComPtr<IStream> input;
    input.Attach(new (std::nothrow) Stream(state));
    if (!input)
      return BDK_AUDIO_OUT_OF_MEMORY;
    if (FAILED(MFCreateMFByteStreamOnStream(input.Get(), &stream)))
      return BDK_AUDIO_UNSUPPORTED;
    ComPtr<IMFAttributes> hints;
    stream.As(&hints);
    if (hints) {
      int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, file.name, -1,
                                  nullptr, 0);
      std::wstring name(size_t(n), L'\0');
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, file.name, -1,
                          name.data(), n);
      hints->SetString(MF_BYTESTREAM_ORIGIN_NAME, name.c_str());
    }
    ComPtr<IMFAttributes> attributes;
    if (FAILED(MFCreateAttributes(&attributes, 2)) || !attributes)
      return BDK_AUDIO_OUT_OF_MEMORY;
    attributes->SetUINT32(MF_SOURCE_READER_DISCONNECT_MEDIASOURCE_ON_SHUTDOWN,
                          TRUE);
    attributes->SetUINT32(MF_SOURCE_READER_DISABLE_DXVA, TRUE);
    auto result = MFCreateSourceReaderFromByteStream(stream.Get(),
                                                     attributes.Get(), &reader);
    if (FAILED(result))
      return BDK_AUDIO_UNSUPPORTED;
    if (FAILED(
            reader->SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS, FALSE)) ||
        FAILED(reader->SetStreamSelection(MF_SOURCE_READER_FIRST_AUDIO_STREAM,
                                          TRUE)))
      return BDK_AUDIO_UNSUPPORTED;
    ComPtr<IMFMediaType> type;
    if (FAILED(MFCreateMediaType(&type)) || !type)
      return BDK_AUDIO_OUT_OF_MEMORY;
    type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_Float);
    if (FAILED(reader->SetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM,
                                           nullptr, type.Get())))
      return BDK_AUDIO_UNSUPPORTED;
    // AAC's MFT advertises a provisional format before its first input.
    // Prime real PCM and query the negotiated output, never reinterpret that
    // first buffer using the provisional sample-rate/channel defaults.
    for (unsigned i = 0; i < 10000; ++i) {
      DWORD flags = 0;
      LONGLONG time = 0;
      ComPtr<IMFSample> sample;
      if (FAILED(reader->ReadSample(MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0,
                                    nullptr, &flags, &time, &sample)) ||
          (flags & MF_SOURCE_READERF_ERROR))
        return BDK_AUDIO_DECODE_FAILED;
      if (sample) {
        auto code = format();
        if (code)
          return code;
        ComPtr<IMFMediaBuffer> buffer;
        DWORD bytes = 0;
        if (FAILED(sample->ConvertToContiguousBuffer(&buffer)) ||
            FAILED(buffer->GetCurrentLength(&bytes)))
          return BDK_AUDIO_DECODE_FAILED;
        if (bytes > 4 * 1024 * 1024 || bytes % (channels * 4))
          return BDK_AUDIO_CORRUPT;
        auto end = int64_t(std::llround(static_cast<long double>(time) * rate /
                                        10000000)) +
                   bytes / (channels * 4);
        if (end > 0)
          primedEnd = uint64_t(end);
        return BDK_AUDIO_OK;
      }
      if (flags & MF_SOURCE_READERF_ENDOFSTREAM)
        return BDK_AUDIO_CORRUPT;
    }
    return BDK_AUDIO_DECODE_FAILED;
  }
  int format() {
    ComPtr<IMFMediaType> type;
    if (FAILED(reader->GetCurrentMediaType(MF_SOURCE_READER_FIRST_AUDIO_STREAM,
                                           &type)))
      return BDK_AUDIO_DECODE_FAILED;
    GUID subtype{};
    UINT32 bits = 0, alignment = 0;
    if (FAILED(type->GetGUID(MF_MT_SUBTYPE, &subtype)) ||
        subtype != MFAudioFormat_Float ||
        FAILED(type->GetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, &bits)) ||
        bits != 32 ||
        FAILED(type->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &rate)) ||
        FAILED(type->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels)) ||
        FAILED(type->GetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, &alignment)) ||
        alignment != channels * 4 || rate < 1000 || rate > 192000 ||
        !channels || channels > 32)
      return BDK_AUDIO_UNSUPPORTED;
    return BDK_AUDIO_OK;
  }
  int info(bdk_audio_info &out) {
    PROPVARIANT duration;
    PropVariantInit(&duration);
    auto result = reader->GetPresentationAttribute(MF_SOURCE_READER_MEDIASOURCE,
                                                   MF_PD_DURATION, &duration);
    uint64_t ticks = SUCCEEDED(result) && duration.vt == VT_UI8
                         ? duration.uhVal.QuadPart
                         : 0;
    PropVariantClear(&duration);
    if (ticks && !rawAdts)
      out = {rate, channels, bdk_scale(ticks, rate, 10000000)};
    else {
      // Raw ADTS may have no container duration. Count actual timestamped PCM.
      uint64_t end = primedEnd;
      for (unsigned iteration = 0; iteration < 10000000; ++iteration) {
        DWORD flags = 0;
        LONGLONG time = 0;
        ComPtr<IMFSample> sample;
        if (FAILED(reader->ReadSample(MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0,
                                      nullptr, &flags, &time, &sample)))
          return BDK_AUDIO_DECODE_FAILED;
        if (flags & MF_SOURCE_READERF_ERROR)
          return BDK_AUDIO_DECODE_FAILED;
        if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) {
          auto oldRate = rate, oldChannels = channels;
          auto code = format();
          if (code || rate != oldRate || channels != oldChannels)
            return BDK_AUDIO_DECODE_FAILED;
        }
        if (sample) {
          ComPtr<IMFMediaBuffer> buffer;
          if (FAILED(sample->ConvertToContiguousBuffer(&buffer)))
            return BDK_AUDIO_DECODE_FAILED;
          DWORD bytes = 0;
          buffer->GetCurrentLength(&bytes);
          if (bytes > 4 * 1024 * 1024 || bytes % (channels * 4))
            return BDK_AUDIO_CORRUPT;
          auto first = int64_t(
              std::llround(static_cast<long double>(time) * rate / 10000000));
          auto last = first + bytes / (channels * 4);
          if (last > 0)
            end = std::max(end, uint64_t(last));
        }
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
          out = {rate, channels, end};
          break;
        }
      }
    }
    return bdk_validate_info(out);
  }
};
} // namespace
int bdk_platform_probe(BdkAudioFile file, bdk_audio_info &info) {
  Reader r;
  auto code = r.open(file);
  if (code)
    return code;
  return r.info(info);
}
int bdk_platform_decode(BdkAudioFile file, uint32_t rate, uint64_t start,
                        uint32_t count, int16_t *out) {
  Reader r;
  auto code = r.open(file);
  if (code)
    return code;
  bdk_audio_info info{};
  code = r.info(info);
  if (code)
    return code;
  BdkPcmWindow window;
  code = window.init(info, rate, start, count);
  if (code)
    return code;
  PROPVARIANT position;
  PropVariantInit(&position);
  position.vt = VT_I8;
  auto first = window.firstSourceFrame();
  auto before = first > info.sample_rate ? first - info.sample_rate : 0;
  if (r.rawAdts)
    before = 0; // ADTS sources expose estimated seeking; decode real PTS from
                // origin.
  auto positionTicks = bdk_scale(before, 10000000, info.sample_rate);
  if (positionTicks > INT64_MAX)
    return BDK_AUDIO_RANGE;
  position.hVal.QuadPart = LONGLONG(positionTicks);
  if (FAILED(r.reader->SetCurrentPosition(GUID_NULL, position)))
    return BDK_AUDIO_DECODE_FAILED;
  for (unsigned iteration = 0; iteration < 10000000 && !window.complete();
       ++iteration) {
    DWORD flags = 0;
    LONGLONG time = 0;
    ComPtr<IMFSample> sample;
    if (FAILED(r.reader->ReadSample(MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0,
                                    nullptr, &flags, &time, &sample)) ||
        (flags & MF_SOURCE_READERF_ERROR))
      return BDK_AUDIO_DECODE_FAILED;
    if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) {
      code = r.format();
      if (code || r.rate != info.sample_rate || r.channels != info.channels)
        return BDK_AUDIO_DECODE_FAILED;
    }
    if (sample) {
      ComPtr<IMFMediaBuffer> buffer;
      if (FAILED(sample->ConvertToContiguousBuffer(&buffer)))
        return BDK_AUDIO_DECODE_FAILED;
      BYTE *pcm = nullptr;
      DWORD length = 0;
      if (FAILED(buffer->Lock(&pcm, nullptr, &length)))
        return BDK_AUDIO_DECODE_FAILED;
      if (length > 4 * 1024 * 1024 || length % (info.channels * 4)) {
        buffer->Unlock();
        return BDK_AUDIO_CORRUPT;
      }
      auto stamp = int64_t(std::llround(static_cast<long double>(time) *
                                        info.sample_rate / 10000000));
      code = window.add(pcm, length / (info.channels * 4), info.channels, true,
                        stamp);
      buffer->Unlock();
      if (code)
        return code;
    }
    if (flags & MF_SOURCE_READERF_ENDOFSTREAM)
      break;
  }
  return window.finish(out);
}
