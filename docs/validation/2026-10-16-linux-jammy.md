# Isolated older Linux ABI validation, 2026-10-16

Current measured state: **unchanged-source Jammy Debug build, ELF/dependency
inspection and complete export verification passed**. Bundle requirements are
GLIBC **2.34** / GLIBCXX **3.4.29**. Native feature runtime remains **partial**:
the actual Setup screen is visible under softpipe, but Demo activation,
Light/gallery and app WAV import are unpassed. The default llvmpipe launch
aborted. **No Release build was run; full runtime acceptance is incomplete.**

Status at the initial checkpoint: **signed Jammy bootstrap is running; no Jammy
build, ELF compatibility, native runtime or Release verdict exists yet.** The
unchanged application input is 0.5.6+14, 308 reviewed files, archive SHA-256
`0fcb10a86eb935986326008e9cec64cc5f66541a54734e84f3b071d83714ed50`.
The pinned Flutter 3.44.4 / Dart 3.12.2 SDK revision is
`ad70ec4617166f1c38e5d2bfd388af71fda14f06`.

## Isolation and reviewed helpers

The existing owned QEMU host PID 20036, two TCG CPUs and 4 GiB RAM remains in use,
with SSH/QMP only on localhost 33422/33423. The parent independently confirmed the
prior Noble Sound QA processes had ended before releasing the guest mutation
fence. No Windows-global SDK, operating-system package, physical device, supplied
ESP32 source, serial, playback, transfer or OTA operation is part of this work.

The distinct guest base is `/home/runner/jammy-056-20261016`, its fresh root is
`root/`, and helper/job inputs live in `/home/runner/jammy-helpers-20261016`.
`tools/linux_runner/jammy-*` implement fixed account/hostname/canonical-path
guards, strict package/signature verification, a private mount namespace, separate
SDK/source/profile directories, bounded jobs and exact native GUI identity checks.
The namespace has its own proc/dev/run/tmp mounts and only synthetic standard
character devices; no physical device or Noble build directory is bound into it.
Service startup is inhibited during root package installation. Cleanup matches
both the owned mount namespace and chroot before signalling children.

Fresh review corrected main-app mouse input to require its exact focused XID and
target that XID explicitly. The future portal chooser needs its own observed
PID/XID/title/executable/session identity before chooser input. Review also added
the phase allowlist before writes/mounts and a canonical, nonsymlink jobs-parent
guard before directory/log/PID writes. The actual launcher rejected a sandbox
jobs-parent symlink with exit 1; its target remained empty. The preserved sandbox
is `/home/runner/jammy-guard-check-20261016`.

All helper Bash/Python syntax checks passed. The source helper extracted the
actual approved archive and matched 308/308 hashes. Focused checks rejected
unsafe archive paths, an existing extraction destination, changed reviewed bytes
and a different focused window. These are helper checks, not native app gates.

## Signed bootstrap inputs and preserved failures

Ubuntu's `debootstrap` 1.0.134ubuntu2 package was downloaded through the existing
signed Noble apt metadata and extracted only in the owned guest base, without
installing it into Noble. Its exact SHA-256 is
`836bb4cfe322a415cc9e2b1abe46d65cdc53cefac315764edb498380f8f28de5`.
The copied Ubuntu archive keyring SHA-256 is
`80a36b0a6de2f69f49d2df75ef473ccde121e9e190b9ea01d20a4f63778d5c31`.
The corrected absolute keyring matches both the original digest receipt and the
installed archive keyring. `gpgv` reports a good Noble-updates signature from
Ubuntu Archive Automatic Signing Key (2018).

| Attempt | Supervisor PID | UTC start / finish | Result |
| --- | --- | --- | --- |
| setup | 18692 | 22:19:09 / 22:19:12 | Exit 2: relative gpgv keyring resolved under `~/.gnupg`; no root created |
| setup-resume | 18954 | 22:20:02 / 22:20:04 | Exit 1: strict flag spelled `--force-check-sig`, unsupported by this official debootstrap; no root created |
| setup-resume2 | 19442 | 22:20:43 / 22:35:01 | Exit 0: corrected `--force-check-gpg`, valid Jammy Release signature and validated package lists |

Both terminal failures, their logs, timestamps, exit codes and the original helper
snapshot are retained. Resumes required terminal prior jobs, a still-absent root,
and unchanged source archive, SDK revision, package and keyring identity. No live
job was restarted because an observation timed out.

The setup outer command, observed in its process arguments, was:

```sh
timeout --signal=TERM --kill-after=30s 4200 bash /home/runner/jammy-helpers-20261016/jammy-resume-setup.sh /home/runner/jammy-helpers-20261016 setup-resume2
```

It encloses a root-owned 3600-second timeout and
`unshare --mount --propagation private bash .../jammy-namespace.sh setup`.
Official debootstrap now explicitly reports `Checking Release signature` and
`Valid Release signature`, key ID
`F6ECB3762474EDA9D21B7022871920D1991BC93C`. There is no unsigned or HTTPS-only
fallback. The original launch-command text omitted its final resume-attempt token;
the observed process arguments above are authoritative, and the helper's receipt
format has been corrected for later jobs without altering the old record.

Each detached phase retains `command`, `started`, `finished`, `exit`, `log`,
`supervisor.pid` and `execute.pid` under the helper directory's `jobs/<phase>/`.
Build jobs have a separate root-owned 1800-second limit and a 1860-second outer
supervisor; GUI has a 1100-second root bound enclosing its 1000-second session.
Local ignored receipts are under `artifacts/linux-runner/jammy/`, including launch
receipts and `helper-resume-changes.diff`.

## Remaining gates

Actual Demo/Light/gallery/native LED mapping and owned-WAV import through the
portal chooser/decoder isolate need a new guarded session. The default renderer
failure and missing Demo transition need diagnosis. Release requires its own
separate build/verdict. TCG/software rendering cannot establish physical
BLE/audio, hardware FPS, older distributions or other CPUs.

## Completed setup and Debug build

Setup-resume2 completed in 14 minutes 18 seconds. Actual root identity is Ubuntu
22.04 (Jammy), clang 14.0.0-1ubuntu1.1, CMake 3.22.1, GTK 3.24.33, GStreamer
1.20.3. The package manifest records libc6/libc6-dev 2.35-0ubuntu3.15 and
libstdc++6 12.3.0-1ubuntu1~22.04.3; these package versions do not substitute for
measuring the bundle's imported symbol versions. The copied SDK reports the exact
requested Flutter/Dart/framework revision and a clean tracked source status.
Source extraction verified all 308 reviewed file hashes, and the build directory
was absent before launch. Setup left no live owned setup job or root mounts.

Debug supervisor PID **37382** ran **22:35:55–22:43:07 UTC**, exit **0**, with the root-owned
1800-second timeout and 1860-second outer timeout recorded above. Flutter reports
307912 ms for its Linux command. Locked
dependency resolution passed and native compilation reports clang 14. Both LED
and decoder build rules preserve `-fno-fast-math`; the actual native compiler
paths, flags and process observations are saved in `cmake-compiler-paths.txt`,
`native-compiler-flags.txt` and `native-build-processes.txt` in the root evidence.

Resource ruling: `CMAKE_BUILD_PARALLEL_LEVEL=2` was exported, but the measured
Flutter command invokes `ninja -C ... install` directly, without `-j2`. This
environment variable alone does **not** prove two Ninja jobs. The existing VM
still bounds execution to two TCG CPUs and 4 GiB RAM. The parent explicitly chose
to preserve and continue the live build rather than repeat an unchanged build
solely to claim a compiler-job count. No exact Ninja parallelism claim is made.

The complete setup/failure/inventory receipts have been copied into local ignored
`artifacts/linux-runner/jammy/jammy-setup-receipts.tar.gz`. An owned 3.000-second
PCM16 WAV is ready for the later actual app import: 16000 Hz, stereo identical
channels, 48000 frames, 192044 bytes, SHA-256
`387b443f440c40241e148870b7c654b3958e46f7546c411f69e5b40e3926267f`.
It contains generated samples, not recorded audio, and has not been played.

This task continues to use the exact 0.5.6 snapshot. A separately identified
Particle Burst Demo adapter defect and any subsequent 0.5.7 correction are outside
this bundle; no newer source or native object is mixed into its evidence.

## Measured ELF and dependency result

Every packaged ELF is x86_64 and resolves its dependencies **inside Jammy**.
Imported symbol requirements, not compiler/package versions, establish this table:

| Bundled ELF | Highest GLIBC | Highest GLIBCXX | Highest CXXABI |
| --- | --- | --- | --- |
| `bdk_audio` | 2.34 | 3.4 | 1.3 |
| `libaudioplayers_linux_plugin.so` | 2.2.5 | 3.4.29 | 1.3.13 |
| `libbdk_audio_decoder.so` | 2.34 | 3.4.29 | 1.3 |
| `libbdk_led_engine.so` | **2.14** | 3.4 | 1.3 |
| `libflutter_linux_gtk.so` | 2.18 | none | none |

The measured bundle maximum falls from the Noble build's GLIBC 2.38 to **2.34**;
GLIBCXX remains **3.4.29**, CXXABI **1.3.13**. Independent Noble/Jammy `readelf`
requirements agree for all five files. Jammy `readelf` emitted unrecognized-form
warnings, preserved in the log; its exits/tables were checked. `ldd` reports no
missing libraries. These necessary ABI constraints do not prove all-distribution
or full application compatibility.

## Partial native runtime and preserved limitations

Initial GUI supervisor **38618**, 22:43:56–22:44:36 UTC, exited **1**. Actual app
PID **38715** aborted before a visible window with wait status **134**:
`LLVM ERROR: 64-bit code requested on a subtarget that doesn't support it!`.
Its renderer receipt identifies Mesa **23.2.1**, llvmpipe **LLVM 15.0.7 / 256 bits**,
`Accelerated: no`. That default-renderer failure remains unresolved.

Distinct supervisor **39392**, 22:45:48–22:57:37 UTC, used only per-job
`LIBGL_ALWAYS_SOFTWARE=1`, `GALLIUM_DRIVER=softpipe`, `GDK_BACKEND=x11`.
[Mesa documents that software-renderer selection](https://docs.mesa3d.org/envvars.html).
The measured renderer is Mesa 23.2.1 softpipe, GL 3.3 / GLES 3.1, not accelerated.
The real shipped entrypoint reached visible Setup as app PID **39483**, XID
**2097155**, title `BDK Audio`, exact executable
`/home/runner/bdk-audio-056-jammy/build/linux/x64/debug/bundle/bdk_audio`.
No alternate entrypoint, state injection, LED factory or native-loader override
was used.

The no-WM focus guard initially refused PointerRoot focus. Reviewed recovery
recorded all top-level map states/properties and exempted only the measured
unnamed, propertyless 1x1 override-redirect auxiliary XID **2097161** at (-100,-100),
fully outside the viewport with the same observed client prefix. Changed helper
conditions or other viewable windows reject; focused main identity is rechecked.
Window-scoped synthetic mouse/key events did not establish Demo activation.
Inspected XTest keyboard navigation moved focus; no Return activated Bluetooth
settings or manual audio confirmation.

One mouse diagnostic stopped before clicking when `xdotool` reported window 0:
`xwininfo -id 0` waited interactively. Only verified owned diagnostic PID **40643**
was terminated. The helper now rejects zero/negative windows, explicitly declares
the X11 ctypes API types, and uses a 30-second alarm. A corrected XQueryPointer
read, exact identity/focus and recipient-ancestry guards recorded one actual
XTest click at (640,472), targeting main window **2097155**. Its subsequent native
PNG still showed Setup. The missing transition's cause is **UNKNOWN**; app,
backend and tooling causes have not been isolated. No blind repeat or forced Demo
state counted as a pass. Before/after PNGs, stderr, focus/map-state and recipient
receipts are preserved.

Only visible Setup is established here. Light/gallery, mapped native LED library,
actual file selection and app decoder-isolate import are **unpassed**. The owned
WAV was neither selected nor played. The controller ended intentionally and reaped
app PID 39483 with SIGTERM / wait status **15**. Its exit **0** denotes clean
partial session completion, not feature acceptance. Final checks found the owned
app/controller/Xvfb/D-Bus/diagnostic/export PIDs absent, no X99 socket and no root
mounts; the root and all receipts remain for review.

## Complete export

Audit/export supervisor **41159**, 22:58:08–22:58:44 UTC, exited **0**. The locally
transferred bundle is
`artifacts/linux-runner/jammy/bdk-audio-0.5.6-linux-jammy-x64-debug-preview.tar.gz`,
**38884655 bytes**, SHA-256:

```text
1978f13a1efdaf8f03540f219c07a78fe5ec042f3cd96c45bc654e89fceca2be
```

Independent verification matched every path/type/mode/size/hash: **42 entries /
28 regular files / zero symlinks**. Executable and installed launcher retain
`0755`. Post-QA/export hashing matched **308/308** reviewed source files.
Full native/failure/profile evidence is in `jammy-validation-receipts-final.tar.gz`
(the earlier receipts archive is retained);
direct manifests, ABI/dependency/source receipts, the separate acceptance verdict
and independent archive verification are alongside it in ignored local artifacts.
The package inventory remained byte-for-byte unchanged after QA/export, and the
copied SDK's tracked Git status is still clean. The overall migration and this
plan's full runtime acceptance are not complete.

## Focused input-helper review corrections

Fresh review found three input-guard issues after the partial session: potentially
normalized child focus, titled-window-only modal checks, and a default SIGALRM
that could abandon a diagnostic subprocess. These are corrected in the helpers,
without rerunning the app or changing the preserved runtime verdict.
`jammy-input-common.py` now supplies raw `getwindowfocus -f`, the complete viewable
top-level InputOutput inventory with only the exact measured auxiliary exception,
and bounded owned process groups. Every diagnostic command, including
`windowfocus --sync`, has a timeout; timeout or a raising overall-deadline handler
kills and reaps the active child before unwinding. GUI key/pointer inputs reuse
the full inventory before each XTest action, rejecting unnamed popups as well.

Guard-only private Xvfb tests created test windows, not the application. Actual
raw focus on child 2097154 was rejected as parent 2097153 even though that parent
was its real WM_CLASS ancestor. This installed Noble `xdotool` default also
returned the child; the test records that observed version behavior rather than
claiming it normalized. An unnamed viewable InputOutput popup was rejected, and
the sole-parent positive case passed. Command-timeout child PID 42513 and
overall-deadline child PID 42514 were both absent and already reaped afterward.
Earlier test-fixture failures are retained. Guard test receipts are in ignored
`artifacts/linux-runner/jammy/jammy-input-guard-tests.tar.gz`. These checks prove
guard behavior only; they add no Demo, LED, file import or Release evidence.
