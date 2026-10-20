# Visible startup, pairing entry and app icon — 0.6.0+18

The earlier startup Future could finish before its branded view became visible.
The installed 0.5.9 did contain setup, confirmed by a fresh native capture, but
its title said “Connect speaker controls” and the compact Demo action said only
“Demo.” Both installed Android applications also shared the label BDK Audio.

Code checkpoint `bfc701b3889a34ea6ed4c56eeb28017aeb437661` addresses these issues:

- Initialization runs in parallel with a brief 750 ms brand intro, timed from
  the framework's first post-frame callback. A ready application no longer skips
  branding. It does not show “Starting up” after loading has completed. Slow
  initialization, errors and explicit retry remain handled; disposal cancels
  the timer. This is an intentional intro, superseding 0.5.9's no-minimum design.
- Idle setup is titled **Pair your speaker**, with a truthful Bluetooth audio
  status. The compact Demo header has a visible **Pair** action. Audio identity,
  same-device discovery, status synchronization and explicit Demo gates remain.
- A newly authored vector B monogram and signal accent replace the earlier
  speaker/circle mark. Native-size exports cover Android, iPhone/iPad, macOS,
  Windows and Linux, plus the three iOS launch-image scales. The original Android
  application and its blue board icon remain installed and unchanged.

## Regression and package evidence

The fast-initialization test failed before the fix because the ready application
replaced branding immediately. New tests cover a visible fast intro, disposal
during the intro and a working phone Pair entry. Existing tests retain real
initialization/error/retry, audio-first gating, reduced motion, narrow/large text
and keyboard/slider behavior. Changed visible labels were updated in the existing
assertions; callback/identity/navigation assertions were retained.

Fresh final verification:

- **537 Flutter tests passed, one optional skip**; analyzer reported no issues.
- Independent read-only review found no material startup lifecycle, pairing-gate
  or export issues.
- Deterministic `export_icons.cjs --check` passed for every generated export.
- Android's 432 px transparent foreground has zero opaque pixels outside the
  66 dp safe circle. iOS app icons are opaque RGB.
- ARMv7, ARM64 and x64 optimized APKs compiled. CRC, API 24→36, expected ELF
  architecture, development certificate and eight bundled notices passed.
- Every APK contains the exact new vector-derived Flutter brand bitmap. The
  final ARM64 AOT contains neither optional timing diagnostic marker.

Logs, hashes and raw capture manifests are in ignored `artifacts/startup-060/`
and `artifacts/android-0.6.0-all-abi/`. Other ABI packages are package-verified;
only ARM64 has this physical-device evidence. New Apple/desktop icon exports do
not imply native builds on those targets.

## Actual Redmagic check

Only serial **9125299103B7**, package `com.bdkaudio.controller`, normal
`lib/main.dart`, PreviewOnly optimized AOT was used. Installed artifact:

`artifacts/bdk-audio-preview-0.6.0-release.apk`, **20,696,482 bytes**, SHA256
`06e4c70a8f7f72b0c7fc210cba3d89d473f5142f56033a0289bcc5dc955671ff`.

Local, staged and installed hashes match. The upgrade preserved app data.
Android reports version 0.6.0 / code 2018, observed app PID **17706**. Signing is
still the development Android Debug certificate, rather than production signing.

The cold-start PNG shows the new centered B mark and BDK AUDIO wordmark on the
dark full-screen background. The native recording contains 85 actual encoded
video frames, showing branding enter and then transition to real setup. The
reference-image matcher confirms nine aligned brand frames; its 72 ms span
excludes the moving window transition and must not be described as the entire
intro duration or a startup performance benchmark.

The settled native page shows **Pair your speaker**, verified Bluetooth audio,
BDK SPEAKER and Find speaker. Native launcher captures show the new B icon beside
the original blue board icon, with the new foreground fitting its launcher mask.
Own icon pixels and fresh semantics guarded selection. Explicit Demo opens the
Sound page with a visible Pair button; tapping its actual clickable native node
returns to the pairing gate. The final native XML confirms the route and action.

Two partial QA scripts were preserved: the installer completed hash checks and
captures, but a subsequent semantics dump was interrupted by Home; the first
Demo selector looked for the labeled parent rather than the clickable Pair child.
Fresh native selection of that child and final package/XML checks passed. App
exit records showed package update/earlier owned force stops, with the new app
process still alive. No crash was established by the foreground change.

There are **12 hashed native PNG/XML/video entries** in the capture manifest.
Uniquely owned temporary APK, recording and XML files were removed. No BLE
connection, speaker setting, sound/OTA transfer, ESP32 source/build, serial or
firmware operation occurred. Broad platform, hardware and release gates remain
separate from this installed UI checkpoint.
