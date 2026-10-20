# Android architecture packaging checkpoint

Source checkpoint: `342494db8f486b36b19d9882eacc0c670d4959a1`, version **0.5.6+14**.
This expands build coverage without changing application code or the installed
Redmagic application. It does not establish ARMv7/x64 runtime or Bluetooth support.

## Actual build and package verification

The pinned Flutter 3.44.4 SDK completed this command with exit 0:

```powershell
flutter build apk --release --no-pub --split-per-abi --target-platform android-arm,android-arm64,android-x64 -t lib/main.dart --dart-define=BDK_PREVIEW_ONLY=true
```

Build output reports all three APKs. The log is
`artifacts/android-056-all-abi-build.log`; independently inspected packages and
machine-readable receipts are in `artifacts/android-0.5.6-all-abi/`.

| ABI | Bytes | Version code | SHA256 |
|---|---:|---:|---|
| armeabi-v7a | 17,863,250 | 1014 | `68d87543148d55d990641f9dae269454eab8fe77bb5106e80ae73035dd94dba9` |
| arm64-v8a | 20,712,890 | 2014 | `306fc5f5d40b77cbf005af473148d178fc9b71e9fbef396d47b9673c4b8b56db` |
| x86_64 | 22,219,392 | 4014 | `ee915e9b50243bd6477d1a09dcb42d625ced27b49957ad6f60d2df843e879ebe` |

Each APK passes ZIP CRC and Android SDK 36 `apksigner verify`. Its manifest has
package `com.bdkaudio.controller`, version 0.5.6, minimum API 24, target API 36 and no
debuggable application flag. All use the same **Android Debug development
certificate**; Release optimization is not production signing.

Each archive contains exactly its own ABI and all six native libraries:
`libapp`, `libflutter`, `libbdk_audio_decoder`, `libbdk_led_engine`, `libdartjni`
and `libdatastore_shared_counter`. Every ELF header has the expected class and
machine (`EM_ARM=40`, `EM_AARCH64=183`, or `EM_X86_64=62`). All eight bundled
font/native notice assets match their source bytes.

The separately preserved installed ARM64 APK retains SHA256
`6d625fa98be1a3e7f68d51a0e8b670eab215bef617dc2617507b14ecee9c2a07`.
The new ARM64 APK has a different whole-file hash. All **388 uncompressed ZIP
entries** nevertheless have identical paths/content, with no added/removed
entry; neither package is substituted for the other's installation receipt.
See `arm64-installed-payload-comparison.json`. No reinstall, downgrade, app-data
erase or operation on another attached phone occurred.

The initial verification helper expected SDK 34's `sdkVersion` badging spelling
and a desktop-only `version.json` asset. Those assumptions failed against the
actual APK. The corrected check uses SDK 36's `minSdkVersion` spelling and the
Android manifest, and derives notice paths from `lib/licenses.dart`; application
files and acceptance values were unchanged.

## Windows ARM64 runner inventory

This Windows host is x64. Its installed MSVC 14.44.35207 Hostx64 compiler targets
are x64/x86, and `vswhere` finds no
`Microsoft.VisualStudio.Component.VC.Tools.ARM64` installation. In addition,
the pinned Flutter 3.44.4
[Windows build command](https://github.com/flutter/flutter/blob/3.44.4/packages/flutter_tools/lib/src/commands/build_windows.dart)
chooses `windows-arm64` only on a Windows ARM64 host; this runner selects x64.
Installing an extra compiler alone would not change that command's selection.

No ARM64 build or installer operation was attempted. Actual ARM64 build/runtime
validation needs a suitable native runner. The read-only inventory and source
SHA256 are in `artifacts/windows-arm64-runner-inventory.json`.

## Remaining scope

ARMv7/x64 Android packages are compile/package evidence only. Redmagic ARM64
native UI evidence remains as recorded in the Light-theme checkpoint; live
music/BLE/codec checks await the user's connected/playing state. Apple native
SDK/hardware, Windows/Linux ARM64, older Linux runtimes, publisher/source rights
and signing/distribution gates remain open. No ESP32 source, serial, hardware,
Bluetooth setting or physical speaker operation was performed.
