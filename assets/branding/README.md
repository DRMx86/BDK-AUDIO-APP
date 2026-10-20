# BDK Audio musical B

`bdk-mark.svg` is the original editable vector master: a rounded geometric B
with a separate eighth note (oval head, stem and curved flag). It replaces the
rejected B plus straight signal bar. No JBL artwork, fonts or code are used.

Flutter startup uses the matching code-native `BdkBrandMark` painter. The note
draws in as the B settles; the B then expands around its upper counter while an
aperture reveals the actual app. It is vector art throughout the zoom. App info
continues to use `bdk-mark.png`.

`tools/export_icons.cjs` rasterizes the master at every declared native size:
Android opaque/round/adaptive foreground, opaque iOS, rounded macOS,
multi-resolution Windows ICO and Linux launcher PNG. Apple launch images also
use the master. Run `node tools/export_icons.cjs --check` to compare every export
without changing files. Set `BDK_SHARP_MODULE` to a development-only Sharp module
when it is not on the normal Node module path.

Android's OS starting surface uses the same dark background with a transparent
icon and an immediate SplashScreen API handoff, avoiding a separate launcher-logo
flash. The custom B animation starts after the first Flutter frame is rasterized,
holds for two seconds, then reveals the app over 700 ms. Apple launch surfaces
retain the static mark. Android adaptive foregrounds fit the circular 66 dp safe
area. Generated Apple resources do not
establish an Apple build or release. Native launcher masks and the actual
startup transition still require rendered/device review. Broader publisher and
source rights remain tracked in `docs/validation/branding-license-audit.md`.
