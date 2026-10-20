# Native platform and release gates

The project is a development preview. A Flutter target, compiled bundle and
working physical Bluetooth integration are separate milestones. The current
user scope excludes all ESP32 source changes, builds, serial access and hardware
writes through the earlier graphics-only checkpoint. The later 0.7.2 Android
completion request authorizes normal app controls and reversible phone codec
tests; it still excludes firmware/serial work and physical OTA/sound-transfer QA.
Earlier installed previews use `BDK_PREVIEW_ONLY=true`; the 0.7.2 ARM64 internal
build uses the normal main entrypoint with that restriction false.

The current Android functional checkpoint is documented in the
[0.7.2 delivery receipt](validation/2026-10-20-android-delivery.md).
The earlier Android LED checkpoint is documented in the
[phone GPU receipt](validation/2026-10-16-phone-gpu-diffusion.md):
0.6.8 was installed on the graphics-only authorized Redmagic and owned hardware
emulator. Native phone appearance and emulator GPU conformance are separate from
physical BLE and the Windows emulator's rescaled presentation limitation.

| Target | Native evidence | Audio identity gate | Remaining release evidence |
|---|---|---|---|
| Android ARM64 | Normal 0.7.2 installed on Redmagic; all-tab config strip; LHDC V5 API 900-kbps target and restoration checked; all four LDAC modes confirmed through app UI at 96 kHz / 32-bit | OS A2DP identity and same-device synchronized BLE; Demo remains isolated | Broad Android/OEM/permissions; real-music/latency/performance characterization; physical sound/OTA QA; signed distribution |
| Android ARMv7 | Optimized0.6.8 preview APK; manifest, ELF, signature, CRC, both shaders and bundled notices verified | Same Android app gate; package evidence only | Target-device runtime, permissions, BLE/audio and decoder checks |
| Android x64 | Owned Android36 emulator0.6.8 installed; NVIDIA hardware OpenGL/Impeller Float32 probe and production GPU Spectrum pass; prior discovery/autoplay retained | Real empty OS audio query; no physical speaker/peer injected | Windows rescaled presentation; physical BLE/audio and decoder coverage; broad OS/permissions; signed distribution |
| Windows x64 | Prior Debug GUI/import and0.5.6 AOT setup semantics; complete0.5.8 AOT bundle verified, unchanged LED DLL has12CABI passes; Release UI incomplete | Read-only OS endpoint/container + AudioSink-service address + connected Classic device; fail closed if incomplete | Release GUI QA; physical connected sink/MAC mapping, BLE session, driver matrix, signed installer |
| iPhone/iPad | Target shells, orientation and Bluetooth usage description prepared | Explicit OS audio confirmation; no verified native same-device identity adapter yet | Native build, signing, real iPhone/iPad, BLE/background/permission/file and decoder tests |
| macOS | Target, sandbox/file/Bluetooth entitlements and app name prepared | Explicit OS audio confirmation; no verified native identity adapter yet | Native build, Intel/Apple Silicon, file access scope, decoder, BLE, signing/notarization and distribution |
| Linux x64 | Ubuntu24/0.5.6 native Demo/Light/gallery/import pass; Jammy22/0.5.6 builds with lower ELF requirements, GUI interaction unverified | Explicit OS audio confirmation; public BlueZ/PipeWire setup state is insufficient for general automatic verification | Current0.5.8 bundle/gallery; Jammy interaction/renderers; physical BLE/audio; architecture/driver coverage; AOT release |

The earlier Windows probe on this host found no connected Classic Bluetooth device. That
verifies the empty-state/exclusion path only; it cannot establish physical sink
mapping. The Redmagic's current OS audio identity and matching BDK controls were
found during 0.5.9 QA. The new BLE session and music playback were not verified;
foreground guards stopped input when the phone returned to Developer Settings.
LDAC quality exposes source-backed preferences and derived nominal targets, never
claims measured bitrate. The 0.7.2 checkpoint additionally supports positively
identified LHDC V5 tuples; unknown vendor mappings remain unavailable.

## Reproducible preview builds

Use Flutter 3.44.4, Dart 3.12.2, SDK revision
`ad70ec4617166f1c38e5d2bfd388af71fda14f06` and committed `pubspec.lock`.
Run `flutter pub get --enforce-lockfile`, `flutter analyze --no-pub` and
`flutter test --no-pub` before packaging. Android uses NDK28.2.13676358.

On the configured Windows development host:

```powershell
flutter build apk --release --no-pub --split-per-abi --target-platform android-arm,android-arm64,android-x64 -t lib/main.dart --dart-define=BDK_PREVIEW_ONLY=true
flutter build windows --debug --no-pub --dart-define=BDK_PREVIEW_ONLY=true
flutter build windows --release --no-pub -t lib/main.dart --dart-define=BDK_PREVIEW_ONLY=true
```

Keep the whole Windows bundle with its DLLs/data. The Android ARM64 split uses
Flutter's ABI version-code offset; 0.6.0+18 becomes 2018. Do not uninstall or erase
app data to bypass a downgrade. The Android Release configuration still uses a
development debug signature; optimization does not make it a signed production
release. The installed 0.6.0 ARM64 AOT preview is 20,696,482 bytes. Windows also has
a complete AOT Release preview; its native UI check remains incomplete after
desktop activation failure. The current Ubuntu guest bundle remains Debug.
These modes do not establish release signing; see the separate
[Windows AOT checkpoint](validation/2026-10-16-windows-aot-checkpoint.md) and
[Demo repair receipt](validation/2026-10-16-demo-trigger-repair.md) and
[gallery/native package checkpoint](validation/2026-10-16-gallery-exposure-checkpoint.md)
and [brightness/startup receipt](validation/2026-10-16-brightness-startup-checkpoint.md).
The [current visible startup, pairing and icon receipt](validation/2026-10-16-visible-startup-pairing-icon.md)
records the subsequent native 0.6.0 verification and intentional brief brand intro.

On native Linux:

```sh
flutter build linux --debug --no-pub --dart-define=BDK_PREVIEW_ONLY=true
```

Install Flutter's [Linux build prerequisites](https://docs.flutter.dev/platform-integration/linux/setup).
The locked `audioplayers_linux` native CMake additionally requires GStreamer1.0,
app and audio development modules. Native BlueZ access and local audio playback
require a functioning desktop session; headless compilation proves neither.
The locked Linux file picker uses the desktop FileChooser portal. The minimal
guest needed `xdg-desktop-portal` and its GTK backend before actual selection
worked; the guest bootstrap now includes them. The actual app then imported the
owned PCM16 WAV through its picker and decoder isolate. The persisted mono draft
matches all 5,644 native reference samples; no audio was played.
Linux's native decoder currently provides WAV/MP3/FLAC via miniaudio, with no
platform AAC fallback. Actual accepted formats still need target-native tests.

On a Mac with Xcode/CocoaPods configured:

```sh
flutter build macos --debug --no-pub --dart-define=BDK_PREVIEW_ONLY=true
flutter build ios --simulator --debug --no-codesign --no-pub --dart-define=BDK_PREVIEW_ONLY=true
```

These are preview/build commands, not signed production release packages. Follow Flutter's
[iOS release guide](https://docs.flutter.dev/deployment/ios) and
[Windows distribution guide](https://docs.flutter.dev/deployment/windows) when
the publisher identity and channel are selected. Apple simulator success does
not prove physical Bluetooth functionality.

## Prepared CI, not executed

`.github/workflows/native-preview.yml` is manual-only, uses a pinned Flutter SDK
revision and pinned official checkout/artifact actions, and prepares Windows,
Linux, macOS and iOS simulator preview bundles. It has read-only repository
permissions and no release, signing, device install or firmware operation.
Archives preserve Apple framework symlinks and include complete desktop bundles.
It has been prepared locally; no remote workflow or Apple build is claimed.
Local Linux guest evidence is recorded separately from that unexecuted workflow.

This Windows host has no Apple SDK. Its WSL inventory query failed with
`Wsl/CallMsi/Install/REGDB_E_CLASSNOTREG`. No host repair, WSL installation or
global Developer Mode change was attempted. An isolated local QEMU/Ubuntu guest
now provides a Linux runner with no host hardware passthrough; its bootstrap and
precise evidence are in [the runner receipt](validation/2026-10-16-linux-runner.md).
An Apple SDK runner is still needed. Linux guest compilation and native Demo/WAV
checks are now recorded. They do not prove physical Bluetooth/audio or every
Linux distribution. The Noble0.5.6 bundle imports GLIBC2.38 / GLIBCXX3.4.29;
the separately built Jammy0.5.6 bundle lowers its maximum to GLIBC2.34 with the
same GLIBCXX requirement. Jammy's default llvmpipe GUI aborted; softpipe reached
Setup, but interaction remains unverified. See the exact
[Jammy receipt](validation/2026-10-16-linux-jammy.md); no broad compatibility claim.

## SDK floors and architecture coverage

The [official Flutter 3.44 matrix](https://github.com/flutter/website/blob/a43b0e7d3092b64db4933397aaddaed41f333ba1/sites/docs/src/content/reference/supported-platforms.md)
is the SDK baseline, not an app validation receipt. Current app configuration:

| Target | Configured floor / SDK range | Current artifact coverage |
|---|---|---|
| Android | API 24 minimum; target 36 | ARMv7/ARM64/x64 compile/package checks pass through0.6.8; ARM64 physical graphics and x64 hardware GPU evidence through0.6.8 |
| iPhone/iPad | iOS 14 minimum; both device families 1,2 | Apple ARM64 native build/runtime remain |
| macOS | 10.15 minimum | Intel/Apple Silicon builds remain |
| Windows | SDK Windows 10/11 | x64 native preview; ARM64 needs a native runner for the pinned CLI |
| Linux | SDK Ubuntu 20.04–24.04 LTS / Debian 10–13 | Noble0.5.6 runtime verified; Jammy0.5.6 GLIBC2.34 build passes, GUI interaction pending |

A separate Ubuntu22.04 root has rebuilt the unchanged0.5.6 native sources against
older libc/GTK/GStreamer, preserving `-fno-fast-math` and lowering the measured
GLIBC requirement. Native interaction remains unverified, and the0.5.7 repair
needs a fresh source/build gate. Copying the Noble LED library would retain its
GLIBC2.38 requirement. Jammy does not prove the oldest distributions. ARM64 Linux needs
its own native environment; the pinned Flutter Linux build command rejects
x64-to-ARM64 cross-building. General Linux audio identity remains limited as
documented in [the source-backed boundary](migration/linux-audio-identity-boundary.md).

The [Android architecture checkpoint](validation/2026-10-16-android-architecture-checkpoint.md)
records the three exact APKs and their limited validation claims. Windows ARM64
inventory found no ARM64 compiler component, and the pinned Flutter command
selects the host architecture. No additional host toolchain or ARM64 build was
attempted. The [older Linux ABI plan](superpowers/plans/2026-10-16-linux-older-abi.md)
defines separate Jammy compilation, ELF and native runtime checks.

## Before a production release

- Validate each target natively with its own BLE/audio identity and permission
  behavior. Do not replace a missing OS capability with a misleading success.
- Capture connected music, stale/lost telemetry, suspend/resume, reconnect,
  cancellation, rotation/resizing, keyboard and screen-reader behavior.
- Confirm SDK/OS minimums, codecs and accepted import formats from actual builds.
- Confirm final branding selection, publisher identities, signing,
  dependency/license review, versioning, installer/store metadata and a trusted
  app-update source. Original musical-B vector exports replace scaffold launcher
  artwork on all five targets. Font/native notices are accessible from App info
  and verified in Android/Windows packages. Remaining source rights and publisher
  decisions are recorded in the [branding/license audit](validation/branding-license-audit.md).
- Keep app-side protocol tests separate from physical transfer/update evidence.
  The latter is outside the current authorized hardware scope.
