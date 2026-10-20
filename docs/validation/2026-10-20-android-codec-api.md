# Android bitrate API research and Redmagic observations

The user requested deeper Android API/profile research after bitrate controls
were missing for the current LHDC V5 connection. No ESP32 source, firmware,
serial or flash operation was used.

## Android entry point

The relevant profile is Bluetooth A2DP. Its profile proxy provides codec status
and a codec preference submission path. Current AOSP marks the getter/setter as
hidden/System APIs; service-side access requires Bluetooth connect permission
and either a companion-device association or privileged access. An association
does not guarantee hidden-API availability on every OS. The app uses normal
permissions and never enables a hidden-API exemption or privileged permission.

- [AOSP BluetoothA2dp contract](https://android.googlesource.com/platform/packages/modules/Bluetooth/+/refs/heads/main/framework/java/android/bluetooth/BluetoothA2dp.java)
- [AOSP service checks](https://android.googlesource.com/platform/packages/modules/Bluetooth/+/refs/heads/main/android/app/src/com/android/bluetooth/a2dp/A2dpService.java)
- [Public codec status fields](https://developer.android.com/reference/android/bluetooth/BluetoothCodecStatus)
- [Extended codec identity](https://developer.android.com/reference/android/bluetooth/BluetoothCodecType#getCodecId())

There is no general numeric Bluetooth bitrate property/setter in this config
contract. The four codec-specific fields carry vendor-defined preferences. The
normal A2DP methods exposed on this phone include getCodecStatus and
setCodecConfigPreference; the finite method inventory exposed no LHDC extended
profile API. This is an observation about this installed OS, not all Android.

## Read-only physical probe

The separate CodecProbe instrumentation APK was built from the project's Java
source, signed with the same development certificate and run against the
installed BDK package on serial 9125299103B7 (nubia NX809J). It uses the target
app's permission/attribution context without any exemption flags. It selects
exactly one connected BDK SPEAKER, prints no Bluetooth addresses, and performs
no setter, pairing, connection or route operation. Instrumentation can restart
the app process; its BLE session reconnects afterward.

Artifacts: artifacts/android-ship-20261020/codec-api-probe/read-only-result.json
and read-only-result.txt. The current config was:

| Field | Observed value |
|---|---|
| Reported codec | LHDC V5 |
| Legacy codec type | 15 (OEM-specific; not a portable LHDC identifier) |
| Sample rate | 192 kHz (mask 32) |
| Input depth / channels | 24-bit / stereo |
| codecSpecific1 | 32776 = 0x8008 |
| codecSpecific2 | 0 |
| codecSpecific3 | 1543503872 = 0x5C000000 |
| codecSpecific4 | 0 |
| Reported extended codec ID | 0x35053AFF |

Android's current documented LHDC V5 identity is 0x4C35053AFF; this OEM's returned
value differs. Do not claim the two are equal or silently reinterpret the value.
The reported name and both vendor field tags match the pinned V5 contract below.
Six codec capability rows were observed; their presence does not prove that all
preferences have been applied successfully.

## Verified LHDC V5 quality contract

Savitech's official integration at 3ac44e21e92983bb800eee8cb9d938522e3852d2 defines
cs1 command mask 0xC000, quality tag 0x8000 and low-eight-bit quality index.
Indices 0..8 map to nominal targets 64,160,192,256,320,400,500,900,1000 kbps;
index 9 is adaptive. Its helper's 9999999 value is a sentinel, not a bitrate.
The V5 cs3 feature tag is 0x5C000000 under mask 0xFF000000.

- [Quality constants](https://gitlab.com/savitech-lhdc/savitech-lhdc-codec-aosp-13.0.0_r2/-/raw/3ac44e21e92983bb800eee8cb9d938522e3852d2/src/packages/modules/Bluetooth/system/stack/include/a2dp_vendor_lhdc_constants.h)
- [V5 field definitions](https://gitlab.com/savitech-lhdc/savitech-lhdc-codec-aosp-13.0.0_r2/-/raw/3ac44e21e92983bb800eee8cb9d938522e3852d2/src/packages/modules/Bluetooth/system/stack/include/a2dp_vendor_lhdcv5_constants.h)
- [V5 negotiation and limits](https://gitlab.com/savitech-lhdc/savitech-lhdc-codec-aosp-13.0.0_r2/-/raw/3ac44e21e92983bb800eee8cb9d938522e3852d2/src/packages/modules/Bluetooth/system/stack/a2dp/a2dp_vendor_lhdcv5.cc)

Thus 0x8008 identifies a configured 1000 kbps target on the observed connection.
It does not measure encoded bytes, RF throughput or acoustic output.

The vendor code clamps fixed requests to peer min/max capabilities. At 96/192 kHz
it raises fixed requests below 256 kbps; at 44.1/48 kHz it lowers fixed requests
above 900 kbps. Lossless mode forces adaptive. Peer min/max codec information
elements are not exposed by this generic Android capability snapshot, so offer
source-valid requests and report a clamped readback honestly.

Only the known quality index may change; preserve cs2..4 and every other cs1 bit.
Require fresh same-device capabilities and exact quality/format readback after
submission. Unknown names/tags/indices remain device-managed.

The vendor encoder's internal lhdcv5BT_get_bitrate needs an encoder handle; it is
not an ordinary application config getter. No actual live bitrate is claimed.
[Vendor encoder source](https://gitlab.com/savitech-lhdc/savitech-lhdc-codec-aosp-13.0.0_r2/-/raw/3ac44e21e92983bb800eee8cb9d938522e3852d2/src/packages/modules/Bluetooth/system/stack/a2dp/a2dp_vendor_lhdcv5_encoder.cc)

## Finite physical preference check

The separate LHDCPreferenceCheck entry used normal target-app access, required
the exact initial tuple above, requested cs1=0x8007 once, and then restored the
captured original config in a finally path. Both stages rechecked the same
connected identity and all non-quality fields before the setter. Native calls
were serialized with bounded result polling and explicit unknown-outcome state.

The phone returned cs1=32775 (900 kbps target), then cs1=32776 (1000 kbps target).
Type 15, priority 1000000, rate 32, depth 2, stereo, cs2=0, cs3=0x5C000000,
cs4=0 and the OEM extended identity/name stayed identical. The captured restored
object equals the before object, including reported text; errors were empty.

Artifacts: codec-api-probe-v2/preference-check-result.txt and .json inside the
same Android shipping artifact directory. The receipt has
changedPreferenceVerified=true, restoreVerified=true, success=true, and a null
measuredBitrateKbps. The Android A2DP quality submission/readback path therefore
worked on this exact Redmagic build without Developer Options or firmware
changes. This does not establish actual encoded throughput, acoustics, all
quality modes, all Android/OEM versions or the later Flutter UI action path.
