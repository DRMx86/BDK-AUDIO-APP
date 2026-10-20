# BDK Audio Flutter migration and product redesign

Status: approved for implementation by the user's "Yes, build this design" reply. Date: 2026-10-16.

Latest scope override: the user said "DO not touch anything related to ESP32."
Work is limited to the app and phone. No firmware edits, builds, serial operations
or flashing. Existing STATUS/METER packets feed the phone preview; firmware
extensions previously proposed in this document are cancelled.

## Intent and user requirements

Replace the existing BDK Audio companion with one Flutter product for Android,
iPhone/iPad, Windows, macOS, and Linux. Preserve all implemented speaker controls.
The user's quality target is a companion app better than JBL's, translated here
into measurable usability, responsiveness, truthful device state, and reliability.

Explicit priorities:

- Reduce scrolling and redesign preset browsing.
- Configure codec, sample rate, bitrate, and bit depth inside the app without
  requiring Developer Options wherever the operating system permits this.
- Move received speaker audio meters to the LED page and use the real incoming
  levels to drive the preview like the ESP32's effects.
- Resolve the first-switch LED preview freeze.
- Make Ambient quick-select immediately reveal the same controls as the effect
  dropdown. Brightness remains available for every effect; Ambient additionally
  reveals speed, two colors, and gradient controls.
- Show phone and desktop mockups before product implementation.
- Maintain an active project goal through implementation and validation.
- Preserve the original app's rich visual character; the first layout preview was
  too plain. Use deliberate BDK typography, depth, cyan accents, expressive preset
  cards, and a vibrant LED preview without large decorative areas.
- Do not cram controls onto a page. Target different ages and levels of technical
  confidence with focused screens, readable labels, clear back navigation, and
  accessible touch targets. Extra screen space is not a reason to add more panels.
- Latest EQ direction: the user requested distinctive alternatives to the common
  connected curve. v9 offers tone pillars (recommended default), wells and steps
  in the review toolbar. Fixed bass/mid/treble wire levels remain integer -12..12;
  use generous drag and 48 px step targets, keyboard and accessibility actions.
- LED preview fills its entire card with stronger Gaussian diffusion and blended
  glow, with JBL Pulse 5/PartyBox lighting as visual inspiration. Do not show an
  inset matrix box or the explanatory "Frosted-glass diffusion" caption.
- Latest fidelity feedback: preserve circular geometry and actual firmware effect
  identities. In this firmware Beat Pulse flashes the whole matrix; Ripple and
  Bass Reactor generate circles. The mockup's Beat Pulse ring was incorrect.
  The implementation reuses portable C++ firmware effect logic through FFI; a
  square/aspect-preserving source feeds the full-card diffusion layer.

## Source and environment evidence

Android source: `D:/ESP32 Bluetooth/BDK-AUDIO-APP-main`.
Firmware: `D:/ESP32 Bluetooth/ESP32-A2DP-SINK-WITH-CODECS-UPDATED-main/bt_audio_sink`.
Both supplied roots are extracted source folders without their own Git metadata.
The firmware contains independent ongoing migration/host-design work: do not
overwrite its baselines, SDK, backups, or Bluetooth host implementation.

Fresh ADB evidence: Redmagic 11 Pro/NX809J, serial `9125299103B7`, Android 16/API 36;
`com.example.myspeaker` 1.0 is installed. Another Samsung is also attached; all
phone commands must select the Redmagic serial. The captured system Bluetooth
screen showed BDK SPEAKER BLE connected for media and an LDAC HD-audio option.
This does not prove a particular bitrate or successful codec changes from an app.
The phone UI was changing during investigation; do not assume a stale resumed
activity identifies the currently visible screen or interrupt the user's screen.

Local Flutter 3.44.4/Dart 3.12.2 and Windows C++ build tools are installed.
`flutter doctor -v` reports Android SDK licenses not fully accepted. Resolve the
specific missing license with the user when needed; do not silently accept terms.
Apple builds require a macOS/Xcode runner. Linux builds require a Linux runner.
Neither native platform is validated by an Android or Windows build.

## Feature parity inventory

| Area | Preserve |
| --- | --- |
| Connection | BLE service discovery, Bluetooth permission/state handling, saved devices, selection, reconnect, explicit disconnect, incompatible-device state |
| Sound | Signed bass/mid/treble gains -12..12 dB, existing Android presets and custom slots, bass boost, channel swap, DSP bypass, encoder-driven updates |
| Lighting | All 22 user effects (IDs 0..21), Off through zero brightness, brightness, speed, two colors, five gradient modes, saved Ambient settings |
| Meters | Three incoming normalized level bytes for 30/60/100 Hz, freshness state, correct dB conversion, LED-page placement |
| Custom sounds | Startup, pairing, connected, maximum-volume sound slots; import, local preview, WAV conversion, upload, delete, notification-sound mute |
| Device | Name, firmware version, connection details, app information |
| Firmware | Local firmware import, existing AES-CBC release compatibility, configurable download source, unified BLE OTA and abort, WiFi recovery guidance |
| Codecs | Active codec/capabilities where readable; capability-checked rate/depth/quality preferences; honest failure and verification state |

There is no BLE volume, transport-control, battery telemetry, sleep timer, or TWS
implementation in the inspected command handler. Do not present these as working
features. Switching saved speakers is supported scope; simultaneous controllers,
group playback, and stereo pairing are separate firmware projects.

## Source findings that govern the port

1. The README's command IDs and UUID examples are stale. Use the actual firmware
   and shared protocol: service `12345678-1234-1234-1234-123456789000`, CMD suffix
   `9001`, STATUS `9002`, METER `9003`. Preserve the current wire format.
2. `main.cpp:143` applies bass boost `0x01`, channel flip `0x02`, DSP bypass
   `0x04`. Shared `DeviceModels.kt` reverses flip/bypass and advertises other
   unsupported flags. The Dart protocol must follow firmware behavior.
3. `shared/EqPresets.kt` contains a 0..100 display catalog whose IDs/values differ
   from firmware presets and Android's active redesign. Port the active Android
   UI gains using its existing conversion and send SET_EQ for app-owned presets.
   Keep firmware preset IDs separate and explicit. Store new custom gains in dB.
4. `LedEffectPreviewView.kt:131` returns when the first requested effect matches
   initial ID 0; the animator only starts after a different effect is selected.
   This is a concrete cold-start path defect consistent with the reported freeze,
   not a completed physical reproduction. Detach destroys rendering resources,
   while attach only requests layout. Per-draw RenderScript allocations are a
   performance concern to measure, not an established cause of the user's freeze.
5. Quick-select's `setupLedEffects()` omits
   `updateAmbientControlsVisibility(effectId)`, which dropdown selection calls.
   This directly explains the two selection paths exposing different controls.
6. The existing preview uses internally simulated sine/random audio, independent
   of received meter packets. Incoming meters are normalized 0..100 positions
   mapped from -60..0 dB; the existing UI incorrectly labels the raw bytes dB.
   Decode approximate level as `0.6 * value - 60`, with finite/clamped handling.
   These are three bass-frequency bands, not bass/mid/treble EQ gains or SPL.
7. The LED renderer additionally consumes bass/mid/high values, beat/intensity,
   playback state, time, and effect-specific state/randomness. Existing METER
   packets cannot reproduce every LED frame. Do not claim exact mirroring from
   three bytes. The app reuses the source renderer with estimated reactive input;
   no firmware extension is included in the latest scope.
8. `OtaActivity.kt` reports completion after a timer; status handlers largely log
   OTA responses. Flutter must await OTA_READY, OTA_FAILED, OTA_COMPLETE and
   post-reboot version verification. A successful GATT write is transport-level
   completion, not proof of a committed firmware image.
9. Full status notifications can be split without fragment framing at low MTU.
   Require enough payload capacity for the current full status, or use an
   explicitly negotiated framed extension. Do not guess boundaries or accept
   truncated packets as ready state.
10. The current update downloader has a placeholder Google Drive file ID and an
    embedded AES key. Preserve encrypted-file compatibility as a legacy import
    path; encryption is not firmware authenticity. A hosted production channel
    needs a real manifest/signing policy before being enabled.
11. Additional source tracing confirmed that phone-originated EQ/control changes
    skip BLE cache mutation when suppressing notification echo. LED commands have
    the same cache divergence pattern. Reconnect/status confirmation must address
    this firmware behavior, not overwrite real new settings with stale cache.
12. Existing OTA ignores one-byte raw data, does not use the sequence field for
    receipts, and finalizes with `end(true)`. Sound replacement removes the prior
    file before a successful replacement. These compatibility and reliability
    constraints are specified in `docs/migration/protocol-contract.md`; strong
    transfer guarantees require corresponding firmware changes and native tests.

## Product interaction design

Revised after user feedback: three primary destinations, Sound, Light, Speaker.
Phone uses labeled bottom navigation; tablets/desktop use a navigation rail.
Detailed screens have an obvious labeled title and back button. Maintain the same
information hierarchy on desktop; use columns only for related content in the
current task, not a dashboard of every feature. Keep device identity and connection
state visible, distinguishing BLE control, audio-source connectivity and freshness.

Sound: a compact selected-profile card, four favorite presets in a two-column grid,
and clear entries for Adjust equalizer and Your saved presets. The complete catalog
opens a dedicated Sound presets screen. The equalizer has its own focused screen
with tactile tone pillars, Reset and Save preset. The three fixed source filters
are a 150 Hz low shelf, 1 kHz peak and 6 kHz high shelf. Integer wire levels -12..12
are scaled by 0.5 / 0.7 / 0.7 in the DSP; do not label wire levels as applied dB or
show a fabricated measured response. Alternative wells/steps styles are available
for comparison outside product navigation. Store actual wire values in profiles.

Sound options has Full-range stereo versus Split output, bass boost, and low/high
output swap. Full-range bypasses crossover, while EQ and bass boost remain active.
Swap has no effect in full-range mode; disable its control and preserve its bit.
A selected preset follows actual values, including physical encoder changes.

Light: one clear 16x16 preview, brightness, a Choose an effect entry, and three
favorite-effect shortcuts. The full 22-effect gallery is a dedicated screen.
Audio activity is a clearly labeled optional disclosure beneath the main controls.
Ambient selected through either favorites or the gallery opens the same focused
Ambient colors screen, with preview, brightness, two colors, blend and speed.
Returning shows the selected effect and a Customize Ambient entry. Same-effect
selection remains idempotent while the visible preview continues. Off preserves
brightness for restoration. Keep animated effect character without decorative blur
over controls. The requested diffusion covers the whole preview card, including
behind its overlays, rather than a small inset square. Use Gaussian diffusion and
a broad glow. Follow the later user refinements: the effect name is plain
text in the upper-left corner without a dark label background or sample-input
badge. A gradient and text shadow keep it readable. In the current native design,
the compact pause/play icon and Preview label sit in the page heading; source status sits above the light
card. Remove the diffusion explanation from the product UI. The mockup uses 12 px base Gaussian
blur and 25 px bloom, with the light field expanded across its display cells. These
are appearance choices, not calibrated optical or hardware measurements. Bound
Flutter blur painting to this preview and profile it on the actual phone. Use
real telemetry in the product; the mockup uses explicit samples.

Audio quality is a dedicated detail screen reached through Speaker. Show active
connection at the top, separate requested preferences beneath, and supported
combinations only. Codec-specific quality/bitrate controls replace an arbitrary
numeric bitrate field. Apply shows pending, then confirmed, refused, or timed out.
Never show Applied just because a setter returned.

Speaker: simple labeled rows for Audio quality, Speaker sounds, name, firmware,
appearance and information. Custom sounds get their own slot list and import flow.
Provide dark/light/system themes, scalable text, keyboard navigation, screen-reader
labels, adequate touch targets and reduced motion. Main actions must use words;
icons and color supplement labels. The redesigned visuals retain cyan/dark BDK
character with stronger typography and restrained gradients on selected content.

The revised full product mockup is `bdk-product-design-v9.html` in the active
brainstorm content directory; it supersedes the initial host-styled layout preview.
The interactive mockup uses sample values and simplified effect drawings. It
validates layout and interactions only; it is not the Flutter app or evidence of
device capability, firmware frame equivalence, or successful Bluetooth traffic.

## Implementation decisions proposed by the assistant

- Create `D:/ESP32 Bluetooth/BDK-Audio-Flutter` as a separate product workspace;
  preserve the original apps and installed Android application for comparison.
  Initial Android package ID `com.bdkaudio.controller` permits side-by-side testing.
- Flutter shared presentation and application state; pure Dart models, packet
  encoders/decoders, preset storage and transfer state machines. Reuse the original
  C++ effect classes unchanged through FFI with a memory-backed LED driver.
  Current state uses controlled widgets/ValueNotifier; keep protocol independent.
- Use `universal_ble` behind a transport interface, pin a verified compatible
  version after a local Android/Windows connection spike. Its published client
  platform list covers all requested native targets, with platform limitations.
- A single connection/session owner serializes GATT operations and owns
  subscriptions. Queue slider writes with latest-value coalescing and a guaranteed
  final write; do not accumulate stale slider positions. Keep a session generation
  token to reject callbacks from old connections. Reconnect uses bounded backoff.
- Await notification setup before status requests. Ready requires valid state,
  not merely a connected socket. Parsers reject malformed data and preserve prior
  confirmed state. Transfers are exclusive with other writes and cancel on loss.
- Android native codec adapter via a Flutter platform channel reuses the current
  CDM association concept and codec-specific mappings. AOSP permits associated
  companion callers in the service but the framework methods remain system APIs.
  OEM/API restrictions require direct Redmagic validation and a clear unsupported
  state. ADB is a development tool, not a runtime dependency or an app bypass.
- iOS/iPadOS/macOS/Windows must not promise arbitrary A2DP codec control. Expose
  available telemetry and OS-managed state unless a supported adapter is proven.
  Linux may add a BlueZ/PipeWire adapter after native capability verification.
  PCM format, Bluetooth codec bit depth, and observed encoder bitrate are distinct.
- Port the ESP32 LED algorithms rather than keep the Android decorative blur.
  Baseline uses actual received meter data and is labeled reactive preview.
  Reconstruct bounded audio/AGC/beat estimates from those existing bytes only.
  Display their positive 0–100% scale with a zero baseline; source labels are
  30/60/100 Hz. Do not sample the phone microphone or synthesize live input.
- Reuse the 22 source effect algorithms unchanged and verify their identities and
  geometry. Existing packets omit exact DSP history and random state, so physical
  frame parity remains unverified and is not promised. Stale/missing input becomes
  silence. Explicit Demo uses the source demo input.
- No new BLE telemetry, firmware prerequisites, edits or deployment in this scope.
  Do not change the separate Bluetooth host migration.
- Cross-platform sound import starts with PCM WAV validation and conversion to
  mono 16-bit WAV. Preserve the current bounded-size compatibility path (200 KiB,
  preferred 22.05 kHz, fallback lower rates); report trimming rather than silently
  cutting the user's audio. Reuse Android/iOS native decoders through adapters and
  choose a maintainable licensed desktop decoder; never quietly drop sound upload.
- OTA uses actual negotiated write capacity and firmware responses, byte counts,
  finite deadlines, explicit abort, and reboot/version verification. Existing
  firmware does not provide resumable/idempotent OTA chunk receipts; do not
  promise resume or blindly retransmit uncertain chunks. Signing/hosted releases
  remain disabled until a trusted release source and firmware policy are supplied.

## Build sequence and acceptance

1. Approve this design and mockup direction; write a concrete implementation plan.
2. Implement packet/state tests and BLE session, then real Android/Windows discovery,
   status sync, EQ, LED controls. Confirm coexistence with A2DP before proceeding.
3. Implement responsive UI, preset parity/persistence, encoder sync, and both LED
   selection fixes. Verify cold launch, first Light visit, repeated effect changes,
   Ambient from every selector, Off/restore, background/resume, and reconnect.
4. Validate Android codec read/apply on Redmagic without Developer Options. Compare
   the requested and negotiated codec/rate/depth/quality after each change. Refused
   configurations must not change the displayed active state. Record limitations.
5. Implement custom sounds and verified BLE OTA with fixture/failure-path tests.
   App installation is authorized for this project; firmware flashing requires
   identity-checked, explicitly approved deployment and a recovery path.
6. Verify the app preview with existing meter data while streaming.
   Check frame stalling, timely control writes, and audible
   playback dropouts under matched baseline/candidate workloads. Report timings,
   CPU/memory/traffic, and remaining unknowns rather than invented performance.
7. Build/package Android and Windows. Use macOS and Linux runners for native builds;
   perform BLE/transfer/renderer QA on actual iPhone/iPad, Mac and Linux hardware
   before marking those targets release validated. CI compilation alone is not
   physical Bluetooth validation. Configure signing/distribution with real keys.

Each platform is tracked separately: source prepared, compiled, installed,
hardware verified, release packaged. The goal is complete only when the agreed
platform and feature acceptance gates are met; no current completion claim.

## Decisions left to the builder

Exact Flutter dependency versions, folder organization, storage schema, names and
colors beyond the accepted mockup direction, desktop decoder selection,
test harnesses, and build scripts may be settled during planning.
Do not expand into account systems, cloud sync, a music service, or unsupported
speaker capabilities. User branding and release identities can replace initial
development identifiers without blocking a functional build.

## Reference sources checked in this investigation

- [Flutter deployment platforms](https://docs.flutter.dev/reference/supported-platforms)
- [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup)
- [Universal BLE platform/API matrix and license](https://pub.dev/packages/universal_ble)
- [AOSP BluetoothA2dp API and CDM association checks](https://android.googlesource.com/platform/packages/modules/Bluetooth/+/refs/heads/main/framework/java/android/bluetooth/BluetoothA2dp.java)
- [AOSP A2dpService caller enforcement](https://android.googlesource.com/platform/packages/modules/Bluetooth/+/refs/heads/main/android/app/src/com/android/bluetooth/a2dp/A2dpService.java)
- [Android non-SDK interface restrictions](https://developer.android.com/guide/app-compatibility/restrictions-non-sdk-interfaces)
- [Apple A2DP audio-session routing](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetootha2dp)
- [JBL Pulse 5 lighting reference](https://www.jbl.com/on/demandware.static/-/Sites-masterCatalog_Harman/default/dw674a105f/pdfs/JBL%20Pulse%205_Specsheet_EN.pdf)
- [JBL PartyBox Encore lighting reference](https://www.jbl.com/PARTYBOX-ENCORE-.html)

Local evidence is under `docs/migration/evidence`. No product source or firmware
was changed during the source/design investigation.

The current wire reference is `docs/migration/protocol-contract.md`, with 35
source-derived examples in `docs/migration/protocol-vectors.json`. Example byte
lengths and full-status string offsets were checked; nine firmware source hashes
still matched the recorded snapshot. This validates the reference data only,
not a Flutter encoder/parser or live peripheral behavior.

## Design verification and handoff

- The brainstorming builder check returned "nothing important left".
- The check was repeated after the user's visual-density and age-group feedback;
  it again returned "nothing important left". The revised design has three main
  destinations and dedicated detail screens. The original four-tab inline concept
  is retained only as an earlier layout exploration.
- Revised v4 browser checks: Sound main content fits the 420x868 phone preview
  without internal scrolling; selecting Deep Bass and opening Equalizer shows
  +8 dB bass; naming/saving a preset produces the saved entry. LED power Off sets
  brightness to 0 and On restores 70. Ambient quick-select and gallery selection
  both expose the same brightness/color/speed controls. The codec screen shows
  the correct 44.1 kHz LDAC bitrate family and disables apply without access.
- The mockup does not measure usability across age groups. Real text-scaling,
  screen-reader, touch, and task-success checks remain product acceptance work.
- Latest v7 checks: the Equalizer screen has no individual range inputs; pointer
  drag, keyboard control, preset saving and Reset work. Nodes have equal horizontal
  gaps at 320/430/1024 viewport widths, 14 px visible circles and 44 px hit targets,
  with no document overflow. The light field covers its whole card inside the
  border, the removed caption has zero visible matches, and both Gaussian layers
  are active. Off clears all source alpha and restoring power restores brightness.
  Ambient controls remain accessible. These are browser mockup checks only.
- Emulated mobile touch also moved a gain point to +6 dB and Reset returned all
  three bands to +0 dB after the browser delivered the tap. This is browser input
  validation, not a physical Redmagic/Flutter test.
- Mockup interactions were exercised in installed Chrome: Deep Bass selected
  +8/-1/-2 dB, saving produced a selectable custom preset, Ambient quick-select
  revealed its controls, LDAC at 44.1 kHz showed the 909/606/303 kb/s family,
  simulated apply updated current state, and the iOS sample disabled apply.
- Final fragment: 26 KB; no full-document markup or escaped-markup corruption.
- Light/dark screenshots were rendered and inspected. Canvas colors are resolved
  from theme tokens before drawing. Corrected version has no captured JavaScript
  errors. Responsive checks at 320/430/768/1024 outer widths found no horizontal
  document overflow; smaller phones still use ordinary vertical scrolling.
- These checks apply only to the mockup. No Flutter build, native codec setter,
  physical LED reproduction, sound upload, OTA, or cross-platform hardware gate
  has passed yet. The project goal remains active, awaiting user design review.

## Implementation checkpoint update

User approved implementation. Separate Flutter repository now exists at
D:/ESP32 Bluetooth/BDK-Audio-Flutter. The v9 browser preview and native Flutter
Light screen put play/pause beside the heading, with no dark overlay on artwork.
All 22 preview algorithms run the original C++ effect classes, not guessed browser
animations. Browser audio is simulated; native preview is the firmware demo path.
Three legacy meter bytes cannot reconstruct exact AGC, beat and random state.
The current app estimates reactive inputs from them; exact physical mirroring is
not claimed and firmware extensions are outside the latest user-approved scope.
Android development build is installed on the verified Redmagic. Android arm64 and
Windows x64 builds compile. This is not completion of the production migration;
codec, audio/OTA app features and other target validation remain.
Current evidence and release gates: BDK-Audio-Flutter/docs/validation/
2026-10-16-development-checkpoint.md. Earlier v7 checks below are historical.
