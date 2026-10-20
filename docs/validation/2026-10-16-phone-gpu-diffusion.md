# Phone graphics and GPU diffusion checkpoint 0.6.8

Source: `0a86eef9ece7d0f6a3ee39f377b404d2796b44c0`, version0.6.8+26.
The user clarified that hardware acceleration must work in the phone app, then
explicitly approved installing and testing graphics only on the Redmagic.
No original ESP32 access, connection, settings/audio/sound/OTA write or playback
was performed. All installed builds use normal `lib/main.dart`, PreviewOnly and
timing diagnostics off. The broad release goal remains paused.

## App change

Android hardware acceleration was already enabled. Previously the portable
native wrapper prepared the continuous Gaussian fields on the CPU, then a GPU
shader composed them. The new supported route records four GPU shader passes:
horizontal/vertical core and halo, each summing16 source samples. Float32 targets
stay GPU resident through `Picture.toImageSync`; the final shader retains the
existing light geometry, title shading and dither before display quantization.
No per-frame CPU field generation or GPU readback occurs on this selected route.
Uniform frames such as Beat Pulse keep their analytic GPU path.

The installed Flutter engine's Skia path silently requests RGBA8 despite a float
picture target. Consequently the GPU route requires Impeller and a completed
one-time fractional Gaussian conformance check. Both output fields are compared
with independent double-precision values before enabling the path. Unsupported,
failed or low-precision targets retain the existing continuous native-float
preparation and hardware shader composition. No backend is labeled GPU-float
merely because a deferred image constructor returned successfully.

Relevant API: [Picture.toImageSync](https://api.flutter.dev/flutter/dart-ui/Picture/toImageSync.html).
Installed engine evidence is in `engine/src/flutter/lib/ui/painting/picture.cc`
and `shell/common/snapshot_controller_impeller.cc` under the pinned Flutter SDK.
Four per-preview shader instances, recorded image references and explicit
disposal preserve pending image lifetimes. Layout and optics work never call the
effect renderer or advance its clock. Source effect headers and live inputs are
unchanged. Main and gallery use the same implementation.

## Verification

- 605Flutter tests pass,2skipped (the pre-existing optional capture and the
  Impeller-only test on the host's Skia tester). Analyzer clean7.1s.
- The missing GPU module/selection API failed before implementation. The raw
  fractional-picture probe on Skia rounded.12345 to.121568635; installed engine
  source confirms its8-bit target. This failure is retained and guarded against.
- Scoped review found no material remaining production issue. A once-only
  production activation event and per-view fallback error distinguish successful
  startup conformance from a later construction fallback. No UI diagnostics added.
- All Android ABI packages passed manifest/API24→36, ELF, development signature,
  CRC, both compiled shaders and eight bundled-notice checks. Build63.3s.
  A prematurely run package check correctly rejected stale0.6.7 before the build
  finished; its failed badging receipt is preserved and excluded.

## Native Redmagic evidence

Explicitly re-identified nubia NX809J, Android36, serial9125299103B7, screen on
and unlocked. Installed ARM64 versionCode2026,20,851,046bytes, SHA256
`11e9119adf6204c8af596234d0bd73ba032fefa8f44a98770a1da51e6e1e6b2c`;
local, staged and installed hashes match. App data was preserved. PID24635 at
verification. Exact temporary APK removed.

`artifacts/phone-gpu-068/gpu-native-startup-ready.png` shows actual native
Light/Spectrum Bars, local firmware Demo, brightness70% and playing. The large
contour bands from the Windows emulator captures are absent; diffusion is smooth.
The user subsequently reported/questioned the good phone result. No later phone
input was sent: the next foreground guard found Settings and stopped before
capture. Preserve that active Settings session.

Own-PID logcat was empty on this vendor phone, as in earlier QA. Therefore this
receipt verifies installed identity and native graphics appearance, but does not
claim an independently extracted phone float-field backend report or measured
phone FPS. The144Hz status indicator is not an app animation benchmark.
`phone-graphics-receipt.json` contains the hashed native screenshot and this limit.

## Hardware emulator evidence and presentation limitation

The user's coarse screenshots were reproduced in the Windows emulator window
while simultaneous native guest PNGs retained smooth dark levels. User PNG
plateaus at0/20/28/34 differ from native consecutive dark values. The shader's
emitting-card background cannot produce the widespread exact zero channels in
those Windows images. This establishes the output/presentation boundary; it does
not identify HDR as the cause.

AOSP's `host/gl/texture_resize.cpp` applies gamma2.2 during resizing and inverse
gamma afterward. Matching strings exist in the installed gfxstream DLL. Its
actual selected intermediate storage precision was not queried, so an8-bit
resizer allocation remains a hypothesis. Native-size/factor1 bypasses this path
in source. Physical Escape interrupted Computer Use twice; subsequent work used
ADB, leaving screenshot shortcuts alone.

Software rendering was abandoned on the user's instruction. A documented
`VulkanNativeSwapchain` experiment crashed this emulator before boot and was
reverted. A later Vulkan-enabled run also exited in NVIDIA's `nvoglv64.dll`,
exception0xc0000409; Windows error receipts are preserved. No driver, global HDR
or Windows setting changed, and no crash report was submitted.

The owned emulator is now running real NVIDIA hardware OpenGL:
`-gpu host -feature -Vulkan`, with process-local `QT_SCREEN_SCALE_FACTORS=1` for
the scaling comparison. WHPX/AVD data remain intact. This excludes software
rendering; Flutter reports **Impeller (OpenGLES)**. Installed x64 versionCode4026,
22,341,168bytes, SHA256
`db9f06fd6dc2cb606364801124ed9ee9f68dd081b4cd7a54daaf29b280ff6a0d`;
installed hash matches, verified PID3433.

Native completed probe reports `ready`, acceptedtrue, core maximum error
6.3079755e-8 and halo3.1400829e-9 in57ms. Actual Spectrum then logs
`BDK_GPU_LIGHT_FIELDS active: impeller_float32`, with no fallback event.
Two native PNGs show continuing GPU-rendered Spectrum. The failed driver run
lost the emulator package state, so the exact verified x64 APK was reinstalled;
no AVD wipe was performed. The final hardware-GL run is stable through these checks.

These native GPU results do not prove the Windows window's rescaled presentation
has been repaired. Its final appearance was not independently re-captured after
the process-local scaling change. The phone's native result is the product visual
evidence; the remaining emulator presentation issue is recorded as a QA limitation.
GPU/native details and failures are preserved under `artifacts/led-quality-068`.
