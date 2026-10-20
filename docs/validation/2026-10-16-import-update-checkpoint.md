# Preset import and app-side update checkpoint

This is a development preview. App/phone work only: no ESP32 project changes,
builds, serial access, flashing, or physical update/sound/control commands.

## Implemented

- Both original Android preset schemas, slots1–3; bounded XML/JSON import,
  selection with curve previews, repeat-import deduplication and preservation
  of the current library/favorites/theme. [Migration instructions](../migration/presets.md).
- Queued profile mutations publish only after saving. Invalid/newer existing
  stored data is retained; failed saves keep the previous library.
- Local raw/.enc application-file inspection, explicit AES key for legacy CBC
  containers, segment/checksum/optional SHA256 validation and immutable bytes.
  These checks do not authenticate the publisher or prove board suitability.
- App-side OTA exclusivity, packet bounds, ATT/worker completion distinction,
  bounded abort/disconnect after uncertainty, and a retained transfer receipt.
  A newer synchronized connection to the same speaker plus fresh requested status
  can check its reported version. COMPLETE alone is never an installed-update claim.
  [Protocol provenance and limits](../migration/ota-app-source-provenance.md).
- Focused Firmware update page. Preview builds allow file inspection but disable
  installation and version-query side effects. Online updates remain unavailable
  until a trusted release source is configured.

## Verification

Full Flutter suite: **364 passed**, one optional screenshot test skipped. Analyzer
clean. This includes53 OTA parser/packet/controller checks, focused import/storage/UI
tests and root reconnect integration. The two private-field export-helper checks pass.

Fresh independent review found hidden reconnect navigation and a long duplicate
name that could exceed storage bounds. Both regressions were reproduced failing
and then passing. Reconnect now reaches setup while retaining the receipt; suffix
generation reserves name space without splitting Unicode. No Critical or deferred
Minor finding remains in this checkpoint. The original Minor label was raised
because one valid name could prevent the entire selected batch from importing.

Actual Redmagic0.4.0 checks:

- Native file picker → synthetic raw application envelope → correct metadata and
  file-check status. Install update remained disabled.
- Native file picker → independently encrypted synthetic envelope → explicit public
  fixture key → correct metadata. The password field was removed/cleared afterward,
  and Install update remained disabled. No real firmware was built or deployed.
- Native Android JSON import → both source formats and expected Kotlin-scaled
  sample curves. Samples were previewed without committing fake library entries.
- Original Android app remains installed. Read-only preset export succeeded with
  zero saved custom fields; raw private preferences were not saved or printed.
- Synthetic files were removed from Downloads by exact names after testing.
  The phone was left on explicit Light Demo. Phone captures remain local/ignored.

Android ARM64 and Windows x64 builds pass. Windows0.4.0 compilation is separate from
the earlier actual Windows GUI/audio-import checks; no Windows BLE claim is made.
Apple/Linux native runners and real platform validation remain open.

Installed artifact: `artifacts/bdk-audio-design-preview-0.4.0.apk`,
**90,279,358 bytes**, version0.4.0 / versionCode2007, `BDK_PREVIEW_ONLY=true`.
Local artifact, transferred APK and installed base.apk SHA256 matched:

`f0f4ca5fad8deb2ba5e8d940f6b2f5838b28253eddd16b4d40fd74b8cf2b2764`

Physical update compatibility, reboot behavior, audible speaker playback, live BLE
reaction and actual codec negotiation remain unverified. Hosted releases/signing,
broader platform validation, accessibility/performance and release packaging are
still required for the full goal.
