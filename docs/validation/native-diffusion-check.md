# Native LED diffusion regression

Windows onscreen inspection found a hard rectangular boundary at the square
source's sides inside the wider preview card. The original painter placed
`ImageFilter.blur` directly on `drawImageRect`. The real window clipped that
filter at the image destination; both the software widget paint test and native
`Picture.toImage` offscreen pixels showed a smooth result instead.

The hardware-free `tools/light_diffusion_probe.dart` isolates the same painter
with one static16×16 dark-green frame, a680×300 card and black background. It
never creates a BLE session or a renderer instance. Its visible native window
reproduced the hard central rectangle before the fix. Its offscreen result
incorrectly suggested success (`maxEdgeJump=0`, sideGreen31, coreGreen79),
demonstrating why offscreen-only evidence was insufficient here.

The fix draws each source into a composited layer and applies Gaussian blur
when restoring that layer. The source destination remains square, its uniform
scale and original pixels remain unchanged, and the glow covers the wider card.
The static native window was inspected again: both source edges now fade
smoothly. The supporting offscreen check passes (`maxEdgeJump=2`, sideGreen18,
coreGreen79). This is an actual onscreen visual failure-to-pass comparison;
the offscreen test did **not** fail before the change.

Reproduce on Windows, first close only this development app so its build output
is not locked:

```powershell
flutter build windows --debug --no-pub -t tools/light_diffusion_probe.dart --dart-define=BDK_DIFFUSION_REPORT=artifacts/diffusion
```

Launch the resulting native development executable and inspect the two vertical
source transitions. The optional report prefix is relative to that process's
working directory; use an absolute prefix to retain output in a chosen local
artifact directory. The report/PNG describe offscreen pixels; the displayed
window is the decisive backend check. Rebuild the actual app with the default
`lib/main.dart` target and `BDK_PREVIEW_ONLY=true` afterward. Never distribute
the diagnostic entry point as the app.

Phone/other GPU implementations require their own native inspection. Geometry,
black/stale input, lifecycle and effect-source tests remain separate. This
change does not alter or write any ESP32 code or hardware.
