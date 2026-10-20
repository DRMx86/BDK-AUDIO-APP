# Redmagic AOT surface observation

Two read-only SurfaceFlinger histories were captured from the installed 0.5.5
ARM64 AOT preview on Redmagic serial `9125299103B7`, in explicit Spectrum Demo.
The package hash is recorded in the release-assets checkpoint. No tracing
counters were reset and no device or Bluetooth setting was changed.

The selected app-owned layer was
`25c986c SurfaceView[com.bdkaudio.controller/com.bdkaudio.bdk_audio.MainActivity](BLAST)#41997`.
Raw inputs and the calculated JSON are ignored artifacts:
`redmagic-055-surface-latency{,-2}.txt` and
`redmagic-055-surface-summary.json`.

The column interpretation follows AOSP's
[FrameTracker dump](https://android.googlesource.com/platform/frameworks/native/+/refs/heads/main/services/surfaceflinger/FrameTracker.cpp),
observed source blob `93d0313e535f4219807dd75092a214e8be078406` on 2026-10-16:
desired presentation, actual presentation, frame-ready time. Zero and pending
`INT64_MAX` presentation values were excluded. The OEM history length is observed,
not assumed to match the AOSP ring size.

| History | Completed distinct presentation timestamps | Span | Median interval | Maximum interval | Recorded cadence |
|---|---:|---:|---:|---:|---:|
| First | 190 | 3.14368s | 16.6333ms | 16.6364ms | 60.1206Hz |
| Second | 190 | 3.14401s | 16.6350ms | 16.6388ms | 60.1144Hz |

The newest completed timestamp advanced 44.233405 s between captures; host output
file times advanced 44.236045 s. This confirms fresh advancing histories rather
than repeatedly reading a stopped surface. `/proc/uptime` uses a different
sleep-inclusive time base, so it was not used to infer timestamp age.

These are two short compositor presentation histories, not the LED algorithm's
simulation rate, long-run frame pacing, CPU/energy measurements, panel refresh
attestation or real speaker synchronization. The preview's 30 Hz input/render
clock is separately covered by cadence tests. No live BLE/music claim follows.
