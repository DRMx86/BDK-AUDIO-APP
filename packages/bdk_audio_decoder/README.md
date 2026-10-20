# BDK offline audio decoder

Portable, stateless **audio → mono PCM16** import decoding. WAV, MP3 and FLAC use the
unchanged official miniaudio **0.11.25** header pinned to commit
`9634bedb5b5a2ca38c1ee7108a9358a4e233f14d`. This package has no playback,
capture, audio-route, Bluetooth or global engine API. Native fallbacks perform offline decoding only.
Runtime dependency: `ffi` only. Source hashes and licenses accompany the package.

## Dart API

```dart
import 'package:bdk_audio_decoder/bdk_audio_decoder.dart';

final decoder = NativeAudioDecoder();
final AudioProbe source = await decoder.probeAsync(localPath);
// source.sampleRate, source.channels, source.frames, source.duration
final Int16List mono = await decoder.decodeSegmentAsync(
  localPath,
  outputRate: 16000,
  startFrame: 0,
  frameCount: 16000,
);
```

`probe` and `decodeSegment` are the equivalent synchronous calls. Use the async
methods from UI code: they open the bundled library independently in an isolate.
No object disposal is needed; each C call opens/uninitializes its own decoder
and closes its file via RAII. An isolate operation does not support cancellation;
the app can reject late results using its own operation generation.

`NativeAudioDecoder({DynamicLibrary? library, String? libraryPath})` permits one
explicit test library. Async methods require a bundled library or `libraryPath`;
they intentionally reject a supplied DynamicLibrary object, which cannot be
transferred to an isolate.

**All segment coordinates count mono OUTPUT frames**, after resampling, rather
than source frames, bytes or milliseconds. Rates are exactly 22050, 16000, 11025,
8000 Hz. Count is 1..102378 samples, permitting a maximum 200 KiB canonical WAV after
the app adds a 44 byte header. A segment must fit the source's converted frame
count, calculated as `floor(source.frames * outputRate / source.sampleRate)`.
Success returns exactly the requested count; errors never pad silence or expose
a partial output. Encoding the canonical WAV, clipping decisions and file
selection remain the app's responsibility.

Files must be nonempty regular local files at most 64 MiB. Paths are strict UTF-8,
at most 16384 bytes, without NUL. Source channels 1..32 and rates1000..768000 Hz
are validated; duration must fit a signed 64 bit microsecond Duration. A bounded
per-call VFS limits every seek/read to the size checked on the same file handle,
even if another process grows the file. Windows uses UTF-8→UTF-16 conversion,
wide `_wfopen_s`, and `ma_decoder_init_vfs_w`, supporting Unicode paths without
an ANSI code-page fallback.

RIFF/WAVE chunk bounds are checked before decoding, including odd unknown
chunks. Float/extensible WAV decode through the pinned backend; nonfinite
decoded samples fail. RIFX/RF64 are not exposed. Native fallback capabilities are listed below. MP3 padding
or encoder delay follows miniaudio's reported frame count. MP3 frame-count
probing may scan/decode the whole bounded file; it belongs off the UI isolate.
Probe checks metadata and container bounds, not an exhaustive payload checksum.
Decoding rejects short reads; a truncated or damaged compressed tail outside
the selected segment is not guaranteed to be detected.

Downmix uses miniaudio's simple channel mixing, followed by its linear resampler
and low-pass filtering. Seeking aligns to the input/output ratio period and
warms 2048 output frames of filter history, avoiding a cold transient and phase
drift. Resampled segment output matches the tested full-conversion slices within
two PCM16 units; same-rate PCM16 fixture samples remain exact. Float output is
finite-checked, saturated and rounded to PCM16 with no random dither.

## C ABI

See `src/bdk_audio_decoder.h`. `bdk_audio_probe` fills a 16 byte struct containing
source sample rate, channels and 64 bit PCM frame count. `bdk_audio_decode_segment`
uses caller-owned PCM16 output with an explicit sample capacity. `path_bytes`
excludes a terminating NUL; the C API makes its own bounded path string.
All exports return typed integer results (also AudioDecoderException.code):

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Invalid argument |
| 2 | File I/O |
| 3 | File exceeds 64 MiB |
| 4 | Unsupported format |
| 5 | Corrupt/empty/invalid audio |
| 6 | Segment/duration range |
| 7 | Insufficient output capacity |
| 8 | Allocation failure |
| 9 | Decode/seek failure or short output |
| 10 | Invalid UTF-8 path |

On error, `written=0`; the caller must discard the output buffer. Native catches
C++ allocation and other exceptions before the C boundary. There is no mutable
global decoder state; independent calls/isolates have independent files/buffers.

## Build and validation

From repository root, with CMake/MSVC, Python and a local ffmpeg:

```powershell
cmake -S packages/bdk_audio_decoder/src -B packages/bdk_audio_decoder/build/native -DBDK_DECODER_BUILD_TESTS=ON
cmake --build packages/bdk_audio_decoder/build/native --config Release
ctest --test-dir packages/bdk_audio_decoder/build/native -C Release --output-on-failure
python packages/bdk_audio_decoder/native_test/test_decoder.py
Set-Location packages/bdk_audio_decoder
flutter pub get
flutter test --no-pub
flutter analyze --no-pub
```

The native suite generates real WAV/MP3/FLAC fixtures under `build/fixtures` and
does not play them. Windows x64 DLL build, sixteen C ABI tests, one PCM window test and five real Dart
FFI/isolate tests passed. The pinned header emits one existing MSVC C4244 warning
at line 80532; it is retained unchanged. Android arm64-v8a and armeabi-v7a builds compiled against NDK 28.2.13676358,
Clang 19 and android-24. Offline Android arm64 runtime decoding passed on the
authorized Redmagic NX809J running Android 16; see the scoped diagnostic
procedure and measured regression in `native_test/ANDROID_RUNTIME.md`. Apple
AVFoundation source is prepared; no Apple SDK/xcrun is installed on this Windows
host, so Apple compilation was not performed. Linux native validation is pending.
Android diagnostics executed only the offline decoder in its task-owned temporary
directory. No playback, audio routes, BLE, serial, speaker or firmware operations
were performed; installed app validation is a separate integration check.


## Offline platform fallbacks

The public C ABI and Dart API are unchanged. Input is still one regular local
file at most 64 MiB, and caller output is still at most 102378 mono PCM16 samples.
Native fallback accepts ISO MP4/M4A, ADTS AAC and Ogg containers, never URL
playlists. Unsupported codecs return code 4; short or incomplete selected PCM
returns an error with `written=0`, without filling missing frames with silence.

| Platform | Backend | Current evidence |
|---|---|---|
| Windows | Media Foundation Source Reader from a bounded IStream | Actual M4A/AAC, ID3-prefixed AAC and Ogg/Vorbis probe/decode passed on this installation |
| Android | NDK MediaExtractor + MediaCodec, linked `mediandk` | arm64 and ARMv7 API 24 libraries compiled; arm64 offline WAV/MP3/FLAC/M4A/AAC/Ogg decoding and selected clips passed on Redmagic NX809J |
| iOS/macOS | AVFoundation resource loader + Asset Reader | Source and Objective-C++/framework build shells prepared, not compiled |
| Linux | Existing pinned miniaudio path | WAV/MP3/FLAC source prepared; AAC/M4A/Ogg native fallback returns unsupported |

Ogg support depends on the platform's installed codecs. The Windows test accepts
actual nonzero decoded PCM or an explicit unsupported result, rather than
claiming every Windows installation supplies that codec. This installation's
Ogg/Vorbis fixture decoded successfully. No codec binary is downloaded at runtime.

Windows queries the actual AAC output format after priming decoded PCM, because
its initial advertised rate/channel defaults can change. MP4 uses the container
presentation duration. Raw ADTS AAC duration and seeking can be estimates, so its
probe counts actual timestamped PCM and segment decode starts at origin. ID3
prefixes are removed as a bounded view into the same open file. No pathname is
reopened: Windows IStream clones share the one protected handle, Android receives
its descriptor plus offset/length, and Apple serves bounded `pread` resource
requests from that descriptor. Apple also forbids references to media outside the
selected container through AVURLAssetReferenceRestrictionsKey.

Decoded output format, timestamps, buffer sizes and Android buffer offsets are
validated. PCM16 and float32 Android output are accepted; other output encodings
or midstream rate/channel changes fail explicitly. The Android decode loop has
a 30-second per-call deadline; Apple metadata loading has a 15-second deadline.
Android native compressed segments retain decoder history from stream origin.
The selected window discards prior PCM without retaining it, which preserves AAC
priming and deterministic excerpt samples. Raw ADTS metadata requires a full PCM
count; segment decoding then recreates the decoder on the same file descriptor.
The existing deadline spans both passes. Late selections in very long inputs may
reach that deadline and fail explicitly; they never return padded output.
Native fallback rates are limited to 1000..192000 Hz and 1..32 channels. Only the
selected mono source window plus resampler warm-up/look-ahead is retained, capped
to four million float samples. Missing timestamp ranges are rejected. Filter
boundary extension is applied only after all declared source frames in the window
were actually decoded; an early EOF is never padded to manufacture success.

Android compile reproduction, from this package (adjust installed SDK path):

```powershell
cmake -S src -B build/android-arm64 -G Ninja `
  -DCMAKE_TOOLCHAIN_FILE=C:/Users/ngocv/AppData/Local/Android/Sdk/ndk/28.2.13676358/build/cmake/android.toolchain.cmake `
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 `
  -DCMAKE_BUILD_TYPE=Release `
  -DCMAKE_MAKE_PROGRAM=C:/Users/ngocv/AppData/Local/Android/Sdk/cmake/3.22.1/bin/ninja.exe
cmake --build build/android-arm64
```

Use `armeabi-v7a` and another build directory for the second compiled ABI.
Both resulting binaries depend on `libmediandk.so`, not an app MethodChannel.
Apple forwarders now use `.mm`, ARC, AVFoundation, AudioToolbox, CoreMedia and
Foundation. Their resource loader deliberately uses no AVAudioSession,
AVAudioEngine, playback or output-device API.

Media Foundation is delay-loaded on MSVC builds and probed from the Windows system directory. Its absence does not prevent the portable WAV/MP3/FLAC library path from loading; native-only containers return unsupported. Delay-import structure was inspected on this host; a Windows edition without Media Foundation was not available for runtime testing. Apple source uses the selected audio track duration and origin, rather than the duration of unrelated tracks in a movie.
