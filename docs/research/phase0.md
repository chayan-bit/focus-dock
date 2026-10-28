# Phase 0 spike: live Dock measurements and API checks

Machine: macOS 27.0 (Darwin 27), Apple Silicon, built-in display 1470x956 pt at backing scale 2.0 (2940x1912 px), Dock at bottom, dark appearance, one dark-blue sea wallpaper.
Dock prefs read-only: tilesize 75, largesize 85, magnification on, autohide off.
All measurements are from 2x crops, so 1 px = 0.5 pt; edge positions are good to about +-1 px.
Scratchpad folder (all evidence): <scratchpad>/phase0/
Evidence images (in that folder): evid_platter_crop.png, z_corner_tl.png, z_corner_bl.png, z_divider.png, z_trash.png, evid_hover_label_crop.png, z_label.png, bounce_montage.png.
Note: my first raw captures (dock_full.png, hover_finder.png, bounce.mov frames) were 150 pt tall and include about 50 pt of window pixels above the Dock; they stay in the scratchpad only.

## 1. Platter (confidence H unless noted)
Method: pixel profiles of columns/rows in a 60 fps-quality still, plus the AX frames of the Dock list (System Events, read-only).
Total height is 95 pt = tile 75 + 2 x 10 pt, so vertical inset from tile cell to platter edge is 10 pt = 0.133 tile.
The AX item cell is 79 x 95 pt (tile + 4 pt pitch) and its height equals the platter height.
Horizontal inset from the first/last AX cell to the platter edge is 8.5 to 9 pt (0.117 tile); to the tile itself it is about 10.5 pt.
Icon pitch is 79 pt = tile + 4 (ratio 1.053); the visible icon art is 60.5 pt (0.807 tile) because Tahoe icon artwork carries its own margin, the Dock cell is the full 75 pt.
Gap from screen bottom to platter bottom is 5 pt; the reserved strip (NSScreen visibleFrame) is 101 pt.
Corner radius is 30 pt (circle fit to the bottom-left rim, R = 60 px, error under 2 px) = 0.40 tile, 0.316 of platter height; confidence M-H.
Rim: a bright specular line about 1 pt (2 px) wide at the top and bottom edges, peak roughly white at alpha 0.30 to 0.35 over the interior (top px rgb 94,116,142 over 13,20,28), fading over the next 1 pt; sides show a 0.5 pt dark outer line (rgb 5,14,25). Confidence M for width, L for alpha.
Drop shadow: faint, dark band below the bottom edge fading over about 5 px (2.5 pt); estimate offset 1 pt, blur 3 pt, opacity 0.3 to 0.5. Confidence L (dark wallpaper hides it).
Fill: interior rgb about 15,41,71 vs 10..28,35..60 outside, i.e. dark tinted glass with strong blur; the real material is Liquid Glass, do not try to match with a flat colour. Confidence L.
Platter height does not change under magnification; width grows centred (see 5). Adding a tile (Calculator) widened it by 79 pt centred (39.5 pt each side).

## 2. Running indicator (current appearance only: dark)
Diameter 8 px = 4 pt (0.053 tile); circle, no outline.
Centre is 6.25 pt above the platter bottom edge, 4 pt below the tile cell bottom, 11.25 pt below the icon art bottom.
The dot does not move or scale under magnification (y stays constant) and is horizontally centred on its tile.
Colour in the centre pixels is about rgb(140,165,192) on this wallpaper, over ten dots with backgrounds from 14,39,69 to 23,44,64 (values moved only 138..150), i.e. near-opaque pale blue-grey, equivalent to white at alpha 0.55 to 0.65.
Confidence L for alpha: only one dark wallpaper is visible, so over-light-wallpaper behaviour is unmeasured; light appearance was not changed or measured.

## 3. Divider
Slot width 35 pt (0.467 tile, AX), drawn line 2 px = 1 pt wide, height 142 px = 71 pt (0.947 tile; 2.25 pt inset from the tile cell top and bottom), vertically centred on the tile.
Colour rgb(78,100,124) over platter rgb(14,36,59), which is white at alpha about 0.28 to 0.30, constant along its length (no gradient). Confidence H for geometry, M for alpha.
This dock has two dividers (apps | other apps | Trash); there is no separate recents block.

## 4. Hover label
Shape is a rounded pill with a small downward tail (pointer) pointing at the tile, horizontally centred on the hovered tile.
Body height 23 pt, total with tail about 30.5 pt; width for "Finder" is 66 pt with text 39.4 pt wide, so horizontal padding is about 13.5 pt.
Corner radius about 11.5 pt (near a capsule, 0.5 x body height); tail about 7.5 pt tall and about 10 pt wide at its base (L).
Text: cap height 10 pt, so SF font about 14 pt, regular weight (M-L; medium cannot be excluded).
Fill opaque-looking rgb(34,34,36) over a black window (so alpha unknown), top edge highlight rgb(48,48,50) 1 px wide.
Gap: body bottom is 10.75 pt above the platter top, tail tip is 3 pt above the platter top.
Label appears with the tile magnified (hover state), fade-in observed mid-transition in one frame (about 0.2 s, L).

## 5. Magnification
Peak size equals largesize: hovered Finder art 137 px vs 121 px unmagnified = 1.13 = 85/75 (H).
Falloff fitted to tile-centre shifts of 10 running-app dots in 5 hover frames (mouse at tile centres and a tile boundary): cosine profile size = 75 + 10 x cos(pi/2 x d/W), W = 3.1 pitch units (245 pt, 3.3 tiles), RMS error 0.66 pt; cos^2 gives W = 3.9 at RMS 0.72, Gaussian sigma 1.6 pitch at RMS 0.82.
Predicted sizes at distance 0, 1, 2, 3 pitches: 85, 83.8, 80.3, 75.5 pt; so about 3 neighbours each side grow, the third barely. Confidence M.
Icons grow upward (art bottom 255 -> 253 px), platter height is constant, and the platter widens centred by sum of growth (about 39 pt for hover mid-dock).
Timing (60 fps VFR recording, mouse teleport in): grows 122 -> 138 px in 3 frames (about 50 ms), steps 7, 5, 4 px (ease-out); shrinks back in about 50 ms. Confidence M-L (frame granularity 17 ms).

## 6. Launch bounce (Calculator, not in the Dock)
Observed one bounce only, because Calculator became ready in under 0.5 s: the tile and icon appear at t = 2.05 s already at the apex, the apex is 20 pt (40 px, 0.27 tile) above rest and held about 0.1 s (to 2.2 s), then it falls to rest in about 0.30 s (2.2 to 2.5 s) with accelerating speed (2 -> 4 px per frame, gravity-like ease-in).
Total visible bounce about 0.45 s; the rise phase and the repeat period for slow-launching apps were NOT observed (L); only Calculator was allowed. Calculator was quit afterwards.

## 7. CoreDock dlsym (H)
dlopen of ApplicationServices.framework succeeds; dlsym resolves both CoreDockGetAutoHideEnabled (0x19762b004) and CoreDockSetAutoHideEnabled (0x1976355b4) without error.
Calling only the getter returned 0 (autohide off), matching defaults. Setter was never called. Test: scratchpad cd.c / cd_test.

## 8. usernoted DB (H)
sqlite3 -readonly opens ~/Library/Group Containers/group.com.apple.usernoted/db2/db directly, no copy needed, no error (db 1.0 MB, wal 3.2 MB).
Tables: app, categories, dbinfo, delivered, displayed, record, requests, snoozed.
Row count of record: 146. No content was selected.

## 9. Chrome AppleScript (M)
The osascript call launched Chrome (it was not running; I quit it again), `count windows` returned 0, so `count tabs of window 1` failed with error -1719 (no window); live tab count is therefore unmeasured.
The sdef exposes classes window and tab only; there is no tab group class or property (grep for "group" only matches access-group elements). Tab groups are not scriptable via AppleScript here.

## 10. Glass APIs (H)
SDK: MacOSX.sdk 27.0 (Xcode, Swift 6.4).
AppKit headers NSGlassEffectView.h: NSGlassEffectView (cornerRadius, tintColor, style regular/clear, contentView) and NSGlassEffectContainerView, API_AVAILABLE(macos(26.0)).
SwiftUICore swiftinterface has glassEffect(_:in:), GlassEffectContainer, glassEffectID, glassEffectUnion, glassEffectTransition (SwiftUI.swiftinterface itself has none; they live in SwiftUICore, imported via SwiftUI).
A test file using GlassEffectContainer + .glassEffect(.regular, in:) + NSGlassEffectView + NSGlassEffectContainerView compiled and ran with swiftc (scratchpad g.swift).

## Constants
```swift
let refTileSize = 75.0              // pt, defaults tilesize at measurement
let refLargeSize = 85.0
let backingScale = 2.0
let platterVerticalInsetRatio = 0.133   // of tileSize; platter height = tile + 2 * 0.133 tile
let platterHorizontalInsetToCellRatio = 0.117 // from AX cell edge (cell = tile + 4)
let itemPitchExtraRatio = 0.0533    // 4 pt spacing added to tile
let platterCornerRadiusRatio = 0.40 // of tileSize (30 pt)
let platterBottomGapPt = 5.0        // pt, fixed (0.067 tile)
let platterRimWidthPt = 1.0
let platterRimAlpha = 0.30          // white, top/bottom specular, L
let platterShadowOffsetY = 1.0, platterShadowBlur = 3.0, platterShadowOpacity = 0.4 // L
let indicatorDiameterRatio = 0.053  // of tileSize (4 pt)
let indicatorBelowTileRatio = 0.053 // dot centre 4 pt below tile cell bottom
let indicatorColor = (r: 140, g: 165, b: 192) // dark appearance, L
let dividerSlotWidthRatio = 0.467   // 35 pt
let dividerLineWidthPt = 1.0
let dividerHeightRatio = 0.947      // 71 pt
let dividerWhiteAlpha = 0.29
let labelBodyHeightPt = 23.0, labelTailHeightPt = 7.5, labelHPaddingPt = 13.5
let labelCornerRadiusPt = 11.5, labelFontSizePt = 14.0, labelGapAbovePlatterPt = 10.75
let labelFill = (r: 34, g: 34, b: 36)
let magnifyPeakRatio = 85.0 / 75.0  // largesize / tilesize
let magnifyHalfWidthPitches = 3.1   // cosine profile: 1 + (peak-1) * cos(pi/2 * d / W)
let magnifyInSeconds = 0.05, magnifyOutSeconds = 0.05
let bounceApexRatio = 0.267         // of tileSize (20 pt)
let bounceFallSeconds = 0.30, bounceApexHoldSeconds = 0.10
```
