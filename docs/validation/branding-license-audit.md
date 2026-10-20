# Branding and redistribution inputs audit

2026-10-16. Read-only inventory at app commit
`604f7d3835449d9a9e3c6a50af47b92e3c798826`; later branding work needs its own
verification. This records local evidence and unresolved release inputs, not
release clearance or a grant of rights. Only this document was added by the
audit. No dependencies, fonts, icons, source, hardware, OS settings, accounts,
or network services were changed or exercised.

Later implementation is recorded in the [0.5.5 release-assets checkpoint](2026-10-16-release-assets-checkpoint.md): app notices, native exports and the placeholder LED notice have been addressed. Publisher/source rights and final target-specific distribution review remain unresolved. The findings below retain their audited-commit scope.

## Release inputs still needed

1. **Publisher and application terms:** no root `LICENSE`, `NOTICE`, or
   `THIRD_PARTY_NOTICES` exists. A publisher must choose terms for app-owned
   work and confirm authority for original assets/source separately. Existing
   `com.bdkaudio` metadata is a configured identifier, not evidence of publisher
   identity or rights. Do not replace missing terms with an invented MIT grant.
2. **Copied LED source:** `packages/bdk_led_engine/LICENSE` literally contains
   `TODO: Add your license here.` The capsule includes unchanged copied source;
   hashes establish identity, not permission. Obtain the applicable source
   license/authorization and preserve it before presenting redistribution as
   settled. Decide terms for the separate wrapper/shims independently.
3. **Original application and branding:** the sibling Android README says
   `This project is proprietary software. All rights reserved.` Its developer
   credit is WillyBilly. No standalone license/notice/font license file was found
   by the scoped filename inventory. Original branding and any derived app
   implementation need publisher confirmation under those original terms.
4. **Ship readable notices:** cached package licenses exist, and generated
   `NOTICES.Z` exists, but the app has no license page/registration. Fonts' OFL
   texts and native source notices are not explicitly bundled by `pubspec.yaml`.
   Add readable distribution notices and verify the actual packaged result;
   keeping files in the repository alone does not establish delivery.
5. **Platform/native inventory:** account for Linux `bluez`/`dbus` MPL source
   availability and native build inputs beyond Pub. Complete target-specific
   dependency/notice inventories from the final release artifacts; this cache
   review is not a complete Android Gradle, Apple Pods, Linux system-library,
   Flutter-engine, or Windows runtime audit.

The existing root `README.md` calls this active development, explicitly not a
production release; `docs/platform-release-matrix.md` already lists branding,
publisher identity, signing, and license review as open. Android's release build
currently uses the debug signing configuration (`android/app/build.gradle.kts`).
This audit does not change those release gates.

## Branding present at the audited commit

| Target | Local evidence | Finding |
| --- | --- | --- |
| Android | `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png`; `AndroidManifest.xml` references `@mipmap/ic_launcher` | Inspected 192px image shows Flutter. Its bytes match the local Flutter SDK's corresponding template. No app adaptive icon/round icon resource is present. |
| iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` and 15 PNGs | Inspected 1024px icon shows Flutter on white. The Xcode project selects `AppIcon`. Launch images are separate assets. |
| macOS | `macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json` and 7 PNGs | Inspected 1024px icon shows Flutter inside a rounded white tile. |
| Windows | `windows/runner/resources/app_icon.ico`; `Runner.rc` selects it | ICO contains 16, 32, 48, 256px frames. File SHA256 `c098d3fc85cacff98b8e69811b48e9f0d852fcee278132d794411d978869cbf8`. The image viewer did not accept ICO; no visual claim is made for it. |
| Linux | `linux/CMakeLists.txt`, `linux/runner/my_application.cc` | Binary/application identity exists; no `.desktop` launcher, app icon, or packaging icon resource was found under `linux/`. |
| In-app | `lib/features/app_info/app_info_screen.dart` | Displays BDK Audio, dynamic version/build, a Material speaker glyph, and original creator WillyBilly. No license navigation is present. |

Android application IDs are `com.bdkaudio.controller` and the isolated
`com.bdkaudio.controller.nativeqa` (`android/buildSrc/src/main/java/BdkBuildIdentity.java`).
iOS/macOS use `com.bdkaudio.bdkAudio`; Linux uses `com.bdkaudio.bdk_audio`.
Windows `Runner.rc` uses CompanyName `com.bdkaudio` and copyright 2026;
macOS `AppInfo.xcconfig` has the same nominal publisher/copyright. The publisher
must confirm final identity, copyright text, signing ownership, and store/installer
metadata. No account lookup was performed.

### Exact original asset options

Paths in this table are relative to the read-only sibling
`D:/ESP32 Bluetooth/BDK-AUDIO-APP-main/`.

| Asset | Technical option and evidence |
| --- | --- |
| `app/src/main/ic_launcher-playstore.png` | Actual 512 by 512 RGBA store bitmap. Visually inspected: blue gradient, large B, radio waves/arrows and a board image. SHA256 `8bc20951a0200980d9eee49bfb366d15a8bcda31b6687ccc55e13799a1fbcd96`. This is the largest supplied launcher bitmap located; enlarging it does not create original 1024px detail. |
| `app/src/main/res/mipmap-*/ic_launcher.png` | Original square launcher exports: 48/72/96/144/192px across mdpi through xxxhdpi. xxxhdpi SHA256 `2b168aa47b724089b20e46aad8c157c82adf47c4340b58bbce473161f5834561`. |
| `app/src/main/res/mipmap-*/ic_launcher_round.png` | Round variants at the same five dimensions. xxxhdpi SHA256 `afe8f89ef5554dbebe45e184fa9942af18073f0b6f041d5774948bd6c7037a0a`. |
| `app/src/main/res/mipmap-*/ic_launcher_foreground.png` | Adaptive foreground exports: 108/162/216/324/432px. xxxhdpi SHA256 `abcec80ff658307f46004928f3d6b64ffb5acc3ec9717b5020d2e9d0a46d289a`. Both `mipmap-anydpi-v26/ic_launcher*.xml` use these foregrounds with `@color/ic_launcher_background` (`#96D7AF`). |
| `app/src/main/res/drawable/bdk_logo_icon.xml` | Resolution-independent, 100 by 100 viewport speaker/circle/waves vector, distinct from the B/board launcher bitmap. Uses `@color/bdk_accent_primary`, defined as `#FF00D4FF` in `values/colors_brand.xml`. SHA256 `fc40fc24502ca94f8ad26368c99ed84f9e95f3fad03ca0610051267f4de930a7`. Technically suitable for scalable exports if chosen by the publisher. |
| `app/src/main/res/drawable/ic_launcher_foreground.xml`, `ic_launcher_background.xml` | Separate 108dp Android template vector resources, not the mipmap foregrounds selected by the original adaptive icon XML. Do not mistake their filenames for the chosen BDK launcher artwork. |

These are reuse candidates, not a decision to rebrand or license the images. A
publisher still needs to select the master asset and confirm rights to the whole
artwork, including the embedded board image. Preserve originals and document
conversion provenance when generating platform exports.

## Fonts: existing licenses and delivery gap

Both font binaries are declared under `flutter.fonts` in `pubspec.yaml`; both
OFL files already exist. No font was replaced or modified.

| Font | Local binary metadata / SHA256 | Existing text |
| --- | --- | --- |
| `assets/fonts/Manrope.ttf` | Version 4.505; name table says copyright **2019** Manrope Project Authors, and SIL OFL 1.1. SHA256 `3ae11c49db0455a3cc33e37d380f20fdb8c7f8b41dc07625c177e3d87a9d6ae6`. | `assets/fonts/Manrope-OFL.txt`: SIL OFL 1.1, copyright **2018** Manrope Project Authors. Preserve both; obtain/confirm the notice corresponding to the exact binary rather than silently editing the year. |
| `assets/fonts/SpaceGrotesk.ttf` | Version 2.000; copyright 2020 Space Grotesk Project Authors; SIL OFL 1.1. SHA256 `acad6de1fc93436f5c0f1f4137751ef04f1aea3063e7036535970ffcfbd79f72`. | `assets/fonts/SpaceGrotesk-OFL.txt`: SIL OFL 1.1 and matching 2020 project credit. |

The OFL texts' condition 2 addresses delivery of copyright and license with
bundled fonts. `pubspec.yaml` does not list either text as an asset; no
`LicenseRegistry`, `showLicensePage`, or equivalent registration was found under
`lib/`. Font name-table license links are not the complete OFL text. This is a
packaging/readability gap, not an absence of font license evidence.

## Owned native packages and copied source

| Component | Evidence actually present | Open boundary |
| --- | --- | --- |
| LED wrapper, ABI, memory driver, shims | `packages/bdk_led_engine/README.md`, `src/bdk_led_engine.{h,cpp}`, `src/led/led_driver_spi.h`, `src/led/sdkconfig.h`, `src/dsp/esp_attr.h` describe app-side portable adaptation. | Package `LICENSE` is a TODO; no terms for these app-owned files were assigned by this audit. |
| Original LED algorithms/config/fast math | `packages/bdk_led_engine/SOURCE_PROVENANCE.json` names three unchanged copied files. Current capsule hashes match all three recorded hashes (below). No copyright/license header or separate applicable source license was found in the copied capsule. | Provenance cannot establish the original source's license. The supplied ESP32 repository was not opened or scanned. Do not apply decoder/wrapper terms to this copied source. |
| Decoder wrapper/platform fallbacks | `packages/bdk_audio_decoder/LICENSE` contains MIT, copyright 2026 BDK Audio contributors, and explicitly separates miniaudio. | This records a license already present; publisher/contributor authority was not verified, and it does not license other app packages. |
| miniaudio 0.11.25 | `packages/bdk_audio_decoder/THIRD_PARTY_NOTICES.md`, `SOURCE_PROVENANCE.json`, `src/vendor/miniaudio/LICENSE`, and unchanged `miniaudio.h` are present. Provenance selects MIT No Attribution; upstream text also includes Unlicense. | Preserve full upstream notices and pin. Header embeds copyright 2026 David Reid; separate license says 2025. Both are retained; the audit does not rewrite either. |
| App-derived behavior | `docs/migration/ota-app-source-provenance.md` records original Android source paths/hashes; `docs/migration/windows-audio-connection-provenance.md` documents app-written native identity work. | Attribution/provenance is not a replacement for the original app's proprietary terms or publisher confirmation. No additional original implementation sources were opened for this audit. |

Copied LED SHA256 values, verified only against the owned capsule:

| Capsule path | SHA256 |
| --- | --- |
| `packages/bdk_led_engine/src/led/led_effects.h` | `81b9573aec358d60a00e4ed4601ba523b1b9c40156e913d5bb8686c355353304` |
| `packages/bdk_led_engine/src/led/led_config.h` | `ecaa124964059bc1cd09bf8adfb07cffe77be2f5579c415d9c1c42857e985804` |
| `packages/bdk_led_engine/src/dsp/fast_math.h` | `8275dc356200094e35820dfebcd93873a5cf56373d70b75862fb2cd109df12ed` |

miniaudio provenance pins commit `9634bedb5b5a2ca38c1ee7108a9358a4e233f14d`.
Measured header SHA256 is
`ac7af4de748b7e26b777f37e01cee313a308a7296a3eb080e2906b320cc55c89`;
separate license SHA256 is
`457f1b500e0adf6bc059edddfa78a2f62012e7c3bb43476c20e0bd23b25ba0eb`.
Both match local provenance. No upstream/network verification was attempted.

## Resolved package and native notice inventory

`pubspec.lock` SHA256:
`d097b16c7b036133ca28e3a3a0ab4c3ad4080ce790fcf75044db20801bec948f`.
All 88 hosted lock entries resolve to the local roots in
`.dart_tool/package_config.json`, and all 88 have a root `LICENSE` file.
Root text inventory: **62 BSD-3-Clause, 21 MIT, 3 Apache-2.0, 2 MPL-2.0**.
This includes development and platform packages; presence in the lock/cache does
not prove inclusion of every package in every binary. The appendix records exact
versions and roles, including `shared_preferences` **2.5.6**, rather than the
`^2.5.4` constraint.

For each hosted appendix row, primary evidence is the file
`C:/Users/ngocv/AppData/Local/Pub/Cache/hosted/pub.dev/<name>-<version>/LICENSE`.
The local Flutter SDK root `C:/Users/ngocv/dev/flutter/LICENSE` contains BSD-3-Clause
text; Flutter 3.44.4 is recorded in package configuration. SDK/engine bundled
third-party notices need release-artifact review in addition to this root file.

Additional locally found inputs requiring explicit accounting:

- `bluez-0.8.3/LICENSE` and `dbus-0.7.15/LICENSE` contain MPL 2.0. Sections 3.1/3.2
  address source form and executable distribution, including informing recipients
  how to obtain source. Record exact versions, modifications, and source delivery
  method for the Linux artifact; an attribution page alone does not establish
  that this release input is complete.
- `characters-1.4.1/third_party/Unicode_Consortium/UNICODE_LICENSE.txt` contains
  Unicode License V3, copyright 1991-2024 Unicode, Inc., in addition to the BSD
  root file.
- `pointycastle-4.0.0/LICENSE` contains MIT text crediting the Legion of the Bouncy
  Castle. `licenses/LICENSE-scrypt.txt` contains Apache 2.0. The nested
  `licenses/LICENSE-BouncyCastle.html` contains MIT body text and a historical
  LGPL3/MPL2 comment in its HTML header. Preserve the supplied files and flag this
  mixed historical metadata for release review; do not classify the entire
  current package as LGPL merely from that comment.
- `audioplayers-6.8.1/example/server/public/files/LICENSE`,
  `shared_preferences_windows-2.4.1/example/LICENSE`, and
  `shared_preferences-2.5.6/extension/devtools/build/assets/NOTICES` also exist.
  They belong to example/tool inputs; determine inclusion from the release
  artifact rather than asserting that those assets ship in this app.
- Windows plugin CMake inputs request CppWinRT **2.0.220418.1** and Windows
  Implementation Library **1.0.260126.7**. Their locally installed build inputs
  have MIT license files at
  `build/windows/x64/packages/Microsoft.Windows.CppWinRT.2.0.220418.1/LICENSE`
  and `build/windows/x64/packages/Microsoft.Windows.ImplementationLibrary/LICENSE`.
  Preserve the Microsoft notices when reviewing compiled/header-derived output.

### What current generated notices actually contain

Decompressed existing build outputs were inspected without rebuilding:

| Output | Compressed SHA256 | Observation |
| --- | --- | --- |
| `build/flutter_assets/NOTICES.Z` | `3e7b376e10719db3ed5f1bf28acf0049a4cca8da16cee32ae48fbef73a23dc63` | Includes `bdk_led_engine` followed by the literal license TODO, decoder root license, package notices including bluez/dbus; no Manrope/Space Grotesk names or David Reid. |
| `build/windows/x64/runner/Profile/data/flutter_assets/NOTICES.Z` and `build/app/intermediates/flutter/profile/flutter_assets/NOTICES.Z` | `7f2c4b53cdb82c5aba5386b8201401b63ec98a5124254d64682746e0ea824bc0` | Same TODO/font/miniaudio author observations. |

The word miniaudio appears because the decoder root license references its
separate license path; that is not evidence that the full nested license text was
bundled. MIT No Attribution is the recorded miniaudio selection, so this audit does
not claim an attribution requirement for it. Unicode appears in generated
notices, but a substring match alone does not prove the exact characters nested
notice is included. Rebuild and inspect the final artifacts after notices are
implemented, and verify their user-facing access.

## Appendix: hosted packages at the audited lock

This is a local text inventory, not legal compatibility analysis. `main` and
`dev` identify direct dependencies; other rows are transitive.

| Package | Version | Root license text | Dependency role |
| --- | --- | --- | --- |
| `android_file_picker` | 2.1.1 | MIT | transitive |
| `args` | 2.7.0 | BSD-3-Clause | transitive |
| `async` | 2.13.1 | BSD-3-Clause | transitive |
| `audioplayers` | 6.8.1 | MIT | main |
| `audioplayers_android` | 5.3.0 | MIT | transitive |
| `audioplayers_darwin` | 6.5.0 | MIT | transitive |
| `audioplayers_linux` | 4.3.0 | MIT | transitive |
| `audioplayers_platform_interface` | 7.2.0 | MIT | transitive |
| `audioplayers_web` | 5.3.0 | MIT | transitive |
| `audioplayers_windows` | 4.4.1 | MIT | transitive |
| `bluez` | 0.8.3 | MPL-2.0 | transitive |
| `boolean_selector` | 2.1.2 | BSD-3-Clause | transitive |
| `characters` | 1.4.1 | BSD-3-Clause | transitive |
| `clock` | 1.1.2 | Apache-2.0 | transitive |
| `code_assets` | 1.2.1 | BSD-3-Clause | transitive |
| `collection` | 1.19.1 | BSD-3-Clause | transitive |
| `convert` | 3.1.2 | BSD-3-Clause | transitive |
| `cross_file` | 0.3.5+5 | BSD-3-Clause | transitive |
| `crypto` | 3.0.7 | BSD-3-Clause | main |
| `dbus` | 0.7.15 | MPL-2.0 | transitive |
| `fake_async` | 1.3.3 | Apache-2.0 | transitive |
| `ffi` | 2.2.0 | BSD-3-Clause | transitive |
| `ffi_leak_tracker` | 0.1.2 | BSD-3-Clause | transitive |
| `file` | 7.0.1 | BSD-3-Clause | transitive |
| `file_picker` | 13.1.0 | MIT | main |
| `file_picker_darwin` | 2.3.2 | MIT | transitive |
| `file_picker_linux` | 2.0.0 | MIT | transitive |
| `file_picker_platform_interface` | 4.2.0 | MIT | transitive |
| `file_picker_web` | 4.2.0 | MIT | transitive |
| `fixnum` | 1.1.1 | BSD-3-Clause | transitive |
| `flutter_lints` | 6.0.0 | BSD-3-Clause | dev |
| `flutter_web_bluetooth` | 1.2.0 | MIT | transitive |
| `hooks` | 2.0.2 | BSD-3-Clause | transitive |
| `http` | 1.6.0 | BSD-3-Clause | transitive |
| `http_parser` | 4.1.2 | BSD-3-Clause | transitive |
| `jni` | 1.1.0 | BSD-3-Clause | transitive |
| `jni_flutter` | 1.0.4+1 | BSD-3-Clause | transitive |
| `jni_util` | 1.0.0 | BSD-3-Clause | transitive |
| `leak_tracker` | 11.0.2 | BSD-3-Clause | transitive |
| `leak_tracker_flutter_testing` | 3.0.10 | BSD-3-Clause | transitive |
| `leak_tracker_testing` | 3.0.2 | BSD-3-Clause | transitive |
| `lints` | 6.1.0 | BSD-3-Clause | transitive |
| `logging` | 1.3.0 | BSD-3-Clause | transitive |
| `matcher` | 0.12.19 | BSD-3-Clause | transitive |
| `material_color_utilities` | 0.13.0 | Apache-2.0 | transitive |
| `meta` | 1.18.0 | BSD-3-Clause | transitive |
| `objective_c` | 9.5.0 | BSD-3-Clause | transitive |
| `package_config` | 3.0.0 | BSD-3-Clause | transitive |
| `package_info_plus` | 10.2.2 | BSD-3-Clause | main |
| `package_info_plus_platform_interface` | 4.1.0 | BSD-3-Clause | transitive |
| `path` | 1.9.1 | BSD-3-Clause | transitive |
| `path_provider` | 2.1.6 | BSD-3-Clause | main |
| `path_provider_android` | 2.3.1 | BSD-3-Clause | transitive |
| `path_provider_foundation` | 2.6.0 | BSD-3-Clause | transitive |
| `path_provider_linux` | 2.2.2 | BSD-3-Clause | transitive |
| `path_provider_platform_interface` | 2.1.3 | BSD-3-Clause | transitive |
| `path_provider_windows` | 2.3.0 | BSD-3-Clause | transitive |
| `petitparser` | 7.0.2 | MIT | transitive |
| `platform` | 3.2.0 | BSD-3-Clause | transitive |
| `plugin_platform_interface` | 2.1.8 | BSD-3-Clause | transitive |
| `pointycastle` | 4.0.0 | MIT | main |
| `pub_semver` | 2.2.1 | BSD-3-Clause | transitive |
| `record_use` | 0.6.0 | BSD-3-Clause | transitive |
| `shared_preferences` | 2.5.6 | BSD-3-Clause | main |
| `shared_preferences_android` | 2.4.28 | BSD-3-Clause | transitive |
| `shared_preferences_foundation` | 2.5.7 | BSD-3-Clause | transitive |
| `shared_preferences_linux` | 2.4.1 | BSD-3-Clause | transitive |
| `shared_preferences_platform_interface` | 2.4.2 | BSD-3-Clause | transitive |
| `shared_preferences_web` | 2.4.3 | BSD-3-Clause | transitive |
| `shared_preferences_windows` | 2.4.1 | BSD-3-Clause | transitive |
| `source_span` | 1.10.2 | BSD-3-Clause | transitive |
| `stack_trace` | 1.12.1 | BSD-3-Clause | transitive |
| `stream_channel` | 2.1.4 | BSD-3-Clause | transitive |
| `string_scanner` | 1.4.1 | BSD-3-Clause | transitive |
| `synchronized` | 3.5.0 | MIT | transitive |
| `term_glyph` | 1.2.2 | BSD-3-Clause | transitive |
| `test_api` | 0.7.11 | BSD-3-Clause | transitive |
| `typed_data` | 1.4.0 | BSD-3-Clause | transitive |
| `universal_ble` | 3.1.0 | BSD-3-Clause | main |
| `uuid` | 4.6.0 | MIT | transitive |
| `vector_math` | 2.2.0 | BSD-3-Clause | transitive |
| `vm_service` | 15.4.0 | BSD-3-Clause | transitive |
| `web` | 1.1.1 | BSD-3-Clause | transitive |
| `win32` | 6.4.0 | BSD-3-Clause | transitive |
| `windows_file_picker` | 2.0.1 | MIT | transitive |
| `xdg_directories` | 1.1.0 | BSD-3-Clause | transitive |
| `xml` | 7.0.1 | MIT | main |
| `yaml` | 3.1.4 | MIT | transitive |
