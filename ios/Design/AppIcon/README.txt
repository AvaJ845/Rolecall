ROLECALL — APP ICON PACKAGE
Direction 1: Refined Roll-Call Tick
Generated: 2026-09-07

MASTER ART
- iPhone / iPad: 1024×1024 RGB, fully opaque, square source (no rounded corners)
- Apple Watch: 1088×1088 RGB, fully opaque, square source
- Light ground: #F3EEE3
- Light mark: #211F1C
- Dark ground: #292622
- Dark mark: #F3EEE3

DESIGN INTENT
A single, confident roll-call tick: “present.”
The icon deliberately avoids job-board symbols, text, badges, gradients, shadows,
and color-dependent meaning. The dark variant uses a lifted warm charcoal rather
than pure black so it remains legible on watchOS.

XCODE
The Xcode folders contain Appearance variants for light/dark use.
For iOS/iPadOS, use AppIcon.appiconset.
For the WatchKit target, use WatchAppIcon.appiconset.

IMPORTANT
Apple's system applies the platform-specific rounded/circular mask. Do not bake
rounded corners into these source PNGs.

QA
Rolecall_Icon_Size_QA.png shows 1024→29px checks.
Rolecall_Light_Grayscale_QA.png is a monochrome sanity check.

This package contains icon artwork only; App Store screenshots, metadata, and
marketing assets are separate deliverables.
