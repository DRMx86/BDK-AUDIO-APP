# Release assets checkpoint

Development preview 0.5.5. The full migration/production goal remains active.

## Implemented and verified

The app uses the original Android speaker/ring/waves vector geometry in its
dark/cyan launcher exports and App info. Supplied source files are unchanged;
SVG provenance records their exact source hash. Android has adaptive and legacy
round icons, iOS/macOS have every declared PNG size, Windows has seven ICO frames,
and Linux has a bundle icon and per-user launcher registration script.

Deterministic generator `--check` passed. All 29 Apple manifest entries match
their PNG dimensions; every iOS export has no alpha channel. Large artwork and
Android adaptive foregrounds were visually inspected. Actual Android and Windows
App info display the artwork. Apple native builds are still unverified.

App info opens a readable license page independently of package metadata.
Existing generated dependency notices are supplemented by eight unchanged or
explicitly identified font/native notice assets. The Manrope OFL's original 2018
copyright and the bundled binary's exact 2019 copyright metadata are both retained;
neither original statement was rewritten. miniaudio, Unicode, scrypt, C++/WinRT
and Windows Implementation Library texts are included. The LED package's literal
TODO was replaced with an accurate unresolved-rights notice granting no rights.
This does not resolve publisher/source authorization or final release review.

The actual Android Debug/AOT APKs and Windows bundle contain all eight notices
byte-identical to source. Generated LED notices contain the updated status and
no scaffold TODO. The full hosted/package audit is a separate evidence document;
this is not a complete Gradle/Pods/system-library licensing clearance.

## Tests and review

- Analyzer clean; Flutter suite **519 passed**, one optional capture skipped.
- Two new App info tests exercise actual bundled notices, including metadata
  failure and 320px/2x text. The missing row failed before implementation.
- Fresh independent review found one Important/P2 issue: a bare Linux desktop
  executable name could not locate a normal extracted bundle outside PATH.
- Real Linux GLib rejected the original entry before the fix. Four native Python
  tests now launch the exact registered executable, including bundle relocation,
  spaces/quotes/dollar/backtick/percent/backslash paths, and preservation of an
  existing launcher when the executable is missing. Registration uses absolute
  executable/icon paths, no shell evaluation, and per-user XDG location only.
- GLib checks its first executable before expanding literal percent codes. A
  fixed `/usr/bin/env` executable plus one escaped absolute target argument passes
  the native launch checks. Paths containing equality/control characters are
  refused before writes. No re-review is claimed.

## Native artifacts

Android ARM64, `lib/main.dart`, `BDK_PREVIEW_ONLY=true`, version 0.5.5 / code 2013:

| Artifact | Bytes | SHA256 |
|---|---:|---|
| `artifacts/bdk-audio-preview-0.5.5-release.apk` | 20,712,890 | `a549b0493ce339fe5f90ab8f6d47243f5f59c0d0275205d6488023fa7521bb68` |
| `artifacts/bdk-audio-design-preview-0.5.5.apk` (Debug) | 90,492,768 | `ead4f415072348fde16541d44635c08985831d2a656686b3614ab06442d99c0b` |
| `artifacts/bdk-windows-design-preview-0.5.5.zip` (Debug) | 46,072,921 | `19fccd965ac414e75b68512c36811dcd297a6e4ced5b2968d5c9115241aa6496` |

Both Android configurations compiled. The final installed Redmagic package is
the optimized AOT artifact, using the existing development debug signature.
Local, transferred and installed base.apk SHA256 values match. No data was erased
and `com.example.myspeaker` remains installed. The exact manifest activity is
`com.bdkaudio.bdk_audio.MainActivity`; an initial shorthand launch was rejected
and corrected using the actual aapt manifest output.

One cold-launch observation was 1130 ms for Debug and 220 ms for AOT; these are finite
observations, not a performance distribution. Debug transfer took 127.872 s; AOT
transfer took 0.854 s. These receipts do not isolate transfer-rate causes.

Native Redmagic setup remains audio-first; Demo was explicitly selected. App info
shows 0.5.5/2013 and the real bundled Manrope license was opened and inspected in
the AOT app. Windows native App info shows 0.5.5/13 and its settled icon/notices
were inspected. The Windows archive includes all 29 bundle files with matching
bytes. An initial transient capture preceded asynchronous image decoding; the
settled native capture confirms the icon renders.

## Calls and remaining limits

License registration is lazy/idempotent from App info, which owns the only
license navigation. A future independent entry point must call the registration
helper. Tests stay in the existing App info test file to exercise the public
route, with packaged byte checks covering asset delivery.

The isolated local Linux runner has passed SSH/isolation/prerequisite gates.
The 307-file allowlisted app snapshot excludes Git metadata, build outputs,
caches, artifacts and credentials; archive SHA256 is
`68afde65a044548aec0497b83d63b3192c18460660f30d69bbfd93c2ee363b95`.
Application compilation/runtime in that guest remains a separate pending gate.

The phone was left on Spectrum Bars at 70% in explicitly selected Demo. Exact
self-created remote APK/capture files were removed. The tested Windows app was
closed; other apps, previous sessions and physical device settings were preserved.

Live music/meter/codec behavior remains pending the user's audio readiness.
No ESP32 source access/change/build, COM operation, flashing, physical speaker
control/sound/OTA write, Bluetooth/audio setting change or cloud source upload
was performed. Source rights, publisher identity, signing/distribution, Apple
native execution and target-native Bluetooth remain open in the platform matrix.
