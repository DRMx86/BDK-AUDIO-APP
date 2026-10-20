# BDK Audio Flutter Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the approved cross-platform BDK companion with real speaker control, detailed capability-checked codec settings, and firmware-faithful LED effects.

**Architecture:** Flutter owns the responsive UI, immutable device models, BLE session and transfer state machines. A portable FFI library reuses the firmware's 22 C++ effect classes with a memory-backed LED driver. Existing three-byte BLE meters drive an explicitly estimated reactive preview. Android native channels handle CDM/codec APIs and audio conversion; other platforms expose only verified capabilities.

**Tech Stack:** Flutter 3.44.4/Dart 3.12.2, universal_ble 3.1.0, Riverpod, shared_preferences, file_picker, audioplayers, Dart crypto/ffi, portable C++17 through a Flutter FFI plugin.

**Spec:** D:/ESP32 Bluetooth/BDK-AUDIO-APP-main/docs/superpowers/specs/2026-10-16-flutter-audio-design.md

## Execution

The user explicitly approved: "Yes, build this design". Execute natively in this
session without another approval checkpoint. Work in the separate new repository
`D:/ESP32 Bluetooth/BDK-Audio-Flutter`, branch `codex/flutter-port`; the supplied
source folders are not Git repositories. Keep a durable execution ledger and
perform a fresh whole-change review after the implementation/checks.

## Global Constraints

- Preserve all implemented original app features; track each target separately.
- Android, iPhone/iPad, Windows, macOS, Linux; Apple/Linux native validation needs their runners/hardware.
- Redmagic ADB serial is `9125299103B7`; another Samsung is attached.
- Maintain Sound, Light, Speaker and focused detail pages; no crowded dashboard.
- Latest EQ steering explores tactile pillars/wells/steps beyond the common curve. Use fixed150Hz/1kHz/6kHz bands, integer wire levels-12..12 and accessible drag/48px step targets; DSP scales gains0.5/0.7/0.7.
- LED glow fills the preview card, retains Gaussian diffusion, and has no diffusion caption.
- Match firmware effect identities and geometry. Beat Pulse is a whole-matrix flash; Ripple/Bass Reactor produce rings. Never stretch circles into ellipses.
- No fake live telemetry, codec readback, battery, TWS, transport controls or volume support.
- Preserve original app, firmware SDK, baselines and independent host migration.
- Latest user scope override: app and phone only. Do not edit, build, flash or otherwise operate on the ESP32 firmware or serial devices. Task 9 is cancelled. Existing BLE STATUS/METER are the only preview inputs; do not add protocol commands or firmware prerequisites.
- Keep source fixtures/browser tests distinct from compiled/native/hardware evidence.

## Review Focus

- Delayed notifications from a prior BLE session must not overwrite the new device.
- Small MTU and malformed string lengths must not create false Ready/transfer states.
- Native audio/preview lifetimes must survive disconnect, background/resume, and rapid effect selection.
- Codec setter success must not masquerade as negotiated readback; permission denial must remain usable.
- Zero brightness and stale telemetry must not produce simulated light presented as live.

## File structure and shared interfaces

- `lib/domain/speaker_state.dart`: EqGains, LedSettings, MeterLevels, SpeakerState, ConnectionPhase.
- `lib/protocol/speaker_protocol.dart`: `SpeakerProtocol` packet builders/parsers with 35 source vectors.
- `lib/connection/ble_transport.dart`: abstract transport and typed device/event records.
- `lib/connection/universal_ble_transport.dart`: one actual platform BLE adapter.
- `lib/connection/speaker_session.dart`: `SpeakerSession` owns one transport, queues, status and stream lifetimes.
- `lib/features/{sound,light,speaker,codec,transfers}/`: controllers and focused widgets.
- `lib/persistence/profile_store.dart`: versioned local profiles, device IDs and appearance.
- `packages/bdk_led_engine/`: portable native renderer, C API, Dart bindings and native tests.
- `lib/platform/codec_adapter.dart`: capability/result interface; Android method-channel implementation.
- `lib/app.dart`, `lib/theme.dart`, `lib/main.dart`: app startup, navigation and design system.
- `tools/`, `docs/validation/`: reproducible builds, evidence and target release matrix.

Core model contracts:
`EqGains(int bass, int mid, int treble)`; `LedSettings(int effect, int brightness,
int speed, int color1, int color2, int gradient)`; `MeterLevels(int hz30,int hz60,
int hz100,DateTime receivedAt)`; immutable `SpeakerState.copyWith(...)`.

Transport contract: `Stream<List<DiscoveredSpeaker>> scanResults`,
`Stream<TransportEvent> events`, `Future<void> scan()/stopScan()/connect(String)/disconnect()`,
`Future<int> configureNotifications()`, and `Future<void> write(Uint8List,bool withResponse)`.
The returned capacity is characteristic-value bytes, not assumed MTU.

Session contract: `ValueListenable<SpeakerState> state`,
`Future<void> connect(String deviceId)`, `setEq(EqGains)`, `setLed(LedSettings)`,
`setControl(int)`, `rename(String)`, `disconnect()`; `Stream<ProtocolEvent> responses`.
Transfer code acquires an exclusive session writer; it does not bypass its queue.

Renderer C API: `void* bdk_led_create()`, `void bdk_led_destroy(void*)`,
`int bdk_led_select(void*,int)`, `int bdk_led_settings(void*,const uint8_t*,int)`,
`int bdk_led_render(void*,const float*,uint8_t,int,uint8_t*,int)`.
Render input has seven floats: bass/mid/high linear, bass/mid/high dB, beatIntensity;
flags bit0 beat, bit1 audioActive; demo is explicit. Output is row-major 16x16 RGBA.

### Task 1: Isolated application and firmware-faithful renderer

**Files:** Create app platform shells; `packages/bdk_led_engine/src/{bdk_led_engine.h,bdk_led_engine.cpp}`, `src/led/{led_effects.h,led_driver_spi.h,led_config.h}`, `src/dsp/fast_math.h`, `native_test/test_renderer.py` (actual C ABI), Dart bindings and provenance record.

- [x] Scaffold Android/iOS/macOS/Windows/Linux app and FFI plugin; initialize the new Git branch and run generated baseline analysis.
- [x] Write native tests asserting Beat Pulse is spatially uniform, bass-reactor rings are circular/symmetric, invalid effect IDs preserve state, zero brightness is black, same-effect selection preserves animation, and all 22 effect classes render bounded frames.
- [x] Build/run the test before the engine exists; expected FAIL for missing engine/API.
- [x] Copy firmware effect/fast-math sources with provenance hashes, retain their non-ESP32 math fallback, implement only the hardware-free driver and C API. Preserve HSV/brightness/serpentine semantics.
- [x] Build native tests with CMake/MSVC, run them, and wire the plugin's C++ target. Expected all assertions PASS; do not call that physical parity.
- [x] Commit renderer and its tests; record any necessary host portability changes exactly. Included in the reviewed development checkpoint; source headers unchanged.

### Task 2: Wire models, packet codec and persisted profiles

**Files:** domain/protocol/persistence files above; `test/protocol_test.dart`, `test/profile_store_test.dart`, copied source vectors.

- [x] Write tests for signed EQ bytes, flags 01/02/04, LED ordering, UTF-8 name byte bounds, full-status lengths, malformed/truncated packets, normalized meter dB, Off restoration, and preset-ID separation.
- [x] Run `flutter test test/protocol_test.dart`; expected FAIL for missing implementation.
- [x] Implement pure Dart packet/model boundaries and JSON profile persistence. Preserve the source's twelve Android presets and three custom slots through an explicit migration/import path; new named profiles store actual gains.
- [x] Verify the 35 reference vectors plus state/persistence tests, `flutter analyze`, then commit.

Core protocol/models and named profile persistence are implemented and committed
in the earlier checkpoint. Explicit legacy XML/curated-JSON import, a read-only
development-phone export helper, selection preview and failure-safe persistence
now have tests and native preview evidence. The original phone had no saved
custom fields; no personal migration is claimed.

### Task 3: Real BLE discovery, synchronization and command lifecycle

**Files:** connection files above; `test/session_test.dart`, fake transport fixture, connection UI.

- [x] Write async tests for notification-before-sync, missing characteristic, queued/coalesced EQ final write, ACK error, status truncation, timeout, cancellation, stale old-session events and bounded reconnect.
- [x] Run session tests RED; implement adapter/session with generation tokens, one operation owner, finite deadlines and final-value delivery.
- [ ] Validate GREEN with deterministic fake transport and analyze. Then build Android/Windows and record actual service discovery/status exchanges separately.
- [ ] Commit without claiming hardware success until actual exchanges are captured.

The app now retains audio identity monitoring while controls are Ready, fails the
gate closed after an OS snapshot failure and checks audio again after BLE sync.
Original three P1 races and the subsequent route-monitoring failures have focused
RED-to-GREEN regressions and independent review. Live music validation is pending.

### Task 4: Approved navigation, presets and tactile tone controls

**Files:** app/theme/startup; sound screens and controls; `test/sound_ui_test.dart`, widget fixtures.

- [x] Write widget tests for three destinations, focused detail routes, preset-to-curve values, dragging/clamping, keyboard steps/reset/save, narrow layouts and 200% text scaling.
- [x] Observe RED; implement the dark/light/system BDK design with accessible tactile tone controls and preset curve illustrations. Bind to real session/persistence rather than hardcoded Connected state.
- [x] Run GREEN and inspect rendered Android/Windows output, then commit.

Native Sound/preset UI evidence is in
`docs/validation/2026-10-16-native-platform-checkpoint.md`; subsequent full-suite
and native appearance checks are in
`docs/validation/2026-10-16-light-theme-preview-checkpoint.md`. This completes the
Task4 UI implementation checkpoint, not the release or live hardware gates.

The 0.5.9 checkpoint adds real-initialization branding and minimal animated setup
states, including reduced-motion/error behavior. Actual Redmagic search motion
and matched discovery are recorded in
[the brightness/startup receipt](../../validation/2026-10-16-brightness-startup-checkpoint.md).
No new synchronized BLE session or sustained native Flutter loading view is
claimed from that run.

The subsequent 0.6.0 fix deliberately holds a brief brand intro even when loading
finishes quickly, clearly labels pairing and its Demo entry, and replaces the
launcher mark. Actual native splash, launcher and Pair navigation are verified in
[the visible startup receipt](../../validation/2026-10-16-visible-startup-pairing-icon.md).

### Task 5: Light controls, source renderer, geometry and diffusion

**Files:** light screens/renderer controller/diffusion painter; `test/light_ui_test.dart`, `test/renderer_lifecycle_test.dart`.

- [x] Write failing tests for first Spectrum visit, same-effect selection, rapid changes, both Ambient selectors, Off/restore, stale input, renderer disposal and square-cell geometry inside rectangular cards.
- [x] Implement FFI renderer integration and aspect-preserving source geometry. Extend/background-blend the diffused field to fill the card; do not nonuniformly scale the source pattern. Actual received meters drive legacy reactive preview, explicitly distinguished from exact mirror.
- [x] Run tests GREEN; verify source-generated effect identities for every gallery item and inspect cold-start/resume on Redmagic, then commit.

App implementation checkpoint: the native 22-effect0.5.6 sweep is supplemented by
the two repaired Demo paths in0.5.7 and the sparse gallery exposure, COLD launch
and actual background/foreground continuation in0.5.8. The 0.5.9 brightness fix
keeps active parameter edits on the effect clock; actual Redmagic drag measured
151 source advances in 5,038 ms, with held-thumb tracking separately widget-tested.
Current Flutter suite: 537 passes,
one optional skip; analyzer clean. The
[gallery/native receipt](../../validation/2026-10-16-gallery-exposure-checkpoint.md)
distinguishes the targeted 0.5.8 run from the older full sweep; the linked 0.5.9
receipt records brightness and setup checks. Cross-platform
runtime and actual speaker telemetry verification remain in Task10; this checkbox
does not assert physical frame parity or production release readiness.

### Task 6: Detailed verified codec preferences

**Files:** codec adapters/screens; Android `CodecBridge.kt`/MainActivity channel; `test/codec_test.dart`.

- [x] Write tests for absent access, no A2DP source, capability filtering, invalid combinations, pending setter and timeout/readback mismatch. Bitrate/quality mapping remains open until native support is verified.
- [x] Run RED; port/refactor the original CDM/CodecManager logic into a narrow native bridge. Read capabilities and active config; re-read negotiated state before success. Expose OS-managed states on unsupported platforms.
- [ ] Run GREEN and measure actual Redmagic negotiations without Developer Options. Record each field's source and limits; commit.

Native bridge8 JVM checks and42 Dart codec tests pass. App route lifecycle and
read-only Demo/preview safeguards have additional regression coverage. Whole
  Flutter suite364 passes, analyzer clean. Actual music/codec testing is pending the
user's audio connection; do not call this task complete from unit/build evidence.

### Task 7: Sound import, playback, upload and delete

**Files:** sound management/conversion; Android/iOS converters; portable desktop WAV/MP3/FLAC decoder adapter; `test/wav_test.dart`, `test/sound_transfer_test.dart`.

- [x] Write tests for WAV chunks/PCM bounds, mono conversion, size/trim feedback, sequence wrap, delayed READY/FAILED, disconnect, cancel and completion.
- [x] Run RED; implement the four slots, local preview, conversion and exclusive protocol upload/delete/mute. Preserve original format support on Android/iOS; desktop support must be explicit, with no silent loss of upload functionality.
- [x] Run GREEN, inspect actual Android/Windows local import/preview and commit the reviewed app implementation checkpoint. Record source-defined replacement limits: the existing firmware removes the old sound first, so the app cannot promise atomic replacement.
- [ ] Physically verify upload/playback/delete only after that operation is explicitly in scope. Current user override prohibits operating on the speaker, and the installed preview build disables remote mutations. Apple/Linux native validation remains tracked in Task10.

### Task 8: Verified local/encrypted firmware updates

**Files:** OTA controller/import/download screens; `test/ota_transfer_test.dart`, release-source settings.

- [x] Write RED tests for MTU 23, one-byte tail repartitioning, begin rejection, uncertain writes, missing/failed completion, abort, reconnect and version mismatch.
- [x] Implement bounded transfer states, raw/.enc compatibility, explicit-key AES legacy import, local source information and reported-version readback. Hosted signing/downloads remain disabled until a trusted channel is configured; never report timer-based success.
- [x] Run GREEN; inspect local raw/encrypted file import on the phone, compile Android/Windows and commit the reviewed app-only checkpoint. No physical deployment under the current user scope.

The original AES key is a placeholder, so encrypted imports require an explicit
key and are not authenticated releases. Actual W20 connections remain excluded
by baseline status synchronization; W20 packetization tests are distinct. Hosted
source configuration, signing and physical release validation remain open in Task10.

### Task 9: Cancelled by user scope override

No firmware changes, builds, serial access or flashing. The original ESP32 project
remains untouched. Existing BLE meter packets drive app-side AGC/beat estimates
for the unchanged source effects; omitted DSP history and random state limit exact
physical frame matching. Do not reintroduce a telemetry extension as a prerequisite.

### Task 10: Native validation, accessibility, packaging and review

**Files:** tools/build scripts, CI for native hosts, signing templates, release matrix and user guide.

- [ ] Run analyzer, relevant unit/widget/native tests; inspect final app screens and lifecycle on Redmagic and Windows.
- [ ] Obtain macOS/Linux build runners and real device evidence for iPhone/iPad/Mac/Linux; keep each platform's prepared/compiled/installed/hardware-verified/release-packaged status separate.
- [ ] Validate text scaling, screen readers, keyboard/touch, permission denial, reconnect and long-running audio/preview coexistence. Fix failures with focused RED→GREEN checks.
- [ ] Build Android/Windows packages and target-native Apple/Linux packages with actual signing/distribution configuration. Do not publish or flash without the applicable concrete authorization.
- [ ] Request a fresh whole-change review, address material findings with regression tests, then audit the full goal. Mark complete only when every required gate has authoritative evidence.

## Self-review

All original app parity areas map to Tasks 2–8; all requested visual refinements map
to Tasks 4–5; detailed codec control maps to Task 6; platform/release work maps
to Task 10. Shared interfaces are defined above and consumed without aliases.
The goal remains the whole approved product; an Android demo or compiled renderer
does not satisfy the release/physical requirements for other targets.
