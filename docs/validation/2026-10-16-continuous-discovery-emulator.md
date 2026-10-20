# Continuous finding and refined search motion — 0.6.4+22

Code checkpoint `dabf9b7ab5c62319d6098be489ac12ecb44b90b2` keeps the original
speaker, grille, angle, drivers, LED bar, wave marks and static rings. Only the
active search painting changes: two diffuse cyan/violet outward pulses over
4.8 seconds replace the rotating wedge and dot. Reduced motion remains static.
The user explicitly clarified that the original illustration must stay.

Foreground automatic discovery now continues until the matching speaker is
found. Five seconds without a match reveals inline **Connected to your speaker?**
help while checking continues, with a **Connect speaker** button that opens OS
Bluetooth settings only on a tap. Cancel and Demo remain accessible. The prior
five-second terminal empty state is superseded; the two-second startup B hold
and 700 ms reveal remain unchanged.

The audio-first/exact-device/service gates remain. Audio polling continues when
no speaker is connected; BLE starts only after the selected audio identity is
verified. Actual continuous native scans no longer expire after 15 seconds.
Matched results retain the initial exposure window and PreviewOnly does not
automatically connect. Background, cancellation, permission/error, connection
and disposal retain cleanup behavior. Scan errors stop native work before a
replacement scan starts. Multiple connected audio choices remain selectable
while OS polling continues.

## Checks

- **580 Flutter tests passed; one optional skip.** Analyzer: no issues, 6.9 s.
- New controller tests first failed on the old terminal behavior. They cover
  continuing after help, polling and later audio connection without retry,
  a native scan beyond 25 seconds, unrelated identities, a later correct peer,
  cancellation/background and permission/query failures.
- Review found two additional P2 issues: inaccessible multiple audio choices
  and scan-stream errors without native cleanup. Both received failing tests,
  fixes, passing focused checks and a clean scoped re-review. Replacement scans
  wait for a deliberately delayed native stop in the regression.
- All 28 pairing UI tests passed, including prompt actions, no automatic settings
  callback, ongoing motion, reduced motion, both themes and 280px/2x text.
- All three Android ABI APKs compiled; manifests/API24→36, ELF, signatures,
  CRC and eight bundled notices checked. Unchanged icon exports verified.

## Native emulator evidence

Only owned AVD `BDK_Animations_API36_20261016`, serial `emulator-5580`, Android36
x64 was used. Normal main, PreviewOnly, diagnostics off; no phone or ESP32
operation. Installed version **0.6.4+22**, code **4022**, PID **11842**:

- APK **22,264,508 bytes**, SHA256
  `b0078fb3e643bf6647834b53e405903b80c8de7e61551a0be93df33130a392b7`.
  Local, staged and installed hashes match; earlier APKs preserved.
- Cold-launch recording: 1080×2400, **993 encoded frames / 23.676089 s**. It
  shows custom B startup, searching, inline connection help and continued soft
  motion rather than a terminal no-device state or automatic settings redirect.
- An eight-second native excerpt has **327 frames / 8.011245 s**. Native early
  and later halo samples changed 417,056 of 800,800 pixels by more than two RGB
  levels in the inspected region. This confirms motion, not an FPS benchmark.
- Fresh native semantics located Connect speaker. Its explicit tap launched
  `com.android.settings/.Settings$ConnectedDeviceDashboardActivity`, the emulator's
  handler for the existing `Settings.ACTION_BLUETOOTH_SETTINGS`. The stable
  screenshot shows Connected devices with Pair new device and Bluetooth settings.
  No radio setting, pairing or peer selection was changed.
- Back returned to the app's checking view without replaying splash; after
  five seconds the inline help returned with ongoing motion. The emulator is
  left in this finding/help state.

The first settings screenshot was captured during the window transition and
still showed the app. It remains preserved but is not settings visual evidence;
use `emulator-bluetooth-settings-stable.png` and its activity receipt. Stable
return captures and the final semantic tree confirm the resumed app state.

Ignored raw evidence: `artifacts/discovery-064/`, including source/package identity,
videos, PNG/XML hashes, explicit tap events and settings/return receipts;
`artifacts/android-0.6.4-all-abi/` contains package receipts. No audio speaker was
connected and no peer/music data injected. Native evidence covers empty OS audio
checking and UI motion/navigation; continuous physical BLE and music/codec
validation remain separate. Phone remains0.6.0; broader release work stays open.
