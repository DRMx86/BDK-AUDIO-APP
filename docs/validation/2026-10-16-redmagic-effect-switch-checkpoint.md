# Redmagic native effect-switch checkpoint — installed 0.5.6

2026-10-16, approximately 22:26:15–22:41:05 UTC (15:26–15:41 America/Los_Angeles).
This is the pre-repair phone result for the shipped normal app, not the later source
repair or a benchmark entrypoint. All **22 named LED choices** were visited.
**20 showed changing native preview artwork; Particle Burst and Meteor Shower did
not.** This checkpoint therefore does not pass all-effect animation.

## Identity and boundary

Authorized Redmagic serial `9125299103B7`, `com.bdkaudio.controller`, activity
`com.bdkaudio.bdk_audio.MainActivity`, installed 0.5.6 / version code 2014,
ARM64 AOT normal `lib/main.dart` PreviewOnly build. The installed base.apk SHA256
was verified before inputs and again after restoration:

`6d625fa98be1a3e7f68d51a0e8b670eab215bef617dc2617507b14ecee9c2a07`.

The app stayed foreground and Not connected, with explicit **Preview · firmware
demo**, brightness **70%**, existing Follow device theme (currently Dark), and
the original colors/blend/speed. No theme, brightness, algorithm, renderer,
clock, or demo-input change was used to make a sample change. No app install,
data clear, BLE scan/connect, music/audio playback, codec/OS/Bluetooth setting,
sound upload/delete, OTA, ESP32 project/serial/flash, other-device action, or
cloud job occurred. The copied native effect classes were not edited by this QA.

## Method and results

Raw evidence is retained locally in ignored `artifacts/redmagic-effects-056/`:
`events.jsonl`, `results.json`, timestamped screenshot receipts, fresh semantics,
first-frame screenshots, gallery-target screenshots, and `capture-manifest.json`.
Each numbered sample prefix below has native `-0.png`, `-1.png`, `-2.png` captures.
IDs/names follow `lib/features/light/light_screen.dart` and the owned native bridge.

Spectrum was already foreground/playing at handoff and was sampled first. This
was **not a cold-launch or startup-latency test**. For IDs 1–20, the gallery was
opened while paused; the exact visible app semantic target was selected, a
forced first frame was captured while paused, and Play preview was activated.
Ambient was selected through the home quick-select chip and opened Ambient colors.
Fresh selected-state semantics, names in captures, and representative gallery/main
screens were inspected. `firstframes-contact.png` preserves the first-frame review.
Representative main/gallery screenshots show diffusion spreading across the card,
readable effect names, and clear gallery selection borders/check marks. No obvious
hard-edged LED square or diagonal seam was visible in those inspected images.
Some patterns start dark or sparse; a dark first frame alone was not a failure.

Captures are 1216×2688. Main artwork ROI is `(200,850)–(1000,1500)`;
Ambient uses `(200,1000)–(1000,1650)` because its back heading moves the card down.
Each ROI contains **520,000 pixels** and excludes title/status/navigation/controls.
Numbers count pixels with any RGB-channel difference relative to capture 0.
The span is the measured first-to-last capture-start interval, including ADB work;
nominal waits of 1 s then 2 s are not an animation FPS measurement.

| ID | Actual selected name | Observation | Changed pixels 1 / 2 vs 0 | Span s | Capture prefix |
|---:|---|---|---:|---:|---|
| 0 | Spectrum Bars | Changed artwork | 155,350 / 143,035 | 4.970 | `00-spectrum-initial` |
| 1 | Beat Pulse | Changed artwork | 520,000 / 520,000 | 7.156 | `01-beat` |
| 2 | Ripple | Changed artwork | 520,000 / 518,388 | 4.368 | `02-ripple` |
| 3 | Fire | Changed artwork | 519,538 / 519,615 | 4.492 | `03-fire` |
| 4 | Plasma | Changed artwork | 519,998 / 520,000 | 4.823 | `04-plasma` |
| 5 | Matrix Rain | Changed artwork | 520,000 / 520,000 | 4.329 | `05-matrix-rain` |
| 6 | VU Meter | Changed artwork | 440,207 / 337,921 | 4.669 | `06-vu-meter` |
| 7 | Starfield | Changed artwork | 489,609 / 465,485 | 4.380 | `07-starfield` |
| 8 | Wave | Changed artwork | 519,855 / 519,995 | 4.715 | `08-wave` |
| 9 | Fireworks | Changed artwork | 520,000 / 519,415 | 4.435 | `09-fireworks` |
| 10 | Rainbow Wave | Changed artwork | 520,000 / 520,000 | 4.707 | `10-rainbow-wave` |
| 11 | Particle Burst | Unchanged Demo; reproduced below | 0 / 0 | 4.454 | `11-particle-burst` |
| 12 | Kaleidoscope | Changed artwork | 520,000 / 520,000 | 4.909 | `12-kaleidoscope` |
| 13 | Frequency Spiral | Changed artwork | 489,988 / 509,776 | 4.452 | `13-frequency-spiral` |
| 14 | Bass Reactor | Changed artwork | 520,000 / 520,000 | 4.577 | `14-bass-reactor` |
| 15 | Meteor Shower | Unchanged Demo; reproduced below | 0 / 0 | 4.215 | `15-meteor-shower` |
| 16 | Breathing | Changed artwork | 520,000 / 520,000 | 4.335 | `16-breathing` |
| 17 | DNA Helix | Changed artwork | 519,947 / 519,354 | 4.831 | `17-dna-helix` |
| 18 | Audio Scope | Changed artwork | 415,260 / 428,049 | 4.477 | `18-audio-scope` |
| 19 | Bouncing Balls | Changed artwork | 502,659 / 517,765 | 4.828 | `19-bouncing-balls` |
| 20 | Lava Lamp | Changed artwork | 509,797 / 520,000 | 5.440 | `20-lava-lamp` |
| 21 | Ambient | Changed artwork | 518,517 / 518,517 | 5.673 | `21-ambient` |

Ambient controls were inspected without changing values: primary `#74D9FF`,
secondary `#BC9AFF`, **Horizontal** blend, brightness 70%. Its changed sample is
consistent with the phase-based Horizontal renderer. Ambient Solid is intentionally
static in the owned source (`renderSolid` ignores phase); Solid was not selected
or tested here. Ambient captures 1 and 2 were identical to each other but differed
from 0, so this finite sample establishes change, not a cadence guarantee.

## Reproduced Demo exceptions

The original short identical pairs are preserved. Each exception was then selected
again through the native gallery, resumed, and sampled longer without changing
brightness, timing, or inputs:

- `11-revisit-0.png` through `-3.png`: four native captures spanning **11.413 s**, changed pixels **0 / 0 / 0** relative to first.
- `15-revisit-0.png` through `-3.png`: four native captures spanning **10.864 s**, changed pixels **0 / 0 / 0** relative to first.

Particle Burst retains a red center glow; Meteor Shower remains dark. These are
reproduced installed-Demo observations, not proof of a global UI renderer freeze
or physical-speaker behavior. The owned source provides a specific causal clue:
`LedEffect::init` sets `m_frame=0`; ParticleBurst `updateDemo` increments it, checks
`%30==0`, then `update` increments it again. MeteorShower does the same with
`%20` bass and `%30` beat triggers. The checked counts are odd and cannot hit
those even divisors. Particle Burst therefore receives no demo burst trigger;
Meteor Shower receives neither the bass hit nor beat needed to spawn a meteor.
See `packages/bdk_led_engine/src/led/led_effects.h` lines 154, 1005, 1060–1066,
1247, 1259, 1303–1309. No native class fix or phone upgrade was part of this run.
Any subsequent root-agent native RED/GREEN or revised APK requires its own receipt.

## Controls, restoration, and limits

Spectrum playing initially changed 155,350 / 143,035 pixels. Its paused sample
was exactly 0 / 0, confirming pause behavior. Play was then exercised for each
selected named effect. Ambient quick-select navigation and current color/blend
controls were inspected. Other quick chips, changing Ambient values, Off/restore,
and exhaustive settings were left untested to respect the roughly 15-minute UI bound.

At 22:41:05 UTC, the unchanged installed APK was left on **Spectrum Bars, 70%,
Follow device, Preview playing, explicit firmware Demo, Not connected**.
`restored-state.xml` confirms selected name/70%/Demo while paused, followed by the
logged Play action. `restored-playing-0.png` through `-2.png` visibly show playing
and changed 126,804 / 133,434 artwork pixels. The final screenshot was inspected.
Only the exact self-created remote `/sdcard/bdk-effect-qa.xml` was removed; native
screenshots were streamed directly without remote PNG files. ADB/app data/logs
were preserved, and phone-input ownership was released after restoration.

A playing-screen UI Automator request failed with `ERROR: could not get idle
state`; no tap was made by that failed semantic request. Subsequent pause taps
required a fresh foreground-guarded native screenshot whose pause-control region
matched the visually inspected app reference, followed by fresh semantics for
selection. An early QA-helper gallery swipe overshot a partially visible Plasma
tile; that navigation attempt was stopped, screenshots/semantics retained, then
Plasma was correctly selected and sampled. Neither tooling event was counted
as an app animation failure.

No BLE/live music, exact physical LED parity, FPS, GPU-presentation, energy,
long-soak, cold-start, other-phone, or all-effects-pass claim follows from this run.
