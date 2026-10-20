# Original Android feature parity audit

2026-10-16. Read-only source audit of the supplied Android application against
Flutter HEAD `abf19a59b44bb94a34b374a302344f434868e9a5`. This document is the only
file authored by this audit. It does not claim a running native or physical test.
Concurrent agents may change the worktree after this baseline; findings below
describe the stated HEAD, not later repairs.

## Scope and evidence notation

- `O:` means `D:\ESP32 Bluetooth\BDK-AUDIO-APP-main\`.
- `N:` means `D:\ESP32 Bluetooth\BDK-Audio-Flutter\` at the audited HEAD.
- `J/` below abbreviates original `app/src/main/java/com/example/myspeaker/`.
- `R/` below abbreviates original `app/src/main/res/layout/`.
- `S/` below abbreviates original `shared/src/commonMain/kotlin/com/example/myspeaker/shared/`.
- References are exact source file and one-based line numbers. Ranges describe
  the supporting action/call chain, not runtime coverage.

Only original Android/shared application sources, layouts, and owned Flutter
sources/provenance were inspected. No ESP32 project was read, edited, built,
flashed, or operated. No serial, ADB, BLE, audio, operating-system device probes,
playback, network, or hardware operation was performed. No applicable AGENTS.md
was found in either audited application tree. A quick memory-registry search
found no relevant Flutter/BDK entry; this audit relies on fresh source inspection.

## Actual shipped navigation

The active baseline is **ConnectionActivity → MainActivityRedesign**, despite
the legacy activity's name. The manifest launcher is `O:app/src/main/AndroidManifest.xml:16-25`;
`O:J/ConnectionActivity.kt:440-446` explicitly starts `MainActivityRedesign`.
The latter loads `activity_main_redesign` at `O:J/MainActivityRedesign.kt:313-315`.
Its settings action launches `SettingsActivity` at lines 432-532. Settings opens
the active codec activity at `O:J/SettingsActivity.kt:125-129`, opens the device
information bottom sheet at lines 120-122 and 252-270, and returns firmware/app
information actions at lines 186-199. The redesign handles these at
`O:J/MainActivityRedesign.kt:1954-1976`; firmware update opens `OtaActivity` at
lines 2913-2923.

Consequently:

- `MainActivityRedesign` is active, not a disposable mockup.
- `MainActivity`/`activity_main`, standalone `DeviceInfoActivity` and
  `AppInfoActivity`, and `activity_main_v2` are not the normal launcher route.
  Manifest registration alone does not prove user reachability.
- The legacy MainActivity local firmware picker and twelve-preset listeners
  must not be confused with the redesigned activity's active nine-preset set.
- A misleading comment saying sound methods are placeholders at
  `O:J/MainActivityRedesign.kt:1687` does not erase the actual sound callbacks and
  upload implementation at lines 518-529 and 2491-2719.

## Findings ranked by concrete user effect

### 1. Original full-picker Off ID 255 is rejected by Flutter

**Confirmed original-app sentinel mismatch; physical compatibility is unproven.**
The active original dropdown adds `Off` with ID 255 at
`O:J/MainActivityRedesign.kt:838-842`. Selecting it follows `onEffectSelected`
(870-900), `applyLedEffect` (1158-1161), and `sendLedEffect` (1885-1891), producing
the shared `SET_LED_EFFECT` command. The original also accepts/displays ID 255
from LED status/full status at lines 1480-1488 and 1614-1622. `O:S/LedEffects.kt:29`
independently names that sentinel.

`N:lib/domain/speaker_state.dart:60-63` restricts serialized effects to 0..21.
Incoming LED status is validated through that serializer by
`N:lib/protocol/speaker_protocol.dart:66-78`, including FULL_STATUS at line 154.
`N:lib/connection/speaker_session.dart:294-308` requires a valid full status to
finish synchronization; malformed LED status is ignored at lines 343-349.
Therefore an original-protocol full status containing 255 cannot finish the
Flutter synchronization gate. The source chain proves that rejection; whether
a particular physical firmware accepts/persists the original command was not
tested in this audit.

The original **quick Off tile** is a different path: it sets brightness to zero
and retains the effect (`O:J/MainActivityRedesign.kt:1024-1039`). Flutter already
implements this ordinary lights-off behavior and brightness restoration at
`N:lib/features/light/light_screen.dart:705-741`. That capability is retained.
The omitted compatibility is the original dropdown sentinel and its status,
not the ability to turn lights dark. Merely accepting 255 in the parser would
also require safe UI/renderer handling: `_names[widget.settings.effect]` at
lines 674 and 757 currently assumes 0..21.

**Post-audit contract reconciliation:** the previously recorded project
[protocol contract](../migration/protocol-contract.md) explicitly forbids sending
effect255 and defines Off as brightness zero. The original dropdown's `06 FF`
is therefore not evidence of a working physical feature to reproduce. The
0.5.3 repair tolerates that sentinel in incoming status and renders it safely,
but rejects it in outgoing SET_LED. Gallery Off instead sends zero brightness
with the remembered valid effect, matching the recorded project contract.
This correction was made before installing the new preview. No ESP32 source or
device was accessed to resolve it; no saved physical255 state is claimed.

### 2. Saved/single-speaker automatic control connection is absent

**Confirmed convenience omission; manual connection remains implemented.**
The original stores the chosen address/name at `O:J/ConnectionActivity.kt:434-438`,
automatically selects that saved discovery at lines 378-383, and automatically
connects a sole candidate after two seconds at lines 386-398. Candidates first
pass service and same-A2DP-address checks at lines 332-340 and 353-360.

Flutter automatically selects a single connected audio identity only when its
name matches BDK (`N:lib/connection/speaker_setup_controller.dart:90-100`), but
does not persist or automatically connect the matching BLE control candidate.
Control connection requires `connectControls` at lines 224-242, wired to the
user action at `N:lib/app.dart:1227`. The reviewed setup/profile code has no saved
speaker-address store or discovery-triggered connection call. Users can still
choose and connect the same speaker; the extra selection is the lost behavior.
This can be an intentional product decision under the approved focused pairing
flow, but it should be explicit rather than described as automatic reconnect
parity. Any restoration must retain the current same-device identity and
fresh-status gates; the original countdown alone is not sufficient evidence.

**Post-audit 0.5.4 repair:** the client now remembers a fully synchronized speaker
after a fresh final OS audio check. Verified audio can start discovery and connect
the matching saved/sole candidate, with a finite retry policy and explicit stop.
Unknown identities and manual-confirmation platforms cannot authorize automation.
Installed preview-only builds keep automatic connections disabled; physical
reconnection remains a native validation gate.

### 3. App information/version/creator screen is missing

**Confirmed small user-facing omission.** Original Settings → App info is active
(`O:J/SettingsActivity.kt:194-199`; `O:J/MainActivityRedesign.kt:1975-1976`).
The sheet reads the installed package version and app name at
`O:J/AppInfoBottomSheet.kt:25-43`, and `O:R/fragment_app_info.xml:58-113` supplies
the description and WillyBilly creator credit. Flutter Speaker routes at
`N:lib/app.dart:984-1073` contain no App info/About route; a source search found
no installed-app version lookup or corresponding credit. The static project
version in pubspec is not a reachable installed-version display.

**Post-audit 0.5.3 repair:** Speaker → App info now reads installed package
metadata and retains the creator credit. Native Redmagic and Windows version/build
displays were verified in the [parity checkpoint](2026-10-16-parity-contrast-checkpoint.md).

No other confirmed loss of an active original **manual control action** was
identified in this bounded source audit. All main controls below have client
routes and protocol/API implementations. This statement is not physical parity,
native test completion, production readiness, or a claim that every platform
exposes Android's codec APIs.

## Active action mapping

| Genuine original action or display | Original evidence | Flutter source route/API | Assessment |
|---|---|---|---|
| Grant Bluetooth access, open system audio pairing, retry search | `O:J/ConnectionActivity.kt:159-169,244-255,261-300,416-417` | `N:lib/app.dart:1170-1227`; `lib/connection/speaker_setup_controller.dart:176-220`; `lib/platform/audio_connection_adapter.dart:146-185` | Client implemented. System-native access/settings behavior still needs each target's validation. |
| Find compatible service and select same connected audio speaker | `O:J/ConnectionActivity.kt:332-360,402-446` | `N:lib/connection/speaker_setup_controller.dart:39-54,224-242`; `lib/connection/universal_ble_transport.dart:95-132` | Android/Windows identity adapters implemented; Apple/Linux use explicit audio confirmation, with missing native identity verification disclosed separately below. |
| Saved/sole-device automatic connect | `O:J/ConnectionActivity.kt:378-398,434-438` | Only audio identity auto-selection at `N:lib/connection/speaker_setup_controller.dart:90-100`; manual `connectControls:224` | Convenience omitted; finding 2. |
| Change speaker from Settings | `O:J/SettingsActivity.kt:90-94` | Speaker → Choose a speaker, `N:lib/app.dart:1019-1022,1146-1152,1204-1227` | Client implemented. |
| Sound/LED navigation, connection name/status, codec badge | `O:J/MainActivityRedesign.kt:361-409,536-537,1749-1763` | Sound/Light/Speaker shell `N:lib/app.dart:370-524`; Speaker summary `984-1014`; Audio quality `1030-1034` | Information reorganized by approved design; not an omission. Codec details have their own route instead of a main-screen badge. |
| Adjust bass/mid/treble, wire values -12..12 | `O:J/MainActivityRedesign.kt:539-542,594-613,1856-1882` | Sound → Equalizer `N:lib/app.dart:823-863`; `lib/domain/speaker_state.dart:13-24`; `lib/connection/speaker_session.dart:353-357`; `lib/protocol/speaker_protocol.dart:39-40` | Client implemented. Applied-gain labels intentionally distinguish wire values from processing scale. |
| Select Balanced, Deep Bass, Vocals, Bright, Punchy, Warm, Studio, Club, Gaming; expand list | `O:J/MainActivityRedesign.kt:676-710,1134-1155`; active layout `O:R/section_eq_presets.xml:14-300` | `N:lib/persistence/profile_store.dart:36-56`; Sound presets `lib/app.dart:659-672,705-821` | All nine active curves retained with integer conversion. Cinema/Podcast/Late Night also exist in Flutter; their legacy MainActivity provenance does not prove they were active redesign actions. |
| Recall/save/overwrite Custom 1 and 2 | `O:J/MainActivityRedesign.kt:713-721,1167-1214` | Saved presets/create/save `N:lib/app.dart:334-367,847-895`; manage/replace `927-981`; `lib/persistence/profile_store.dart:59-105` | Client implemented with named multiple saved presets instead of two fixed slots. Legacy import route `lib/features/presets/preset_import.dart` retains a migration path. Changing storage shape alone is not a feature loss. |
| Bass boost; bypass/full-range flag; channel/output flip | `O:J/SettingsActivity.kt:132-183`; callbacks `O:J/MainActivityRedesign.kt:446-450,2477-2486` | Sound options `N:lib/features/sound/widgets/sound_options_panel.dart:13-103`; `lib/app.dart:239-250`; `lib/connection/speaker_session.dart:375-382` | All three protocol bits implemented. Source-correct naming clarifies the crossover/full-range meaning. Swap is remembered and disabled while full range is selected; this does not erase the stored flag. |
| Choose all 22 effects (IDs 0..21) | `O:J/MainActivityRedesign.kt:64-86,838-900` | Light gallery/names `N:lib/features/light/light_screen.dart:141-164,519-521,794-903`; `lib/protocol/speaker_protocol.dart:46-47` | Client implemented with owned native source renderer, not proof of physical LEDs. |
| Quick Spectrum/Beat/Bass/Rainbow/Ambient selection | `O:J/MainActivityRedesign.kt:1004-1023` | Light quick chips 0/1/21 at `N:lib/features/light/light_screen.dart:762-779`; other effects remain in gallery | All choices reachable; reduced shortcuts are a focused-layout difference, not a lost control. |
| Full dropdown Off sentinel (255) | `O:J/MainActivityRedesign.kt:838-842,870-900,1885-1891` | `N:lib/domain/speaker_state.dart:61` rejects it; UI only lists 0..21 | Compatibility omitted; finding 1. |
| Lights off via brightness zero; brightness restoration | `O:J/MainActivityRedesign.kt:1024-1039,1041-1065` | `N:lib/features/light/light_screen.dart:705-741` | Client implemented. |
| Brightness 0..100 | `O:J/MainActivityRedesign.kt:544-560,1895-1904` | Light brightness `N:lib/features/light/light_screen.dart:736-741`; `lib/domain/speaker_state.dart:62`; `lib/connection/speaker_session.dart:359-371` | Client implemented using full SET_LED. Different command granularity alone is not a confirmed functional omission. |
| Ambient speed, two RGB colors, five gradients | `O:R/section_led_effects.xml:345-381`; `O:J/MainActivityRedesign.kt:563-591,905-951,960-993` | Customize Ambient `N:lib/features/light/light_screen.dart:905-990,1206-1292`; `lib/domain/speaker_state.dart:60-78` | Client implemented. Original speed is inside the hidden Ambient container; there was no active all-effects speed UI to lose. |
| Restore Ambient customization when changing effects | `O:J/MainActivityRedesign.kt:885-900,1080-1110` | `N:lib/features/light/light_screen.dart:519-521` copies only the effect, retaining speed/colors/gradient in current settings | User customization retained; original saved-Ambient fields are memory-local, not a durable preset file. Device-originated updates remain authoritative. |
| Live three-band meter and external EQ/status synchronization | `O:J/MainActivityRedesign.kt:1418-1457,1597-1664,1669-1683` | `N:lib/protocol/speaker_protocol.dart:86-168`; `lib/connection/speaker_session.dart:280-349`; `lib/features/light/meter_preview.dart:33-48`; Sound meter in `lib/app.dart:577-657` | Client implemented. Original dB-labelled integer display is not a calibrated measurement guarantee. Real music, stale/lost packets, and renderer response remain physical gates. |
| Rename speaker | `O:J/SettingsActivity.kt:97-116`; `O:J/MainActivityRedesign.kt:453-458,2470-2474` | Speaker → Speaker name `N:lib/app.dart:1057-1063,1274-1300`; `lib/connection/speaker_session.dart:386-390`; `lib/protocol/speaker_protocol.dart:49-54` | Client implemented, rejects invalid/overlong UTF-8 instead of silently truncating. |
| View device name, firmware, connection | `O:J/SettingsActivity.kt:120-122,252-270`; `O:J/DeviceInfoBottomSheet.kt:449-478` | Speaker summary `N:lib/app.dart:984-1014` | Client implemented; unavailable firmware is shown honestly. |
| Read negotiated codec, rate, depth, channels, quality | `O:J/CodecSettingsActivity.kt:293-337`; `O:J/DeviceInfoBottomSheet.kt:449-478` | Speaker → Audio quality `N:lib/app.dart:1101-1113`; `lib/features/codec/audio_quality_screen.dart:233-283`; `lib/features/codec/codec_controller.dart` | Android client/bridge implemented. Non-Android reports OS-managed capability; no unsupported codec or actual bitrate is invented. |
| Request companion association | `O:J/CodecSettingsActivity.kt:199-254`; `O:J/MainActivityRedesign.kt:2219-2325` | Audio quality access action `N:lib/features/codec/audio_quality_screen.dart:459-464`; `lib/features/codec/codec_adapter.dart:118-120`; native `android/app/src/main/kotlin/com/bdkaudio/bdk_audio/CodecBridge.kt` | Android implementation exists; association success does not itself prove codec API access. Native/OEM validation pending. |
| Select codec, sample rate, bit depth and apply/read back | `O:J/CodecSettingsActivity.kt:344-427,459-514` | `N:lib/features/codec/audio_quality_screen.dart:296-391`; `lib/features/codec/codec_controller.dart:115` onward; `lib/features/codec/codec_adapter.dart:95-110`; native CodecBridge | Client implemented with current capabilities and negotiated confirmation. Original guessed fallback options/optimistic success are not working capabilities that must be replicated. |
| Global notification-sound mute | `O:J/DeviceInfoBottomSheet.kt:314-325`; `O:J/MainActivityRedesign.kt:2491-2500` | Speaker sounds → Play sounds `N:lib/features/sounds/speaker_sounds_screen.dart:240-262`; `lib/features/transfers/sound_transfer_controller.dart:93-126` | Client implemented; preview builds deliberately disable remote changes. |
| Import/convert/upload startup, pairing, connected, maximum-volume sound | `O:J/DeviceInfoBottomSheet.kt:149-218,330-351`; `O:J/AudioConverter.kt:21-29,42-145,189-246`; `O:J/MainActivityRedesign.kt:2514-2653` | `N:lib/features/sounds/speaker_sounds_screen.dart:12-17,162-190,449-474`; `lib/features/sounds/sound_import_io.dart:68-77`; `lib/features/sounds/sound_import_controller.dart:124-245`; `lib/features/transfers/sound_transfer_controller.dart:41-83` | All four slots implemented, including volume-limit slot. Android keeps an audio MIME picker/native decoder route. Accepted formats must still be validated per native platform; Linux's disclosed smaller decoder set is not a missing Android listener. |
| Delete a custom sound; display installed-slot/mute flags | `O:J/DeviceInfoBottomSheet.kt:354-445`; `O:J/MainActivityRedesign.kt:2503-2510` | `N:lib/features/sounds/speaker_sounds_screen.dart:310-317,477-496,817-837`; `lib/features/transfers/sound_transfer_controller.dart:87-126` | Client implemented with explicit remove action and status confirmation instead of undiscoverable long press. |
| Firmware update screen/current version, check hosted update, download/decrypt/upload | `O:J/SettingsActivity.kt:186-191`; `O:J/OtaActivity.kt:101-177,216-337`; `O:J/OtaDownloader.kt:25-41,61-80,198-220` | Speaker → Firmware update `N:lib/app.dart:1116-1143`; `lib/features/updates/firmware_update_screen.dart:222-225,333-350`; `lib/features/updates/ota_transfer_controller.dart:73` onward | Local raw/encrypted image import and app transfer controller implemented. Hosted source is disabled honestly; original endpoint/key were placeholders, not a working release channel. See below. |
| App info, installed version, creator credit | `O:J/SettingsActivity.kt:194-199`; `O:J/AppInfoBottomSheet.kt:25-43`; `O:R/fragment_app_info.xml:58-113` | No corresponding route in `N:lib/app.dart:984-1073` | Omitted; finding 3. |

## Literal preset parity follow-up

An additional read-only comparison checked literal vectors rather than only
route presence. In this checkout the Flutter definitions are
`N:lib/persistence/profile_store.dart:36-56`; there is no `sound_profiles.dart`.
All **nine active redesigned presets match** the corresponding Flutter values.
Original literals are `O:J/MainActivityRedesign.kt:676-685`, dispatched at
lines 688-695. Original conversion is `(value - 50) * 12 / 50`, using Kotlin
integer division towards zero, at lines 1139-1142. Flutter uses the same
conversion with Dart `~/` at `N:lib/persistence/profile_store.dart:21,54`.

| Active original name | Flutter name | Both source levels (bass, mid, treble) | Both wire EQ gains (bass, mid, treble) |
|---|---|---|---|
| Balanced | Balanced | 50, 50, 50 | 0, 0, 0 |
| Deep Bass | Deep Bass | 85, 45, 40 | 8, -1, -2 |
| Vocals | Clear Vocals | 40, 70, 55 | -2, 4, 1 |
| Bright | Bright & Clear | 45, 55, 80 | -1, 1, 7 |
| Punchy | Punchy | 75, 40, 70 | 6, -2, 4 |
| Warm | Warm | 65, 55, 35 | 3, 1, -3 |
| Studio | Studio | 50, 52, 50 | 0, 0, 0 |
| Club | Club | 80, 45, 65 | 7, -1, 3 |
| Gaming | Gaming | 75, 55, 70 | 6, 1, 4 |

The two naming differences expand the original short labels; they do not alter
the curve. Studio's small mid-band source offset rounds to zero in **both**
applications, so its identical wire curve to Balanced is inherited behavior,
not a Flutter regression. Gaming's original redesign index is 8 while the
Flutter/legacy twelve-item list places it after Cinema and Podcast. These
buttons send explicit EQ gains (`O:J/MainActivityRedesign.kt:1155,1856-1882`;
`N:lib/connection/speaker_session.dart:353-357`), so list index does not change
the wire preset selection.

Flutter's additional Cinema, Podcast and Late Night presets retain the legacy
MainActivity literals (`O:J/MainActivity.kt:961-971`;
`N:lib/persistence/profile_store.dart:46-49`). No active redesign preset is
missing, and no same-named curve differs. A bounded PowerShell comparison of
the nine literal rows, explicit name aliases, and truncation-towards-zero gains
reported nine matches and twelve Flutter built-ins. This was a source check,
not native audio processing or physical validation, and changed no app code.

## Protocol coverage versus actual user actions

Original shared command definitions are at `O:S/BleUnifiedProtocol.kt:27-47`.
Flutter implements EQ `01`, control `03`, name `04`, full lighting `05`, status
request `f0` in `N:lib/protocol/speaker_protocol.dart:39-54`; sound `10..14` in
`N:lib/features/transfers/sound_transfer_packets.dart:27-56`; OTA `20..23` in
`N:lib/features/updates/ota_transfer_packets.dart`. Status, ACK/error, sound/OTA,
PONG and full-status parsing exist at `N:lib/protocol/speaker_protocol.dart:97-158`.

The original separate LED-effect `06` and brightness `07` builders have no
standalone Flutter equivalent; Flutter sets their fields with `05`. The
preserved action is choosing/changing lighting, except the ID255 incompatibility
above. A missing builder alone is not evidence of a lost user feature.
Original `SET_EQ_PRESET 02` and `PING ff` are shared helpers, but no active
redesign user listener invokes them; EQ preset buttons send explicit EQ values.
They must not be counted as missing original user actions.

The active redesign requires the unified service/characteristics at
`O:J/MainActivityRedesign.kt:1286-1335`. Legacy MainActivity's additional old
characteristics are not proof that the active shipped route supported legacy
firmware. The Flutter unified-service requirement is therefore not itself an
identified parity regression.

## Honest capability and validation boundaries

`N:docs/platform-release-matrix.md` is the existing source of recorded native
status, not a result produced by this audit. It explicitly retains these gates:

| Target | Client implementation/capability status at audited source | Evidence still required |
|---|---|---|
| Android | Native codec bridge, A2DP identity gate, universal BLE transport, decoder and shared controls are implemented. OS permission/OEM restrictions can still make codec APIs unavailable. | Actual connected music, live/stale meters, codec capability/readback and reconnect; physical controls/sounds/OTA within future authorized scope; supported OS matrix and release signing. |
| Windows | Native audio identity mapping and shared BLE/control/import UI are implemented. Manual codec control is reported OS-managed by `SystemCodecAdapter`. | Physical connected Bluetooth sink mapping/BLE session, native decoder/input-format/runtime tests, final native GUI/accessibility, signed packaging. |
| iPhone/iPad | Target shell and shared client code prepared. Audio pairing uses explicit user confirmation because no verified same-device identity bridge exists; Android codec methods are unavailable. | Native Apple build, signing, physical iPhone/iPad, audio/BLE identity, permissions/background, imports/decoder and layout/lifecycle. |
| macOS | Shell/entitlements and shared client code prepared. Audio identity remains explicit confirmation; Android codec methods unavailable. | Native Intel/Apple Silicon build/runtime, decoder/file scope/BLE, signing/notarization and distribution. |
| Linux | Shell and owned portable sources prepared. Audio identity remains explicit confirmation; Android codec methods unavailable. Decoder picker is WAV/MP3/FLAC only at `N:lib/features/sounds/sound_import_io.dart:75-77`. | Native build and desktop runtime, dependencies, BlueZ/audio integration, actual imports/playback/BLE and packaging. |

The non-Android codec policy is directly visible in
`N:lib/features/codec/codec_adapter.dart:35-43,77-88`. Manual audio confirmation
is visible in `N:lib/platform/audio_connection_adapter.dart:44-45` and
`lib/connection/speaker_setup_controller.dart:39-54,170-172`. A client fallback
does not verify the original same-speaker identity guarantee on Apple/Linux.
Those are unfinished platform integration/release gates, distinct from missing
original Android control actions. No current physical codec capability was
queried or inferred by this audit, including vendor/LHDC availability.

The user reported no connected music. All native previews remain
`BDK_PREVIEW_ONLY=true`; this audit did not change that state or run a device.
Fixture/source/native-isolated tests cannot satisfy actual music, physical
speaker transfers, Apple/Linux runtime or signing gates. Production completion
remains open even after the source omissions are repaired.

## Hosted OTA is an original placeholder, not a lost working channel

`O:J/OtaDownloader.kt:26` contains `YOUR_LATEST_TXT_FILE_ID_HERE` and lines 30-39
contain a zero-filled AES key. The active OtaActivity check/download flow thus
does not establish a usable supplied update publisher. Flutter's local
`.bin`/`.enc` importer and explicit key input are concrete app-side capability;
the absence of a hosted update service is not loss of a working original URL.
`N:docs/migration/ota-app-source-provenance.md` records the original hashes,
packet semantics and limitations. Neither local decryption nor version readback
authenticates a publisher or proves flash contents. A trusted release channel
and signed application distribution remain production work, not completed by
the original placeholders.

## Original snapshot fingerprints

The original directory is not Git. These SHA256 readings pin the critical
application snapshot inspected here, without modifying it:

| Original relative file | SHA256 |
|---|---|
| `app/src/main/AndroidManifest.xml` | `FC3BB440E9B4613DBEA51B53ADFBB3676E0617DA978FC64F2ED9B78D8778542A` |
| `J/ConnectionActivity.kt` | `0BB5FA997F14DDE34CDEB0D078431A019384FB6E7155ABAC1222578F2445CD2A` |
| `J/MainActivityRedesign.kt` | `CFB353717F3A163C6D5ED33A357298FF4A0D138EE6262259C84FA2FB53EF7930` |
| `J/SettingsActivity.kt` | `5CC14179B5706B252B27CE33EF80D5CCD4FDA4607839FCE0FAA5AA1FDF3554F6` |
| `J/CodecSettingsActivity.kt` | `0274EF3F1AB107788D6882EB75017627F0378622D020AD5F0019BBB622EA0537` |
| `J/DeviceInfoBottomSheet.kt` | `8E2DE6BB8824F9B572E60F283FD2D95476B90EF88F216585023B656F2EEA6DAA` |
| `J/OtaDownloader.kt` | `0FE977755DCE1ED9637E76AF225CAAD39A374274DE12DA352E95BB4A2E990D5E` |
