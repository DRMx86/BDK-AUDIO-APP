# Native preview cadence and profiling

2026-10-16. This is a finite baseline of the real Light widget, native source
renderer and diffusion painter. It uses explicit demo/synthetic input and no BLE
transport, music playback, codec setter or ESP32 operation. It is not a full-app,
connected-audio, low-end-device, battery, long-soak or GPU-presentation result.

## Demonstrated cadence defect

The app had a 30 FPS ticker, but every incoming meter update also called the
stateful native effect. Measured native calls increased with input frequency:

| Synthetic input | Redmagic before → after | Windows before → after |
|---|---:|---:|
| 30 Hz | 60.4 → 30.1 calls/s | 60.3 → 30.0 calls/s |
| 60 Hz | 90.2 → 30.1 calls/s | 92.4 → 30.1 calls/s |
| 100 Hz | 90.2 → 30.1 calls/s | 130.1 → 30.0 calls/s |

The unchanged effect classes advance state when called. The owned portable
`led_config.h` declares a default `LED_FPS=30`; the app's existing demo clock is
also 30 FPS. This defect made animation speed depend on data cadence. It also
invalidated in-flight image decodes on every input, which can starve display on a
slower device.

Inputs now retain their latest values while effect updates follow that same
30 FPS clock. Short beats are queued and consumed once; clearing a meter drops
its queued beat. Settings/connection changes still force a fresh frame. No effect
source class, source geometry or diffusion quality was changed. The existing
protocol does not report an overridden physical firmware FPS, so exact physical
clock/frame parity is not claimed.

The 100 Hz widget regression first produced99 native calls in its simulated
one-second input window, then passed the bounded cadence/latest-value/short-beat
checks. A queued beat surviving a meter clear was also reproduced and fixed.
The real native after-runs confirm about 30 effect updates/s for all input rates.

## Native evidence

Flutter 3.44.4 / Dart 3.12.2, profile/AOT mode, one-second warmup and six-second
measurement for each of nine cases: Spectrum, Fire, Plasma, Kaleidoscope, Bass
Reactor, Ambient, and Spectrum with synthetic 30/60/100 Hz input. Actual fixture
tick counts are reported; event-loop timers are not precision acquisition clocks.

| After-run target | View / pixel ratio | Reported refresh | Frame timings | UI/raster over display budget | Over 33.3 ms preview budget |
|---|---|---:|---:|---:|---:|
| Redmagic NX809J | 1216×2688 /3.25 | 60 Hz | 3,257 | 0 | 0 |
| Windows local host | 1264×681 /1 | 240 Hz | 12,964 | 64 | 0 |

On Redmagic, build P95 spans 3.09–7.85 ms and raster P95 spans 1.91–2.08 ms across
these cases. Maximum total span was 17.582 ms; total span includes vsync delay and
is separate from individual build/raster budgets. Windows has occasional samples
over its 4.17 ms display interval; this is not a 240 FPS guarantee or a measured
physical dropped-frame count. No general latency or energy improvement is claimed
from the reduced native call count.

The after-runs remained foreground, had reduced motion disabled, recorded native
render activity throughout each full measured second, and observed a timing
watermark past the final measurement boundary. Run identity/PID matched the fresh
launch progress. Both were marked conclusive for this bounded workload.

Raw numeric reports:

- [Redmagic before](native-profile-redmagic.json) and [after](native-profile-redmagic-after.json)
- [Windows before](native-profile-windows.json) and [after](native-profile-windows-after.json)

Raster duration measures Flutter's raster thread, not completion of a physical
GPU presentation. The scope follows Flutter's
[physical-device profiling guidance](https://docs.flutter.dev/perf/ui-performance)
and [frame timing API](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html).

## Reproduce safely

```powershell
flutter build apk --profile --no-pub --split-per-abi --target-platform android-arm64 -t tools/native_preview_profile.dart --dart-define=BDK_NATIVE_QA=true --dart-define=BDK_PREVIEW_ONLY=true
flutter build windows --profile --no-pub -t tools/native_preview_profile.dart --dart-define=BDK_NATIVE_QA=true --dart-define=BDK_PREVIEW_ONLY=true --dart-define=BDK_PROFILE_REPORT_DIR=D:/chosen/workspace/artifacts/profile
```

Android uses the separate `com.bdkaudio.controller.nativeqa` package. Inspect the
APK manifest before installation; the normal app ID must not be replaced. The
Gradle identity policy rejects diagnostic targets without an explicit true QA
define, including Windows/absolute paths. 22 standalone Java cases pass, and an
actual Flutter build without the flag was rejected during Gradle configuration.
Normal `lib/main.dart` builds retain `com.bdkaudio.controller`.

The benchmark rejects non-profile execution, writes an incomplete current record
before native renderer construction, and gives each run a unique identity and
PID. Successful historical reports remain separate. Failures/interruption do not
reuse a previous success. Pointer, keyboard and semantic interaction cannot pause
the measured child. Background/reduced-motion changes and renderer failures are
latched. Every full measured second requires successful render activity; empty or
truncated timings are inconclusive. A timing watermark has a finite 5 s deadline;
missing frame stamps also time out. These safeguards have focused regression tests.

Capture the new progress run ID and process ID immediately after launching. Read
the result only when progress is complete and both identities match that fresh
run. Do not treat an old file's existence as a completed measurement. Android
reports reside in the QA package's own external files directory; the desktop
override should point inside a chosen workspace. Restore the default app target
after profiling, and remove only the self-created QA package/artifacts as needed.

Independent review found three Important tooling risks, all fixed with focused
regressions. Its timing-drain finding was raised from Minor to Important because
a missed late frame could hide the worst sample; the watermark replaces the
assumed two-second drain. No second review or full production approval is implied.
