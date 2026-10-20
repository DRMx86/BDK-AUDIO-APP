# Redmagic native Demo repair checkpoint — installed 0.5.7

2026-10-16, approximately 22:44–22:48:21 UTC (15:44–15:48 America/Los_Angeles).
Targeted post-repair verification of the normal shipped AOT app: **Particle Burst
and Meteor Shower both animate, pause, and resume on the authorized Redmagic**.
The two previously unchanged main Demo previews pass this bounded native check.
The inspected static Meteor Shower gallery thumbnail remains dark; that separate
visual limitation is preserved below.

## Identity and scope

Serial `9125299103B7`, package `com.bdkaudio.controller`, activity
`com.bdkaudio.bdk_audio.MainActivity`, PID **22556**, installed **0.5.7 / code 2015**,
ARM64 AOT normal `lib/main.dart` PreviewOnly build. The authorized APK is
**20,729,274 bytes**, with installed base.apk SHA256 verified before inputs and
again after restoration:

`b35c2040abaece68da9abbcfb4843f48773b30199fc5c44787716a15efc5c2da`.

The root build includes app-owned native bridge repair `975641e`: only Demo input
for effect IDs 11/15 is corrected; copied effect algorithms remain unchanged. Build,
native RED/GREEN, and source-review receipts are separate from this phone result.
The [0.5.6 native baseline](2026-10-16-redmagic-effect-switch-checkpoint.md) and
its raw evidence were left intact. This targeted 0.5.7 run did not repeat all 22
effects or validate live speaker input.

Fresh observation found the app's own setup page foreground and unlocked. The
local **Explore Demo** control opened the app; the Light tab then showed
Spectrum Bars 70%, Not connected, explicit **Preview · firmware demo**. No Bluetooth
or OS settings control was activated. No app install/source edit/data erase,
BLE scan/connect, audio playback, sound/OTA write, ESP32/serial/flash action,
other-device action, or cloud job occurred during this QA.

## Native captures and controls

Raw receipts are retained in ignored `artifacts/redmagic-effects-057/`:
`events.jsonl`, `results.json`, initial/final identity JSON, fresh app semantics,
gallery captures, paused first frames, native screenshot series, tooling notes,
and `capture-manifest.json`. Capture prefixes below have numbered native PNGs.

For each named effect, fresh exact app semantics selected its gallery tile while
paused. A forced initial frame and selected-state semantics were captured; Play
then activated the preview. Initial, extended, paused, and resumed sequences were
recorded. The observed first frame may be sparse/dark before a Demo trigger;
that alone was not treated as a freeze. Fresh foreground checks guarded inputs.
Pause inputs also required a freshly captured app-control region matching the
visually inspected Pause reference; subsequent selection used fresh semantics.

All native screenshots are 1216×2688. Artwork ROI `(200,850)–(1000,1500)` contains
**520,000 pixels**, excluding title/status/navigation/controls. Values count
pixels with any RGB-channel difference relative to capture 0. All **9 sample
records** were independently recomputed from PNGs with **zero mismatches**.
Spans measure first-to-last capture-start timestamps, including ADB overhead;
they are not FPS measurements or a comparison of exact random RGB between builds.

| Native sample prefix | Captures | Changed pixels vs first | Span s |
|---|---:|---:|---:|
| `11-particle-burst` | 3 | 496,911 / 520,000 | 4.274 |
| `11-particle-burst-extended` | 4 | 520,000 / 520,000 / 520,000 | 8.553 |
| `11-particle-burst-paused` | 3 | 0 / 0 | 4.691 |
| `11-particle-burst-resumed` | 3 | 520,000 / 520,000 | 4.503 |
| `15-meteor-shower` | 3 | 171,117 / 281,746 | 4.318 |
| `15-meteor-shower-extended` | 4 | 304,248 / 456,564 / 479,978 | 7.980 |
| `15-meteor-shower-paused` | 3 | 0 / 0 | 4.320 |
| `15-meteor-shower-resumed` | 3 | 235,098 / 383,300 | 4.343 |
| `restored-playing` | 3 | 200,361 / 213,780 | 4.490 |

Particle Burst visibly changes color and particle/glow arrangement. Meteor Shower
visibly develops colored trails that shift across the card; extended frames 1/2
show different positions. Both main previews retain diffusion across the card,
without an obvious hard square or diagonal seam in the inspected captures.
Both paused sequences are exactly 0 / 0; their resumed sequences change again.

## Gallery observation

`11-selected-thumbnail-gallery-selected-target.png` shows the complete selected
Particle Burst tile: correct name/symbol, readable selection border/check, and
colored native thumbnail glow spreading across the card.

`15-selected-thumbnail-gallery-selected-target.png` shows the complete selected
Meteor Shower tile with correct name/symbol/border/check, but its static native
thumbnail is dark. This is a preserved gallery visual limitation. Its main
preview's captured animation pass does not establish a useful gallery thumbnail,
and the dark gallery capture was not relabeled as a main renderer freeze.
The initial partial Particle tile capture is retained; complete-tile inspection
was performed afterward before counting the gallery review.

## Restoration and limits

At **22:48:21 UTC**, the unchanged installed 0.5.7 app was left on **Spectrum Bars,
70%, Follow device (visible Dark), Preview playing, explicit firmware Demo,
Not connected**. Theme/colors/blend/speed were untouched. `restored-state.xml`
confirms Spectrum/70%/Demo while paused; the logged Play action and final native
screenshots show playing. Restored artwork changes **200,361 / 213,780 pixels**.
The final screenshot was visually inspected. `final-identity.json` freshly
records 0.5.7/code 2015, the exact APK hash, PID 22556, and own foreground activity.
Phone-input ownership was then released; this QA took roughly 4 minutes.

Only the exact self-created `/sdcard/bdk-effect-qa.xml` was removed. Native PNGs
were streamed directly. The root's `/data/local/tmp/bdk-audio-preview-057.apk`,
ADB server, logs, and app data were left intact. A local final-event logger raised
a duplicate-timestamp-key error after the identity file and screenshots had
already been saved; its ignored helper was corrected and the saved identity was
appended locally without further ADB calls. The tooling error is retained in
`qa-tooling-observations.json` and does not change the native observations.

This finite targeted pass does not establish physical LED parity, live BLE/audio,
FPS, GPU presentation, energy, cold-start timing, long-soak reliability, other
devices, or an all 22-effects rerun of 0.5.7. The initial cold launch performed by
the root is a separate receipt; this QA began from the app's visible setup page.
