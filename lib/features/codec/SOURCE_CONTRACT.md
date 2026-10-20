# Android codec quality contract

The original LDAC checkpoint added source-backed quality preferences. It does not expose
measured transmission bitrate or establish that this phone/OEM permits a normal
app to apply a codec preference. No native setter, pairing, playback, audio-route,
Bluetooth-setting or speaker operation was performed during that checkpoint.

## Verified source meanings

The Android 16 Settings controller writes `codecSpecific1 = 1000 + index`. The
Bluetooth encoder interprets these canonical quality codes:

| Code | Quality setting | Nominal target at 44.1 / 88.2 kHz | Nominal target at 48 / 96 kHz |
|---|---|---|---|
| 1000 | High quality | 909 kbps | 990 kbps |
| 1001 | Balanced | 606 kbps | 660 kbps |
| 1002 | Connection priority | 303 kbps | 330 kbps |
| 1003 | Adaptive | No fixed target reported | No fixed target reported |

These rates refer to the Bluetooth codec's configured sample rate, not the
selected media file's sample rate. Unknown/default quality codes and unknown or
multiple rate bits yield no derived nominal target. The AOSP encoder can fall
back from adaptive to balanced if its ABR library is unavailable; it also adapts
quality from its transmit queue. Therefore fresh `BluetoothCodecConfig` readback
confirms the configured quality setting, not the encoder's instantaneous bitrate.

Actual bitrate is separate native encoder state (`ldacBT_get_bitrate`), printed
by its debug dump. It is absent from the normal app's `BluetoothCodecConfig`
contract. The UI explicitly labels fixed derived values “Nominal target” and
reports actual bitrate as unavailable to this app.

Primary sources were fetched at immutable revisions and their contents matched
the initially inspected Android 16 branch files. Hashes and exact URLs are in
`android/app/src/test/kotlin/com/bdkaudio/bdk_audio/CodecQualitySources.json`:

- [Settings quality controller](https://android.googlesource.com/platform/packages/apps/Settings/+/0fb38ed81e9b49d5da4be8f50d9d69865c1192e8/src/com/android/settings/development/bluetooth/BluetoothQualityDialogPreferenceController.java), lines 59–90.
- [LDAC nominal rate helper](https://android.googlesource.com/platform/packages/modules/Bluetooth/+/4b73ee6039271ffbf71ebdc8c109fc98eac8e137/system/stack/a2dp/a2dp_vendor_ldac.cc), lines 289–321.
- [LDAC encoder](https://android.googlesource.com/platform/packages/modules/Bluetooth/+/4b73ee6039271ffbf71ebdc8c109fc98eac8e137/system/stack/a2dp/a2dp_vendor_ldac_encoder.cc), quality selection/fallback lines 217–258, adaptation lines 350–360, actual bitrate debug dump lines 567–585.
- [LDAC constants](https://android.googlesource.com/platform/packages/modules/Bluetooth/+/4b73ee6039271ffbf71ebdc8c109fc98eac8e137/system/stack/include/a2dp_vendor_ldac_constants.h), lines 25–30.
- [Framework config fields](https://android.googlesource.com/platform/packages/modules/Bluetooth/+/4b73ee6039271ffbf71ebdc8c109fc98eac8e137/framework/java/android/bluetooth/BluetoothCodecConfig.java).

The supplied original Android `CodecManager.kt` and `CodecSettingsActivity.kt`
were inspected read-only. Their generic opaque `codecSpecific1` setter and
two-step submission are not proof of a particular quality/bitrate mapping or
successful negotiated readback; the new bridge retains one checked submission.

## Capability and confirmation policy

- Quality choices require a recognized current LDAC code (default `0` or explicit
  `1000`–`1003`), one explicit supported
  Bluetooth sample rate, and a matching selectable capability row. No quality
  mask is invented: AOSP exposes all four LDAC modes for this recognized contract.
- Local LDAC/LHDC quality drafts use the last accepted capability contract and
  remain editable after the five-second observation window. Current telemetry
  is marked stale. Every apply rechecks fresh same-device capabilities and the
  recognized quality contract before submitting; editing itself never writes.
- A pending LDAC quality remains a draft. Confirmation requires fresh readback
  after submission from the same audio identity, matching codec, rate, depth,
  channels **and** the requested quality code. Submission alone is insufficient.
- Native validation preserves all other same-codec opaque fields. Switching
  codec uses default zero fields. It rejects arbitrary `cs2`–`cs4` changes and
  refuses unknown `cs1` quality mutations. Recognized LDAC codes and the narrow
  identified LHDC V5 low-byte contract described below are the mutable fields.
- The existing serialized native lease, cancellation, timeout, CDM consent,
  connection epochs and broadcast invalidation remain in force. There is no
  hidden-API exemption, privileged permission, settings write or route change.
- Demo/preview-disabled controllers refuse quality changes. The method-channel
  schema and audio connection snapshot contract are unchanged.

## Earlier LHDC investigation and physical validation limits

Savitech's official AOSP 13 integration at revision
`3ac44e21e92983bb800eee8cb9d938522e3852d2` uses a distinct vendor command contract:
`A2DP_LHDC_VENDOR_CMD_MASK=0xC000`, quality magic `0x8000`, quality mask `0xFF`,
and version-dependent quality indices. See the [vendor constants](https://gitlab.com/savitech-lhdc/savitech-lhdc-codec-aosp-13.0.0_r2/-/blob/3ac44e21e92983bb800eee8cb9d938522e3852d2/src/packages/modules/Bluetooth/system/stack/include/a2dp_vendor_lhdc_constants.h)
and [LHDC V5 integration](https://gitlab.com/savitech-lhdc/savitech-lhdc-codec-aosp-13.0.0_r2/-/blob/3ac44e21e92983bb800eee8cb9d938522e3852d2/src/packages/modules/Bluetooth/system/stack/a2dp/a2dp_vendor_lhdcv5.cc).
This source alone did not identify the Redmagic's installed vendor codec IDs,
version, offload path, command layout or readable live fields. At that earlier
checkpoint no LHDC quality control or nominal bitrate derivation was enabled.

The only phone query at that checkpoint was a read-only `dumpsys bluetooth_manager` pipeline on
explicit serial `9125299103B7`, filtered on-device to codec configuration and LDAC
quality/bitrate lines, capped at twenty lines. It returned no codec observation.
That is absence of evidence, not proof that the phone lacks these capabilities.
No private app/music data was read. Actual codec application, vendor mapping,
live bitrate and end-to-end release validation remain open for a separately
authorized audio connection test.

## Checks

54 Dart/model/controller/widget tests and ten standalone JVM parsing/policy/cache
checks passed. New regressions first failed for the missing quality UI and
accepted unknown LDAC quality request, then passed. Coverage includes cadence
targets, nullable/unknown states, capability rows, opaque field preservation,
stale and wrong-quality readback, cancellation/lease ownership, expiry/disposal,
preview mode and 280-pixel / 2x text rendering. Targeted codec analysis is clean.
Full-app integration checks belong to the parent task while its other features
are being edited concurrently.

## Android completion recovery changes, 2026-10-20

Initial A2DP profile acquisition is asynchronous. The controller now retries only
the `initializing` state within one native-call deadline, with cancellation and
one serialized native lease. Permission, identity, association and connection
checks remain required.

After a checked submission, the native bridge invalidates previous broadcasts.
On an OEM that restricts direct reads, `apiUnavailable` for the same selected
audio identity can mean the replacement broadcast has not arrived. Verification
now retries that transient state within the existing verification deadline. It
does not retry a lost permission, disconnected device, missing/different audio
identity, or unrecognized access state, and never confirms absent telemetry.

The current connection card keeps Android's observed codec, Bluetooth sample
rate, bit depth and channel mode separate from the preference draft. It displays
the direct-query/broadcast source and five-second freshness window. An owned
expiry timer marks old telemetry as out of date for every codec, including those
without recognized LDAC quality. Refresh and app-resume observation remain
explicit; no continuous polling or route mutation is introduced. Android
restriction, read-only and error states offer a system Bluetooth-settings action;
preview/demo controls keep that action disabled.

The explicit bitrate label is `Bluetooth bitrate: Not reported by Android.` The
recognized LDAC nominal target remains separately labelled and is not represented
as actual encoded/transmitted bitrate. That recovery change introduced no vendor
quality contract; the subsequent identified LHDC V5 path is documented below.

The parent observed the new regressions fail against the prior controller/UI in
`artifacts/android-ship-20261020/features-red.log`, then all 66 focused Dart
model/adapter/controller/widget checks pass in `codec-green.log`. The larger
current card exposed an existing preview-mode test's offscreen tap; that test
now scrolls the control into view before tapping, preserving hit-test warnings.
Final analysis, suite checks and phone validation belong to the parent
integration run. Source implementation and fake-adapter readback are not evidence
that the phone accepted a codec setter or changed its audio stream.

## LDAC bitrate selection from device default

`codecSpecific1=0` is a source-defined LDAC device default. The pinned Settings
controller initializes this field to zero (line 60), and the pinned encoder
reads `persist.bluetooth.a2dp_ldac.default_quality_mode` with an ABR fallback
when the field is zero (lines 219–227). It therefore cannot identify a fixed
current quality or bitrate. A zero observation now permits an explicit choice
of the four known `1000`–`1003` preferences; unknown nonzero codes still disable
these choices. This policy applies only to identified LDAC codec type `4`, a
supported single rate/depth/channel combination, and a fresh same-device read.

The `Bitrate / quality` selector shows the three source-defined nominal targets
for the draft Bluetooth sample rate (990/660/330 or 909/606/303 kbps) and labels
Adaptive as variable bitrate. A default observation starts with a disabled
`Device default · Choose a bitrate` placeholder; it does not silently select
High or Adaptive. Selecting a target changes the draft only. Confirmation still
requires fresh post-submission readback of the explicit requested quality code,
and the native validator preserves opaque `codecSpecific2`–`codecSpecific4`.

Model/controller/widget regressions and a new standalone native policy check
first failed on the missing default-zero contract and bitrate-labelled UI in
the parent's `bitrate-default-red.log` and `codec-native-red.log`. Their GREEN
run and subsequent phone verification belong to the parent integration task.

A deterministic fake-time regression also caught a queued-read deadline race:
after a refresh timeout, its operation remained eligible to start a delayed
native read. Failure now cancels that operation, preventing queued obsolete
work while the real `_nativeTail` lease still waits for already-started calls.
The parent recorded the expected pre-fix failure in
`handoff-codec-deadline-2.log`; the final integration run owns GREEN evidence.

Final review also added an explicit LDAC codec-type guard to the default-zero
policy. A zero opaque field on SBC, AAC or an unidentified vendor codec does not
authorize LDAC quality choices, even if LDAC appears in selectable capabilities.
The corresponding model regression failed first in `ldac-identity-red.log`.

## Identified Redmagic LHDC V5 contract, 2026-10-20

A normal-app, read-only instrumentation probe in
`artifacts/android-ship-20261020/codec-api-probe/read-only-result.json` reported
active codec type `15`, name `LHDC V5`, 192 kHz, 24-bit stereo,
`cs1=0x8008`, `cs2=0`, `cs3=0x5C000000`, `cs4=0`. Its selectable row reported
rate mask `43`, depth mask `3`, stereo, and zero codec-specific fields. These
fields identify the pinned Savitech V5 quality contract. They do not establish
that a setter request was accepted or measure an encoder/RF bitrate.

The probe's extended codec ID was `0x35053AFF`. The official Android identifier
is `0x4C35053AFF`; this OEM reported the truncated value. Recognition therefore
does not rely on this identifier or on the name alone. It requires a vendor
codec type, the normalized `LHDC V5` name, `cs1 & 0xC000 == 0x8000` with index
`cs1 & 0xFF` in `0..9`, `cs3 & 0xFF000000 == 0x5C000000`, and one recognized
Bluetooth rate. Quality requests additionally require a matching current
selectable rate/depth/channel row. Legacy vendor codec index `15` is not assumed
universal.

Indices `0..8` mean requested nominal targets 64, 160, 192, 256, 320, 400, 500,
900 and 1000 kbps; index `9` is adaptive. The source's `9999999` ABR return is a
sentinel, not a measured bitrate. At 96/192 kHz, fixed requests start at 256 kbps;
at 44.1/48 kHz they end at 900 kbps. Lossless feature bits `cs3 & 0x180` restrict
requests to adaptive. Peer minimum/maximum bitrate limits are not exposed in
the generic configuration, so UI options are explicitly requests that Android
or the speaker may clamp/refuse.

Only the low eight bits of an already recognized `cs1` can change:
`newCs1 = (oldCs1 & ~0xFF) | qualityIndex`. Every other `cs1` bit and `cs2`–`cs4`
must remain identical. The same narrow rule is enforced in Dart and native
validation. Existing LDAC APIs remain available alongside `LhdcV5Quality`.
Fresh post-submission identity/format/explicit-quality readback is required;
matching the codec label or receiving a different clamped target is not success.

Current details and the shared strip may display the recognized configured
nominal LHDC target. Actual bitrate remains not reported; its separate native
encoder getter requires an internal handle and is not exposed by the probed
A2DP profile API. No media-file or PCM bitrate is substituted.

The critical V5 constants header is now pinned in `CodecQualitySources.json`:
`a2dp_vendor_lhdcv5_constants.h` at revision
`3ac44e21e92983bb800eee8cb9d938522e3852d2`, SHA256
`1bd4d43c137ba81b5389873cf6c01a311ca12b29558fad551fa5c324145a30d7`.
A fresh official raw download matched the cached bytes. See the
[V5 constants](https://gitlab.com/savitech-lhdc/savitech-lhdc-codec-aosp-13.0.0_r2/-/raw/3ac44e21e92983bb800eee8cb9d938522e3852d2/src/packages/modules/Bluetooth/system/stack/include/a2dp_vendor_lhdcv5_constants.h),
the previously pinned common constants and V5 integration, and
[Android codec identifiers](https://developer.android.com/reference/android/bluetooth/BluetoothCodecType#getCodecId()).

The parent confirmed the expected new Dart and native failures in `lhdc-red.log`
and `lhdc-native-red.log` before this implementation. Current GREEN and physical
setter/readback evidence belong to the parent integration run. The detail screen
does not continuously poll or rebuild a menu to keep a five-second draft lease;
its expiry timer changes only the current-reading freshness display.

Final tuple validation also covers a rate-only request whose `cs1` is unchanged.
A known V5 1000-kbps target cannot be carried implicitly from 192 to 48 kHz.
The controller adjusts the local draft to an explicit allowed target (900 kbps
in that case; Adaptive when lossless requires it) before Apply. Native validation
checks the recognized rate/quality/lossless tuple even without a quality-byte
change, and confirmation compares that explicit adjusted quality. Inconsistent
lossless/fixed-quality observations provide no derived nominal target in either
current details or the shared summary. The parent first observed these edge
failures in `lhdc-edge-red.log` and `lhdc-edge-native-red.log`.

The parent's normal-app API experiment in
`artifacts/android-ship-20261020/codec-api-probe-v2/preference-check-result.json`
confirmed a configured LHDC V5 target change `0x8008` (1000 kbps) to `0x8007`
(900 kbps) and verified restoration to the exact original configuration, with
rate/depth/channels and `cs2`–`cs4` unchanged. This establishes setter and
configuration-readback behavior on this phone/build. The artifact's measured
bitrate is null; it does not establish RF throughput, acoustic output, or final
Flutter UI deployment. Later integration receipts own those separate claims.
