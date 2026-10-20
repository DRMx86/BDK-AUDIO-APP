# Local image import and OTA controller provenance

2026-10-16. App-only implementation and fake-link tests. No SDK builds, firmware
source edits, flashing, serial access, hardware transfers, ADB, or playback were
performed for this work. Hosted checking, downloads, manifests and signature
verification remain disabled; this module contains no network transport.

## Read-only original application sources

The sibling `BDK-AUDIO-APP-main` source snapshot was inspected without editing:

| Relative source | SHA256 |
| --- | --- |
| `app/src/main/java/com/example/myspeaker/OtaActivity.kt` | `94047125C83E2560974446FF2C7465DE737073EC6D36FCF9951E05AC8421D6ED` |
| `app/src/main/java/com/example/myspeaker/OtaDownloader.kt` | `0FE977755DCE1ED9637E76AF225CAAD39A374274DE12DA352E95BB4A2E990D5E` |
| `app/src/main/java/com/example/myspeaker/BleUnifiedProtocol.kt` | `683088DD5560A4E93434367B5457026FDEA579E305C319B8DA71198018FF702C` |
| `shared/src/commonMain/kotlin/com/example/myspeaker/shared/BleUnifiedProtocol.kt` | `6178869EBCD63E2C8B95510FAE274D2F33759E94C95E951584A95CB2E56DB330` |

The downloader extracts a 16-byte IV, decrypts AES-256-CBC with PKCS padding on
Android, then passes plaintext to OTA. Its source key is a zero-filled placeholder;
the Flutter importer instead requires an explicit 32-byte local key. No key is
bundled or persisted by the image model. Encryption does not authenticate a release.

The shared builders define BEGIN `20 + u32LE size`, DATA `21 + sequence + bytes`,
END `22`, ABORT `23`. Android's DATA counter starts 1 and wraps 255 to 0. The current
source ignores that sequence; it is not a resumable or duplicate-safe protocol.
Original sender sleeps, optimistic completion, and uncertain packet retries are
not retained. App-side behavior also follows [the protocol contract](protocol-contract.md).

## Image envelope

The implementation checks the documented header/segment boundaries, XOR footer,
and optional appended SHA256, following Espressif's [image format](https://docs.espressif.com/projects/esptool/en/release-v4/esp32/advanced-topics/firmware-image-format.html).
It requires the 256-byte application descriptor at the first segment's data start;
field offsets follow [Espressif's descriptor definition](https://github.com/espressif/esp-idf/blob/v5.5/components/esp_app_format/include/esp_app_desc.h).

`FirmwareImage.parse` copies and exposes readonly raw application bytes. The
default expected chip ID is 0 (ESP32); input is capped at 8 MiB raw and the AES
container at that bound plus 32 bytes. These are local allocation bounds, not a
claim about an attached speaker's partition size. Bootloader-like images without
the descriptor, merged files, unexpected/signed trailers, malformed segments,
checksum mismatches and invalid padding reject visibly. No trailer is stripped.

The parser does not establish publisher authenticity, physical model, available
OTA space, eFuse revisions, secure-boot keys, anti-rollback policy, or that the
speaker ultimately wrote the same image. App version and project strings are
untrusted metadata. `isAuthenticated` always returns false.

## Transfer and verification boundaries

Only one session writer and packet are pending. BEGIN requires ATT completion and
OTA_READY; DATA requires ATT completion only because the baseline protocol has no
semantic per-DATA receipt; END requires ATT completion and OTA_COMPLETE. Progress
notifications are informational. `attCompletedBytes` therefore never means
flash-verified bytes. DATA chunks fit the actual characteristic capacity, bounded
at 512 bytes including their 2-byte header. A one-byte tail is repartitioned into
two final packets without changing the image.

Cancellation may send the existing ABORT only while the original lease has no ATT
write pending; it requires matching command ACK plus ATT within a deadline, then
disconnects. Pending/uncertain ATT skips ABORT and disconnects immediately. An
abort ACK is not a rollback guarantee. Timeout, FAILED, disconnect and uncertainty
require a fresh connection epoch and never retransmit or resume an uncertain DATA.
Cleanup is scoped to the original epoch and cannot disconnect a newly selected
speaker. Dispose suppresses late notifications and does not own the shared session.

OTA_COMPLETE plus END ATT records `awaitingRestart`, not updated success. The
controller retains its image/receipt across route closure. Explicit
`verifyAfterReconnect` requires a genuinely newer synchronized connection to the
same device ID and a newly requested FULL_STATUS response plus its ATT completion.
Cached status and unsolicited STATUS_FW do not count. A match verifies only the
reported version string, never image identity or boot health. The expected reported
version can be supplied separately because a legacy BLE version may differ from
the image descriptor. There is no automatic discovery or reconnect.

Untagged READY/COMPLETE cannot prove immunity to arbitrarily delayed,
protocol-violating duplicate responses within an otherwise successful epoch. The
controller rejects idle, wrong-stage and duplicate bursts. Completion is the
source terminal boundary; no reconnect is fabricated to manufacture verification.
The safe baseline session still refuses characteristic capacity below 113 bytes
for unframed full-status sync. W20/MTU23 packetization tests do not claim an actual
small-MTU connection is supported.

## Synthetic fixtures and checks

`test/ota_transfer_fixture.dart` creates an application-like byte envelope with
synthetic descriptor strings and no compiled executable. Its legacy AES fixture
was encrypted independently using .NET `Aes` in CBC/PKCS7 mode, key bytes 00..1f and
IV bytes 10..1f. It is compared byte-for-byte with the Dart fixture after decryption.
These public fixture values are not release keys. No SDK/compiler/device was used.

Recorded RED then GREEN tests cover malformed/encrypted images, packet tails,
sequence wrap, delayed/early semantic replies, ATT races, failure/timeout/abort,
stale links, old cleanup versus a new speaker, explicit version mismatch and
preview guards. Run:

```text
flutter test --no-pub test/firmware_image_test.dart test/ota_transfer_packets_test.dart test/ota_transfer_test.dart
```

At this checkpoint 53 targeted tests pass and targeted Dart analysis is clean.
This is app-side fake/source-fixture evidence, not production or hardware validation.
