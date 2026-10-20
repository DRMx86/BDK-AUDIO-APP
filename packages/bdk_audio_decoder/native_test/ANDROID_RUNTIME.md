# Offline Android decoder regression

Validated on the explicitly authorized Redmagic NX809J, Android 16 / API 36,
arm64-v8a, ADB serial `9125299103B7`. This is a native C ABI check, separate from
installed Flutter app validation. It does not play audio or change routes,
settings, BLE, the installed app, or firmware.

## Measured failure and repair

The generated `real.m4a` reports 16000 Hz, mono, 32000 presentation frames. Its
track contains `encoder-delay=1024`; the first compressed packet has timestamp
`-64000 us`. Before the repair, probe returned success, but decoding 44100 output
frames at 22050 Hz returned code 9 / `written=0`. Seeking to zero after priming
skipped the negative pre-roll. MediaCodec then applied encoder delay after flush,
and the first physical PCM packet started at frame 1024. The strict window
correctly rejected the gap. A second measured EOF failure treated the extractor's
no-sample flags as encryption and returned code 4 before draining the codec.
The [AOSP extractor implementation](https://android.googlesource.com/platform/frameworks/av/+/refs/heads/main/media/ndk/NdkMediaExtractor.cpp#208)
returns `uint32_t(-1)` when sample metadata is unavailable, so its bits must not
be interpreted as flags on an EOF result.

After retaining primed PCM and checking flags only for a valid input sample, the
same file returned code 0 / 44100 samples, 44098 nonzero, with output guards intact.
Late seek/flush excerpts also showed a maximum 873-unit difference from the same
origin conversion. Android native segments now decode from origin, discarding
prior PCM without retaining it. This preserves decoder history. ADTS metadata
scans are followed by a fresh decoder on the same already-open file descriptor;
the 30-second deadline is not reset. Missing PCM is never synthesized.

The matrix verifies all four output rates, full and nonzero/tail clips, six-second
M4A excerpts, extension-independent `.audio` cache input, 44.1-kHz stereo AAC,
WAV unknown chunks/float/extensible, MP3, FLAC, raw/tagged AAC, M4A and Ogg/Vorbis.
Excerpt comparisons differ by at most two PCM units from origin conversion.
Truncated inputs, unsupported rates and invalid ranges return errors rather than
PCM success. A selected 1000-frame excerpt at second 110 in a two-minute M4A
completed in approximately 0.80 seconds, including ADB/process overhead, on this
device. This finite check does not establish timing for arbitrary inputs/devices.

## Reproduction

Generate the fixtures with `python native_test/test_decoder.py` after building the
Windows test DLL. Build Android arm64 as shown in the package README, adding
`-DBDK_DECODER_BUILD_CLI=ON`. `BDK_DECODER_DIAGNOSTICS=ON` enables test-only stderr
format/packet/window tracing; both options default OFF in production builds.

Provision only the opt-in CLI, shared library and generated fixtures into
`/data/local/tmp/bdk-decoder-qa-20261016/`, with every ADB command explicitly using
the authorized serial. Set executable permissions on the task-owned CLI. Then:

```powershell
python native_test/android_runtime_test.py `
  --adb C:/Users/ngocv/AppData/Local/Android/Sdk/platform-tools/adb.exe `
  --serial 9125299103B7
```

The script performs only bounded offline CLI executions against that directory
and writes `build/android-runtime-green.json`. Each case records typed return
code, frame count, nonzero count, peak, sample hash, guards, comparison and elapsed
time. Source hashes are recorded with the cases. The CLI starts a Binder callback
pool only in its standalone test process; Android app processes already provide
one. This setup is not part of the production decoder or public API.

Local RED traces remain in `build/android-runtime-binder-red.txt` and
`build/android-runtime-seek-red.txt`; the first successful full-frame trace is
`build/android-runtime-trace-green.txt`. Build artifacts and generated fixtures
remain ignored. Vendor miniaudio header/license hashes are unchanged. ARMv7 is
compile-only evidence; Apple and Linux native validation remain pending.
