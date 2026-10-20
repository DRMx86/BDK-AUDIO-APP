# Development checkpoint — 2026-10-16

This is an incomplete development build, not a production release. The project
goal remains active. Latest user scope is the app and phone only: no ESP32 source
changes, builds, serial access or flashing. Previously proposed firmware work is
cancelled; the supplied firmware project was never edited or flashed.

## Implemented and exercised

- Focused Sound / Light / Speaker navigation, adaptive rail/bottom navigation,
  bundled Manrope/Space Grotesk fonts, system/dark/light appearance.
- Twelve original Android presets with Kotlin integer conversion, four favorites,
  named local profiles, tactile tone pillars and current-preset curve fingerprint.
  Cards say “Choose preset” and have miniature curves. The native phone check
  exposed a loose width constraint that collapsed those curves; a failing width
  regression reproduced it, and explicit available width repaired it.
- Source-correct full-range/split output, bass boost and low/high output swap.
  Full-range bypasses crossover while EQ stays active. Swap is disabled in that
  mode and its stored bit is preserved. Wire levels are not applied decibels.
- Portable C++ renderer reuses all 22 effect classes unchanged. Provenance hashes
  match the supplied led_effects.h, led_config.h and fast_math.h. This proves
  source reuse, not measured physical pixel parity.
- Existing positive 0–100 meter positions are displayed with zero baseline on
  Light. Source band labels are 30/60/100 Hz. App-side AGC/beat estimates feed the
  source effects. Missing DSP boost/peak/history and random state prevent exact
  physical frame reconstruction. Stale/missing data becomes silence; connected
  previews never substitute demo music. No new BLE characteristics or commands.
- Full-card Gaussian diffusion with uniform square geometry, effect name only
  inside artwork, accessible play/pause beside the heading. All 22 picker tiles
  have purposeful vector symbols and restrained source-generated glow. Both
  Ambient paths immediately expose the same controls; Off preserves settings.
- Actual universal_ble adapter and bounded session lifecycle, startup sync,
  ACK/error distinction, command coalescing, stale-generation isolation and an
  exclusive transfer writer. Small unframed full-status packets are rejected.
- Audio-first pairing restores the original Android A2DP identity gate: no audio
  connection means no BLE discovery. Candidates must have both the service and
  the selected connected audio MAC. Other platforms explicitly require OS audio
  confirmation until their route adapters are validated. First launch, empty
  results and minimal connecting/cancel states are covered.
- Review regressions cover cancellation during audio refresh, audio switching
  while BLE connects, Demo isolation, stale ACK versus newer draft, refusal
  rollback and old cleanup versus a new same-device connection.
- Android CDM/codec backend compiled with 8 standalone JVM tests. Dart codec
  models/controller and the focused Audio quality screen have 42 targeted tests.
  Choices use reported codec/rate/depth/channel combinations and submission is
  confirmed only by fresh same-device readback. Bitrate and quality modes remain
  device-managed pending verified mappings. Actual native negotiation is untested.
- Codec route ownership follows the screen lifetime through its closing animation.
  Resume-during-pop reproduced a disposed-controller failure, then passed after
  moving ownership into a route widget. A tall-phone no-audio layout regression
  caught excess vertical centering; detail content now begins below the title.
- Four speaker-sound editors, bounded offline import/conversion, explicit clip
  selection, local playback and persisted drafts; app-side upload/delete/mute
  state machines are implemented. See the [sound checkpoint](2026-10-16-sound-import-checkpoint.md)
  for review repairs, actual phone/desktop evidence and physical transfer limits.
- Original Android preset import and failure-safe library commits; app-side local
  raw/encrypted update inspection, transfer state machine and explicit reconnect
  reported-version checks. See the [import/update checkpoint](2026-10-16-import-update-checkpoint.md).
  Installed preview builds keep speaker update actions disabled.

## Current native evidence

- Flutter 3.44.4 / Dart 3.12.2, Android API36, NDK28.2.13676358, MSVC19.44.
- Android arm64 debug app installed on Redmagic NX809J / Android16, serial
  9125299103B7, com.bdkaudio.controller version0.4.0(2007). Original
  com.example.myspeaker remains installed. Samsung was never targeted.
- Design build uses BDK_PREVIEW_ONLY=true. EQ/LED/control changes stay local;
  existing status/meter notifications may be read for the phone preview. Demo
  disconnects control transport and guards mutations independently.
- Actual phone screenshots verified setup, Sound, current/preset curves, Light,
  effect picker and Fire animation. Phone captures remain local and ignored by
  Git because they include the user's system UI.
- A phone-only diagonal seam across the blurred artwork reproduced on a paused
  frame. Switching the texture composition from advanced screen blending to
  additive light removed the seam in the same paused frame after hot reload.
  Geometry, source pixels and Gaussian blur were unchanged. Captures:
  redmagic-light-seam-before.png / redmagic-light-seam-after.png.
- Fire selection rendered and two actual phone captures had different preview
  pixels (redmagic-fire-a.png / redmagic-fire-b.png). This checks animation in
  explicit Demo; it does not prove live meter or physical LED synchronization.
- Current Flutter suite: 364 passed, one optional screenshot test skipped.
  Analyzer: no issues. Native C ABI suite previously passed 9 tests with unchanged
  engine sources. Decoder checks passed 174 offline Android cases, 16 Windows
  C ABI cases, one PCM-window test and five Dart FFI/isolate tests. Windows x64
  debug rebuilt successfully with the current source. Native Windows GUI and
  local M4A import were inspected separately; Windows BLE remains unverified.
- Historical 0.1.0 session synchronized with BDK SPEAKER firmware1.0.3 using valid
  status. Latest user report: Bluetooth audio is not connected/playing yet. Live
  BLE-driven reaction, hardware ACKs and physical effect comparisons remain open.
- Browser v11 remains a secondary simulated design review surface on localhost
  49468; native source frames come from the loopback renderer on49469. It is not
  physical BLE evidence.

Installed APK artifact: artifacts/bdk-audio-design-preview-0.4.0.apk,
90,279,358 bytes, ARM64 only. Local artifact, transferred file and installed base.apk
SHA256 matched:
`f0f4ca5fad8deb2ba5e8d940f6b2f5838b28253eddd16b4d40fd74b8cf2b2764`.
All curve, blend, pairing, codec lifetime and detail alignment repairs are baked
into this package and verified after a cold launch. Final phone captures:
redmagic-audio-quality-v021.png / redmagic-light-v021.png cover the preceding
design checkpoint; sound evidence is tracked separately. No live reaction claim.

Build uses --split-per-abi --target-platform android-arm64 --build-name=0.4.0
--build-number=7 --dart-define=BDK_PREVIEW_ONLY=true. Flutter's ARM64 split adds
2000 to the version code, producing2007. Future local upgrades should retain the
split strategy or use a version code greater than2007; do not uninstall user data
to work around a version downgrade.

## Build and phone tooling

- Kotlin incremental caches cannot relativize C: Pub cache and D: source paths;
  incremental Kotlin compilation is disabled in this project only.
- Project NuGet.Config supplies the official HTTPS feed without global changes.
  Windows CMake bundles inside the project; no Program Files install target.
  Project-local plugin junctions avoid a global Developer Mode change.
- ADB push measured about0.5 MB/s. Installation and inputs always target the
  Redmagic serial. No ADB server reset or other-device input is required.
- OEM logs omitted the Flutter VM URL. tools/read_flutter_vm_uri.py reads only
  the app's FlutterJNI static field via JDWP without invoking methods, suspending
  the VM or writing memory. Token-bearing output stays under ignored artifacts/.
  Flutter attach receives the original device URL and performs its own forward.
- A stale coordinate tap once landed in Bluetooth settings and attempted an
  unrelated connection; no firmware was changed. Subsequent semantic taps use
  tools/phone_ui.ps1: unique fresh dump, exact package/target and foreground checks,
  cancellation on missing/ambiguous targets. Stop automation when the user changes
  the phone view. No subsequent unrelated device interaction is authorized.

## Required work remaining

Negotiated codec readback on Redmagic and verified bitrate/quality controls;
physical sound upload/delete/mute and audible speaker playback; authorized physical
update/reboot validation; trusted hosted source/signing configuration; live BLE
testing after audio starts; Windows BLE runtime,
Apple/Linux builds and physical validation; accessibility/usability/performance
checks; signing and release packaging. Exact physical frame matching is not
promised from the existing three-byte meters. No firmware work or hosted release
is included in the current scope.
