# Musical B reveal and full discovery — 0.6.3+21

Code checkpoint `9511c73200e4f76b2843959d40b7829956546477` includes the
requested visible two-second B hold, 700 ms zoom into the actual application,
five-second discovery/retry window and full-page finding/recovery design.
It supersedes the rejected static intro and compact setup presentation in 0.6.0.

The B and eighth note are original vector artwork. Android's platform starting
surface has a matching dark background and transparent icon; the API 31+
SplashScreen exit listener removes it immediately at handoff. The custom B is
the only visible logo sequence. Android still owns a starting window while the
engine initializes, as described in its [SplashScreen documentation](https://developer.android.com/develop/ui/views/launch/splash-screen).

An emulator recording of 0.6.2 exposed an additional timing problem: a CPU
post-frame callback could start the intro clock before the first visible raster.
The final intro waits for `waitUntilFirstFrameRasterized` before starting its
full hold. Initialization remains parallel, and the ready application mounts
once during reveal. Reduced motion, slow loading, errors, retry and disposal
retain their existing behavior. Native adaptive foregrounds fit the 66 dp circle.

Discovery uses an animated speaker/radar and one shadowed status card. Audio
checking, BLE finding, results, connecting, permissions and no-results remain
separate truthful states. Existing same-device/audio/service/status gates remain.
Read-only automatic discovery is independent from automatic connection. A scan
does not finish early when a candidate arrives; late candidates do not introduce
another full wait. No-audio retries perform a fresh OS query at the deadline.
Cancel, background, replaced requests and late permission replies cannot revive
an abandoned search. PreviewOnly continues to disable automatic connections.

## Verification

- **568 Flutter tests passed; one optional skip.** Analyzer reported no issues.
- New first-raster regressions failed before the fix and passed afterward.
  They cover a delayed raster, the full visible hold, reduced motion, disposal
  and an error/retry before raster completion. Fourteen focused brand/startup
  tests passed. Existing discovery/cancellation/permission tests also passed.
- Independent scoped reviews found no remaining material timing/lifecycle
  findings. Earlier fresh-query, permission-race and late-candidate findings
  were reproduced and fixed before the final suite.
- Deterministic icon export checks passed for five platforms. At 432 px the
  adaptive foreground has zero nonzero-alpha pixels outside the safe circle.
- ARMv7, ARM64 and x64 optimized APKs compiled; API 24 minimum/36 target, ELF
  architecture, ZIP CRC, common development certificate and eight notice assets
  were checked. These are development-signed previews, not production releases.

## Actual Android emulator evidence

The user switched testing from the phone to an emulator. All subsequent inputs
and installation used only owned AVD `BDK_Animations_API36_20261016`, serial
`emulator-5580`, Android 36 Google APIs x64, Emulator 37.2.12 with WHPX/host GPU.
No global driver/feature change, phone operation or ESP32 operation was performed.

Installed package `com.bdkaudio.controller`, normal `lib/main.dart`, PreviewOnly,
diagnostics off, version **0.6.3+21**, x64 code **4021**:

- APK **22,264,504 bytes**, SHA256
  `de01bde7f27515568e74faaf37485fd7df10eef069d045d9c2f1f3354a7a305c`.
- Local, staged and installed APK hashes match. Prior APKs were preserved.
- Cold-launch video: **446 encoded frames, 17.718289 s**, 1080×2400. Actual
  frames show the dark native handoff without a launcher-icon flash, the B
  holding for about two seconds, vector zoom/aperture and full animated finding
  page. This is a visual timing observation, not a frame-rate benchmark.
- Retry video: **279 encoded frames, 14.898422 s**. A fresh native Search again
  action stays in animated Bluetooth-audio checking at the four-second capture
  (capture completed at 4.422 s), then shows full-page No speaker found at the
  6.5-second capture. The video shows about five seconds of checking. The exact
  five-second controller default is pinned by tests.
- Explicit Demo opens Sound; Light runs its native x64 renderer. Actual Sound,
  Light and discovery surfaces were visually inspected. Pair returns to animated
  checking, then full no-speaker recovery. The emulator is left in that state.

UIAutomator could not reach idle while the LED preview was animating, so the
first Pair automation attempt stopped before input. Its capture named
`emulator-return-finding.png` actually remains on Light; do not use it as proof
of return. The successful attempt used a fresh screenshot, an exact pixel match
against the inspected Pair header, foreground/AVD guards, and subsequent native
searching/recovery captures. The failed attempt remains recorded.

Raw videos, PNG/XML captures, hashes, actions, package receipts and logs are in
ignored `artifacts/discovery-063/` and `artifacts/android-0.6.3-all-abi/`.
Earlier 0.6.1/0.6.2 captures are retained separately.

No peer, music or meter data was injected for discovery. The emulator had no
Bluetooth audio speaker; this validates the native empty-audio flow and motion,
not physical BLE discovery, connection, codec or music telemetry. Found and BLE
no-results states have deterministic controller/widget coverage. The phone
remains at 0.6.0; other platforms and the broader production goal remain open.
