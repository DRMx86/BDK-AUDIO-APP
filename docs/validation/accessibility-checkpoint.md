# Light and tone accessibility checkpoint

Date: 2026-10-16. Audited baseline: `ea8f7d019d4a15730048b1e6c000b5f791d48a6c`.
This is the scoped widget/accessibility portion of Task 10. It does not complete
native accessibility or the platform release gates.

## Demonstrated failures and fixes

The new tests ran against the original controls before these fixes. After test
harness corrections, the initial result was six passing layout/target checks and
three product failures:

| User-facing contract | Observed failure | Narrow fix |
| --- | --- | --- |
| Know which RGB channel an adjustable value changes | The Red slider's accessible label was empty | Merge each visible channel name into its slider semantics |
| Identify the active effect in the gallery | Spectrum Bars lacked selected state | Add selected semantics to each gallery tile |
| Recognize and focus the custom tone adjustment control | The pillar lacked a slider role | Declare the slider role and current input-focus state |

A subsequent check also failed because the tone node exposed no
`SemanticsAction.focus`: its inner `Focus` sits under `ExcludeSemantics`.
The public semantics node now forwards an assistive input-focus request to the
same `FocusNode` used by pointer and keyboard interaction. The regression check
requests Mid focus after Bass was focused and confirms the next arrow key changes
Mid only. All production fixes had observed failing tests before implementation.

The fixes add accessibility metadata and focus forwarding. They preserve the
existing pillar drawing, full light card, quiet preview control, named vector
effect gallery, and focused page navigation.

## Fresh verification

Executed from `D:/ESP32 Bluetooth/BDK-Audio-Flutter`:

```powershell
flutter test --no-pub test/ui/accessibility_controls_test.dart test/ui/tone_controls_test.dart --reporter expanded
dart analyze lib/features/light/light_screen.dart lib/features/sound/widgets/tone_controls.dart test/ui/accessibility_controls_test.dart
git diff --check
```

Results: **28/28 tests passed** (11 new accessibility checks and 17 existing tone
checks); scoped analysis reported **No issues found**; diff whitespace check
passed. The whole application suite and platform builds remain the integrating
agent's separate checks.

The new checks exercise real widgets and their returned settings. Only the
renderer boundary uses blank RGBA frames; no native library, Bluetooth session,
audio route, or speaker is required. The fixture supplies no telemetry and is
not evidence of connected music or live effects.

Coverage:

- Red, Green and Blue semantic increment actions each change one channel; the
  committed primary color changes from `65D9F4` to `66DAF5`, preserving secondary
  color and brightness.
- Gallery selected state moves from Spectrum Bars to Ripple after semantic
  activation. Ripple is also reachable through Tab and selectable with Enter.
- Brightness and Movement speed expose names/percent values and support semantic
  adjustment and keyboard arrows after Tab traversal.
- Tone pillars expose slider/focus semantics, increment/decrement actions and
  bounded endpoint actions. Tab and assistive input-focus requests route arrow
  keys to the intended band. Existing tone tests also cover Home/End, Page Up,
  clamping, drag, all three visual styles and 280px/2x text.
- At 600x800/1x, 320x800/1x and 320x800/2x, Flutter's
  `androidTapTargetGuideline` (48x48 logical pixels) and
  `labeledTapTargetGuideline` pass for the visited Light, Ambient, color-dialog
  and tone controls. The gallery audit scrolls to all 22 tiles before checking
  their targets and names. Every tone band is scrolled into view and its named
  increase button is activated, with resulting levels `[1, 1, 1]`.
- These viewport traversals report no Flutter layout exceptions.

The guideline definitions were checked in the installed official Flutter SDK:
`C:/Users/ngocv/dev/flutter/packages/flutter_test/lib/src/accessibility.dart`.
The distinction between accessibility focus and requested input focus follows
`SemanticsProperties.onFocus` in
`C:/Users/ngocv/dev/flutter/packages/flutter/lib/src/semantics/semantics.dart`.

## Remaining native evidence

TalkBack, VoiceOver and desktop screen-reader availability and behavior are
**unverified**. Widget semantics and injected semantic actions do not establish
spoken output, native traversal order, touch exploration, OS accessibility
integration, real keyboard behavior or usability with a screen reader. Native
checks must inspect those behaviors on each target platform, including the RGB
dialog and selected effect announcement. Contrast and rendered screenshot review
were not part of this scoped checkpoint.

No ADB/device actions, native builds, OS/audio operations, firmware changes,
serial access, BLE commands or flashing were performed for this audit. The
original Android and ESP32 sources were not modified.

## Native integration follow-up

The integrating agent installed 0.5.2 on Redmagic and inspected actual Android
accessibility nodes. Bass/Mid/Treble expose focusable `android.widget.SeekBar`
roles with their frequency and level labels. The RGB dialog exposes three
focusable SeekBars labeled Red, Green and Blue with values. Gallery selection
moved natively from Spectrum Bars to Ripple (`selected=true` moved with it).

Windows 0.5.2 exposes the three tone controls as UI Automation sliders. Focusing
Bass and pressing Up changed its value from 0 to +1 while Mid/Treble stayed 0;
Down restored 0. These are native bridge/keyboard checks, not spoken screen-reader
verification. The TalkBack package is present on the phone, but it was not
enabled or used. No accessibility/system settings were changed.
