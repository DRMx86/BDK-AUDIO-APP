# Brightness, startup and connection UI — 0.5.9+17

Brightness changes now follow the existing preview clock instead of advancing
the native effect on every slider callback. The held thumb tracks directly;
idle keyboard and accessibility adjustments retain one-percent steps. A branded
startup view covers real initialization, and setup/search/connection waiting
states have a minimal animated halo with reduced-motion support.

App code checkpoints: `f1619d3` and `f47a364`. The latter also keeps the phone Demo
header compact below 480 logical pixels and adds an optional Android timing file
for native QA. Linux-only decoder and runner work remains uncommitted and is not
linked by this Android build. No ESP32 source, build, serial, firmware or speaker
setting operation occurred.

## Brightness regression and real phone measurement

Previously, every settings update invalidated the image decode and forced a
source render. A 100 Hz input test produced 100 brightness renders / 98 Ambient
speed renders in a simulated second, exceeding the independently specified
20–33 frame range. Active same-effect/same-power edits now configure the latest
parameters without forcing a render or invalidating an in-flight decode. Genuine
effect/power changes and inactive previews retain their first-frame path.

Flutter's discrete slider also eased the thumb toward each new value. An actual
thumb-paint test, while a verified pointer remained down, measured 70 logical
pixels of lag after 8 ms before the fix. Continuous movement during the held
gesture passes the next-paint tolerance of two logical pixels. Returning to 100
divisions while idle preserves the existing one-percent semantics and keyboard
tests. The native run establishes real input and source cadence; it does not
measure finger-to-photon latency.

Only the Redmagic **9125299103B7**, package `com.bdkaudio.controller`, was used.
Four guarded 350 ms brightness swipes ran in explicit local Demo. Five timing
intervals contained **151 actual renderer advances over 5,038 ms**, or
**29.972 per second**. Individual frame counts were 30/30/31/30/30 while settings
callbacks reached 39 in one interval. The following two idle intervals each
contained 30 advances over 1,006 ms. These are source/FFI advances, not GPU frame
rate or physical-speaker synchronization.

The first instrumented run's empty release logcat could not prove cadence; that
failure is preserved. The successful run used opt-in
`BDK_LIGHT_TIMING_DIAGNOSTICS=true` and a serialized JSONL file in the app's own
external-files directory. The exact QA trace was removed after the diagnostic
process ended. The final installed APK has diagnostics disabled, with neither
timing marker present in its AOT payload. No global logging or permission setting
was changed.

Recorded verification on the final app code: **534 Flutter tests passed, one
optional test skipped; analyzer reported no issues**. This includes cadence,
thumb tracking, one-percent keyboard/semantics, large text, reduced motion,
startup retry, setup gates and 390-pixel phone header checks. Reviews found no
material slider/startup issues; the earlier diagnostics restart-counter finding
was corrected. A separate final read-only review found no material issues in
the default-disabled, serialized timing-file path. Raw tests, traces and comparison receipts remain in ignored
`artifacts/brightness-059/`.

## Actual native startup and pairing checks

The clean APK was upgraded with app data preserved and its installed hash
verified. Native captures show the OS audio identity gate selecting BDK SPEAKER,
then **Connect speaker controls**, rather than opening disconnected controls.
A manual search shows the centered speaker name, animated halo, one status line
and Cancel setup. Two actual search-halo captures differ in 116,904 of 159,600
pixels in ROI `(420,1070)–(800,1490)`; 116,708 pixels differ by more than five RGB
levels. The matching BDK speaker controls subsequently appear in the selection
list. This verifies native search and motion, not a new synchronized BLE session.

The phone repeatedly returned to Developer Settings. Foreground guards refused
inputs there, including the final attempted connection check. No new BLE
connection completed in this run. Music playback, live meter timing and codec
negotiations remain unverified; the earlier user report of no audio connection
is superseded by the current OS audio identity evidence.

Android's native launch resources use the existing BDK mark and dark background.
A normal launcher tap was guarded by fresh icon semantics, exact own-brand icon
pixels and the verified package. Its recording shows the BDK launch icon
transition into real setup. The tap script's immediate foreground assertion ran
during the transition and failed; its video and cleanup were preserved, and a
later read verified the correct BDK Activity. Direct shell cold starts did not
capture a sustained splash. Real initialization completed quickly, so a sustained
Flutter branded-loading view was not observed natively; its pending/error/retry
states are covered by widget tests. No artificial startup delay was introduced.
The iOS static launch resources are prepared but have not been compiled on Apple.

Native PNG/XML/video hashes and final package identity are recorded in
`artifacts/brightness-059/capture-manifest.json` and `final-native-receipt.json`.
Only uniquely owned temporary XML/video/APK paths were removed. Other devices,
apps and OS settings were not modified.

## Installed preview and release boundary

Normal `lib/main.dart`, optimized Release AOT, ARM64 split code **2017**, with
`BDK_PREVIEW_ONLY=true`; automatic discovery/connection and speaker-setting writes
remain disabled. APK `artifacts/bdk-audio-preview-0.5.9-release.apk`:

- **20,731,882 bytes**.
- SHA256 `700aae955f1c8e83f39386e83675cb181f216c733fbc146bd74d27ea84fc00f7`.
- Local, staged and installed hashes match; final observed app PID **13285**.
- API 24 minimum / target 36, not debuggable; development Android Debug certificate.

ARMv7/ARM64/x64 packages pass CRC, manifest, expected native ELF architecture,
certificate and eight bundled-notice checks. ARMv7/x64 are package-only checks.
The final app's last verified state is matched speaker controls found, awaiting
connection; the current foreground is the user's Developer Settings screen.
Windows remains at its separate 0.5.8 package checkpoint. Apple builds/devices,
broader native validation, production signing and distribution remain open.
