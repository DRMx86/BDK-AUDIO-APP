# Windows AOT preview checkpoint

Version **0.5.6+14**, application code checkpoint
`342494db8f486b36b19d9882eacc0c670d4959a1`. Subsequent checkpoint `758fcb2`
changes only validation documentation. The pinned Flutter 3.44.4 command completed
with exit 0:

```powershell
flutter build windows --release --no-pub -t lib/main.dart --dart-define=BDK_PREVIEW_ONLY=true
```

The build reports 69.6 seconds; this single observation is not a performance
distribution. Existing C4244 conversion warnings in the copied LED/miniaudio
sources remain in `artifacts/windows-056-release-build.log`. No application or
native algorithm was changed for this build.

## Complete portable export

`artifacts/windows-0.5.6-release/bdk-windows-preview-0.5.6-x64-release.zip`
contains **all 27 runtime files**, with ZIP CRC, file sizes and SHA256 checked
against the built bundle and a fresh extraction. It is **13,943,279 bytes**,
SHA256:

```text
577fc06d5b3ff4e929a547891355d890f61072e301f0a0cd5c4dbbe7c6bdf7af
```

All seven PE binaries are AMD64; the AOT `data/app.so` is ELF64/x86_64. No Debug
kernel blob is included. All eight explicit font/native notices match source
bytes. Native executable FileVersion/ProductVersion both read `0.5.6+14`.
Authenticode reports **NotSigned**. This optimized portable development preview
is not a signed installer or production release.

Detailed manifests, checksum, binary/notice checks and signature status are in
the same ignored artifact directory. The first packaging helper incorrectly
expected a desktop `version.json` asset; the actual Windows runner embeds native
VERSIONINFO instead. The corrected verification reads that resource. The bundle
and application code were unchanged.

## Native startup and incomplete UI check

The executable was launched from the **freshly extracted archive**, not another
build directory. Process **44588**, window **23070046**, title `BDK Audio` and
executable path were observed. Its actual accessibility tree exposed the setup
screen, Bluetooth-audio step and Explore Demo action. Four mapped executable/
plugin/engine files match the exported manifest hashes.

The native screenshot was occluded by another running window. The desktop
automation returned `failed to activate captured window` on the attempted Demo
action. Fresh window selection succeeded; one scoped activation recovery failed
with the same error. **No successful input, rendering, animation, Sound import
or BLE verdict is claimed for this Release process.** Earlier native Debug UI
checks remain separate evidence.

Further input stopped. Only the identity-checked owned QA process was terminated;
the subsequent process inventory and native window list confirmed its absence.
Other applications and settings were untouched. Receipts are
`native-startup.json`, `native-binary-verification.json` and `cleanup-final.json`.

The Redmagic installation remains unchanged. Live music/BLE, physical Windows
identity/codec mapping, native ARM64, signing and distribution gates remain open.
