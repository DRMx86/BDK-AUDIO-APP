# BDK musical B provenance

The current SVG and Flutter painter are original vector geometry created for
BDK Audio. The B is a custom rounded geometric monogram; an eighth note with an
oval head, tall stem and curved flag makes the audio identity explicit.

This replaces both the earlier ring/speaker adaptation and the later B plus
straight signal accent. The current master does not reuse supplied Android
drawable geometry, JBL assets, third-party logos or downloaded icon artwork.
The original Android application and supplied source remain unchanged.

`lib/features/startup/bdk_brand_mark.dart` reproduces the SVG paths as a Flutter
CustomPainter for crisp zoom animation. Native launcher and Apple launch
bitmaps derive from `assets/branding/bdk-mark.svg` through
`tools/export_icons.cjs`. The SVG keeps a full opaque canvas; adaptive Android
foreground exports remove that canvas and use an inset safe area. macOS and
Windows exports use a rounded tile, while iOS applies its own launcher mask.

Generate with `node tools/export_icons.cjs`; the development-only Sharp module
may be selected through `BDK_SHARP_MODULE`. `--check` compares every regenerated
export in memory. No runtime package or network asset dependency is added.

This artwork record does not establish broader project source, publisher,
trademark or release rights. Those remain separate release inputs.
