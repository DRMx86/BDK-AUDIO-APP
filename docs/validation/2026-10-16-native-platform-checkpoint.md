# Native platform and saved-preset checkpoint

Development preview; the whole cross-platform production goal remains active.
App/phone/host work only. No ESP32 source edits, builds, serial access, flashing,
or physical speaker control, codec setters, sound transfer or update operations.

## Result

- Saved presets have rename, replace-with-current-sound and delete actions.
  Managed cards use a full column on phones so names have room beside the menu.
  Deleting a library entry keeps the current sound. Persistence errors keep
  the previous library. Names and controller lifetime are validated explicitly.
- Queued writes capture the sound at confirmation, and successful persistence
  reconciles the active label against actual gains. A late new save cannot
  overwrite a newer sound's selected label or refresh an exited EQ route.
- Android LDAC quality uses source-backed recognized codes, freshness and
  same-device quality readback. Derived values are labeled nominal targets;
  actual bitrate and unverified vendor/LHDC mappings remain unavailable.
  [Source contract](../../lib/features/codec/SOURCE_CONTRACT.md).
- Windows has a bounded native audio identity adapter and no manual bypass.
  Partial/unsupported drivers receive explicit feedback; missing/failed evidence
  cannot authorize BLE discovery. [Native provenance](../migration/windows-audio-connection-provenance.md).
- Native shell titles/product metadata say BDK Audio. The platform matrix and
  pinned manual preview CI are prepared locally; no CI has been pushed or run.
  [Platform and release matrix](../platform-release-matrix.md).
- Native onscreen inspection caught a source/glow boundary that offscreen
  rendering missed. Layer filtering fixes the visible hard edge while retaining
  square source geometry. [Reproduction and evidence limits](native-diffusion-check.md).

## Checks

Fresh full Flutter suite: **400 passed**, one optional screenshot test skipped.
Analyzer clean. The13 focused preset model/UI checks cover storage failure,
replacement/deletion, delayed queues, wrong active labels, exit/slow-dialog
lifetimes, narrow screens and enlarged text. The new asynchronous regressions
were observed failing before the fixes, then passing.

Root independently reran **14 compiled Windows native checks** and **10 compiled
JVM codec checks**, all passing. The actual read-only Windows diagnostic returned
ready,15 active render endpoints,18 present MEDIA adapters,3 AudioSink adapters,
0 connected Classic Bluetooth devices and0 verified routes, in11ms. This is
empty-state evidence, not a connected physical speaker match.

Fresh independent review identified two Important asynchronous replacement
issues and no Critical/Minor issues. Both were reproduced and fixed in one
regression pass. Native QA additionally exposed the cramped managed-card layout
and delayed new-save route bug, also reproduced and fixed. No re-review success
or exhaustive hardware validation is implied.

Actual Windows app0.5.0 was launched and its pairing, Sound and animated Light
pages inspected. A separate static native GPU probe demonstrated the old hard
edge and the corrected smooth transition. The actual app was rebuilt after the
diagnostic entry point; the probe is not a distributed app target.

Actual Redmagic0.5.0 native QA exercised create/rename/replace/delete using only
the self-created `BDK-QA-05` entry; it was removed afterward. Its Light screen
was captured and inspected, showing smooth diffusion without the rectangular
source cutoff or diagonal blend seam. These were native app checks, not HTML.
Final0.5.1 was installed on Redmagic as versionCode2009 and cold launched.
Local, transferred and installed base.apk SHA256 matched. A self-created long
QA name now fits on one line in a full-width native managed card; that entry
was also deleted afterward. The original Android app remains installed.

Android artifact: `artifacts/bdk-audio-design-preview-0.5.1.apk`,90,297,114 bytes,
`BDK_PREVIEW_ONLY=true`, SHA256:

`2836ae7d878313edd54928a1a893fb2a9521efe82225159ef2a3a491a32d72ca`

Final Android ARM64 and Windows x64 Debug builds pass. The Windows preview
archive includes the complete executable, plugins, engine and Dart assets;
those required entries' hashes match the current build bundle. Product metadata
reports BDK Audio0.5.1+9. Archive:
`artifacts/bdk-windows-design-preview-0.5.1.zip`,45,702,416 bytes, SHA256:

`c8457f6d31c5fbac49ea27a059f1b8bee52877cca5c9991c2b9588df4db379ca`

These are development packages, not signed production releases. Native phone
captures remain local/ignored. Only exact self-created QA files/entries were
removed; no app data was cleared and no original app was replaced.

## Remaining gates

The latest user report is not connected/playing music. Live BLE-driven response,
actual codec negotiations, audible continuity and physical Windows sink matching
remain unverified. Apple/Linux native builds/runtime, broad permission/driver and
accessibility/performance matrices, original icons, publisher identities/signing,
trusted hosted updates and production packages are still required. Prepared
targets, passing client tests and development bundles do not complete those gates.
