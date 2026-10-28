# Native Dock RE (macOS 27.0 / 26A428, Dock 1.8 build 2571.0.6.402)

Target: `/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock` sha256 `b704affb...e33e`, arm64e, opened in REA (Ghidra 12.1.2, 29,464 procs).
Evidence IDs are REA `ev_*`; `asm@0x...` = `otool -tvV` address in the same binary; static only, nothing executed.
Confidence: H = read directly from code/data, M = inferred from strong static signal, L = plausible, UNKNOWN = needs runtime.

## 0. Architecture facts that drive everything
- Dock does NOT link AppKit (`otool -L` has no AppKit), it draws with raw SkyLight windows + CoreAnimation (`CAContext`, `CABackdropLayer`) and SwiftUICore/DesignLibrary materials. H
- It is `LSUIElement=true` (Info.plist) and is itself the Spaces/Mission Control server (imports `CGSAddWindowsToSpaces`, `SLSTransactionSetSpaceAbsoluteLevel`, WindowManager.framework `ExposeCoordinator`). H
- So "same level" is achievable, but "same Space semantics" is not: Dock windows are outside normal Space management. A third-party panel can only approximate with public collection behaviours. H

## 1. Window level, type, collection behaviour
- Every Dock window class (`WALayerKitWindow`, `TileDragWindow`, `BezelIconListWindow`, `DockWindowCopy`) is created via `initWithFrame:connection:display:scaleFactor:tags:level:` (ev_8dc098...). H
- 27 calls to `CGWindowLevelForKey`; 21 pass key 7 = `kCGDockWindowLevelKey` (level 20) (ev_d25ee5...; asm@0x1000ed108 `mov w0,#0x7`). Others: key 12 Dragging (tile drags), 18 DesktopIcon, 2 Desktop, 8 MainMenu, plus `dock-2` and `dock+3` offsets (asm@0x1000c9b84 `subs w0,w0,#2`; asm@0x100229c94 `adds w20,w0,#3`). H
- Example: `FUN_1000ed048` allocs `WALayerKitWindow` at Dock level, puts it on its own Space and sets `SLSTransactionSetSpaceAbsoluteLevel` (ev_c91142...). H
- Window tags passed in x4: `0xa00`, `0x200`, `0x20`, `0` (asm@0x1000ed0xx, 0x100297518, 0x1001bf8b0). The Dock's tag option-set names are in strings (`.ignoreForEvents .opaqueForEvents .onAllWorkspaces .preventsActivation .ignoresCycle .ignoreForExpose .superSticky .friendOfFullscreen .neverSticky ...`). Mapping to classic CGSPrivate bits gives 0x800 = onAllWorkspaces (sticky), 0x200 = ignoreForEvents. M
- No activation stealing: Dock never becomes an AppKit key window; clicks go through its own event handlers (`DockBarMouseEventHandler`). H
- Third-party equivalent: see recipe; `.canJoinAllSpaces + .stationary + .ignoresCycle` reproduces sticky / not-moved-by-Mission-Control / not in Cmd-` cycle. M (public API semantics, not verified at runtime here)
- Above fullscreen: native Dock only appears in fullscreen Spaces on edge reveal (`WindowManager.ExposeCoordinatorDelegate.minimumDockRevealAmountDidChange`). Without `.fullScreenAuxiliary` our panel will not show in fullscreen Spaces, which matches. M

## 2. Visuals (platter, glass, indicator, sizes)
- Platter = Liquid Glass from private `DesignLibrary.GlassMaterialProvider` with `Configuration.dock`, `size = .medium`, `adaptive(Bool)` (asm@0x100177200..0x10017723c; imports `...ConfigurationV4dock`, `...SizeO6medium`). H
- Controller classes: `DockGlassMaterialLayerController initWithVariant:adaptive:`, `DockGlassMaterialEnvironment` (colorScheme, colorSchemeContrast, accessibilityReduceTransparency, accessibilityShowButtonShapes, tintColor, tintAmount, backdropGroupName, displayScale, maxAllowedSystemUIContentHeadroom), `DockGlassMaterialLayoutConfiguration` (elements, smoothness, frame) (REA search_procedures ev_3d66b5...). H
- Platter shape is an SDF union of elements (`DockSDFElement`, `DockTileSDFElementContents`, `SDFElementCornerRadius`, `cornerRadiusAddition`, `smoothness`), not a fixed rounded rect. H for mechanism, UNKNOWN for numeric radius (measure with a screenshot at known tilesize).
- Other glass configs: app icons `Configuration.appIcons` + `.minimum` + `boostWhitePoint`; hover labels/popovers `Configuration.cartouchePopover` (asm@0x100224c7c); Cmd-Tab `Subvariant("appSwitcher")`; Mission Control uses `.regular`/`.clear`. H
- Legacy (pre-glass / Reduce Transparency) path: `LegacyFloorLayer` vs `ModernFloorLayer`, `ECMaterialLayer`, PNG `shadow-large-{light,dark}.png`, `cartouche-*.png`. H
- Shadows: `primaryShadowLayerController`, `rimShadowController`, `rimShadowMaskController` field names (Swift reflstr). Rim + drop shadow, values UNKNOWN.
- `Assets.car` contains only AppIcon renditions, no platter/indicator images (assetutil). H
- Running indicator `DOCKIndicatorLayer updateIndicatorForSize:` (asm@0x10000ada8): if tile size < 33 pt then 3x3 pt, cornerRadius 1.5, else 4x4 pt, cornerRadius 2.0 (`setBounds:` / `setCornerRadius:` stubs confirmed by REA list_names). H. Colour adapts via `dockBackgroundChanged`, value UNKNOWN.
- Tile size default (asm@0x1000085d4): `tilesize` absent => 64 pt, or 52 pt when main display height <= 800 pt; valid if 0 < v < 257. `largesize` default 128, valid < 513. H
- This Mac's prefs: `tilesize=75`, `largesize=85`, `magnification=1`, `autohide=0`. H
- Public glass API exists: `NSGlassEffectView` (cornerRadius, clipsToBounds, `Legibility.standard/.increased/.tintAmount`) and SwiftUI `.glassEffect`. H (exports in AppKit)

## 3. Animations
- Dock animates on its own frame loop `DockAnimationThread` + `DockFloatAnimatedProperty`, not CAAnimation, for bar layout/magnify. H
- Attention bounce (`DockGlobals`, asm@0x100245a24): `bounce-duration` default 60, `bounce-secondary-duration` default 3, `bounce-secondary-interval` default 60, converted to double seconds at use (asm@0x100031654 `ucvtf d0`). Reading: critical request bounces ~60 s, then a 3 s bounce burst every 60 s. M (units inferred)
- `no-bouncing` and `launchanim` keys gate bounces; `BounceAppTile not entitled for bundleID` means CoreDockBounceAppTile is entitlement-gated. H
- Window warp animations (minimize "scale", reveal) ease with raised cosine `t' = 0.5 - 0.5*cos(pi*t)` driving `CGSSetWindowWarp` (FUN_100037fd8, ev_191066...). H
- Minimize: `WAGenieAnimation`, `WASuckAnimation`, `genie-speed` default 0.5, `slow-motion-allowed`. H
- Autohide: `autohide-delay` default 0.15 s (asm@0x10006ee6c reads 0.15f), `autohide-time-modifier` default 1.0 multiplied by 60 (asm@0x10025882c). H
- Magnification curve constants: UNKNOWN. Settle with a 120 fps screen recording of hover at fixed tilesize/largesize, or a later decompile of `DockBar` layout.
- Launch bounce height/period: UNKNOWN (`_bounceDur`, `_bouncePeriod` ivars exist). Settle by frame-stepping a recording.

## 4. Data sources
- Running apps: private LaunchServices `_LSCopyRunningApplicationArray`, `_LSScheduleNotificationOnQueueWithBlock`, `_LSCopyApplicationInformation`, `_LSCopyFrontApplication`, `_LSIsApplicationRunning` (imports). H. Public: `NSWorkspace.shared.runningApplications` (KVO) + didLaunch/didTerminate/didActivate notifications, filter `activationPolicy == .regular`; `isFinishedLaunching` ends a launch bounce.
- App badges: apps call `NSDockTile.badgeLabel` -> `CoreDockSetProcessLabel` (log `SetProcessLabel psn=...`). Notification badges come from usernoted over `com.apple.usernoted.dock` (`DockNotificationCenterBadgeConnection`). H
- Dock republishes badges as AX: `AXApplicationDockItem` with `AXStatusLabel`, `AXIsApplicationRunning`, `AXProgressValue`, `AXURL`. H. Third-party path: Accessibility permission, read Dock process AX tree (works while native Dock is autohidden). Public-with-TCC, no SPI.
- usernoted DB exists at `~/Library/Group Containers/group.com.apple.usernoted/db2/db` (+wal/shm). Schema only: `app(app_id, identifier, badge)`, `record(rec_id, app_id, uuid, data BLOB, request_date, delivered_date, presented, style, ...)`, `delivered/displayed/requests/snoozed(app_id, list BLOB)`, `categories`, `dbinfo`. Contents not read. H. Reading it needs Full Disk Access and is undocumented; prefer AX badges.
- "Held notifications" popover: no public API to intercept/suppress other apps' notifications; Focus filters are the public lever. UNKNOWN beyond that.
- Recents: `recent-apps` array in `com.apple.dock` prefs (readable via `UserDefaults(suiteName:"com.apple.dock")`), `show-recents`, `show-recent-count`. H
- Attention requests from other apps: no public signal found; only Dock receives `DOCKAppNeedsAttentionEvent`. UNKNOWN.

## 5. Hiding / coexisting with the native Dock
- HIServices exports `CoreDockSetAutoHideEnabled`, `CoreDockGetAutoHideEnabled`, `CoreDockSetTileSize`, `CoreDockSetOrientationAndPinning`, `CoreDockSetMagnificationEnabled`, `CoreDockGetRect`, `CoreDockIsDockRunning` (dyld_info). H
- Dock handles these live (`DOCKAutoHideEnabledEvent` / `DOCKAutoHideDisabledEvent`), no restart. H
- Pref keys read: `autohide`, `autohide-delay`, `autohide-time-modifier`, `static-only`, `orientation`, `tilesize`, `largesize`, `magnification`, `mineffect`, `launchanim`, `show-process-indicators`, MDM locks `*-immutable`. H
- `autohide-delay` is read in an init path (asm@0x10006ee64), so changing it via `defaults` needs `killall Dock`. M
- Safest reversible recipe: at launch store `CoreDockGetAutoHideEnabled()`, call `CoreDockSetAutoHideEnabled(true)`; on quit/crash restore. Optional one-time `defaults write com.apple.dock autohide-delay -float 1000` + Dock restart, restore by `defaults delete`. Never edit system files.
- Do not use `static-only` or hiding with opacity hacks; Dock still owns Cmd-Tab, Mission Control, minimized windows and hot corners.

## 6. Things clones usually miss
- Hover label is a "cartouche": glass `cartouchePopover` capsule with shadow, side-aware (`ECCartoucheSide`, `ECCartoucheSize`), radius from `cartoucheRadiusFor:`. H
- Right-click menu (`DockMenus.plist` key `process`): [Not Responding] / Options > (Keep in Dock, Remove from Dock, Open at Login, Show in Finder) / --- / Show All Windows, Show Recents, Hide, Hide Others, Show, Open, Quit (Option: Force Quit). Window list and Assign To are added in code. H
- Remove-from-Dock "poof" sound: `/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/poof item off dock.aif` (also `drag to trash.aif`). H
- Spring-loading: `com.apple.springing.enabled` / `.delay`, `enable-spring-load-actions-on-all-items`, `spring-to-expose`. H
- Mouse "dig" to reveal: `digduration-duration` 0.25, `-perframe` 0.10, `-angle` 25 (asm@0x10006ee7c..0x10006eeac). H
- Stage Manager: Show Desktop relays to WindowManager when SM is on (`Relaying showDesktop to WM (StageManager enabled)`). H
- Respects Reduce Motion (`axReduceMotion` swaps in a cross-fade window) and Reduce Transparency (legacy floor). H
- Single-click on running app with no windows reopens; `minimize-to-application` changes window tiles. H

## Implementation recipe
- Panel: `NSPanel(styleMask: [.borderless, .nonactivatingPanel])`, `level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))` (20), `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]`, `isFloatingPanel = true`, `hidesOnDeactivate = false`, `becomesKeyOnlyIfNeeded = true`, override `canBecomeKey/Main` = false, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`.
- App: `LSUIElement = YES`, `NSApp.setActivationPolicy(.accessory)`; use `NSTrackingArea` for hover, no activation on click.
- Popover: a second non-activating panel at level 20 (or `.popUpMenu` for the held-notifications card), anchored above the platter.
- Platter: AppKit `NSGlassEffectView` (cornerRadius ~ tile/2 + inset, measure) or SwiftUI `GlassEffectContainer` + `.glassEffect(.regular, in: .capsule)` per pill so adjacent pills merge like the Dock SDF union. Private `GlassMaterialProvider.Configuration.dock` is the exact look; avoid it for shipping.
- Tiles: default 64 pt (52 pt on <= 800 pt displays), or read the user's `tilesize`/`largesize`; icons via `NSWorkspace.icon(forFile:)`.
- Indicator: 4x4 pt circle (3x3 below 33 pt tiles), corner radius = half, under icon; colour from `.labelColor` at reduced opacity (verify).
- Easing: cosine ease-in-out for reveal/scale; magnification and launch bounce need measurement.
- Data: NSWorkspace for running/active apps; AX (`AXStatusLabel` on Dock's `AXApplicationDockItem`) for badges; `com.apple.dock` `recent-apps` for recents.
- Native Dock: `CoreDockSetAutoHideEnabled` SPI with saved/restored state; public alternative is `defaults write com.apple.dock autohide -bool true` + `killall Dock` behind explicit user consent.
- Sounds: play the system `poof item off dock.aif` on drag-out removal.

## Open UNKNOWNs and how to settle
- Platter radius, insets, shadow params, indicator colour: screenshot pixel measurement at 2 tile sizes, light and dark.
- Magnification falloff and launch bounce curve: 120 fps capture, fit curve.
- Exact tag bits on the main bar window: `CGSGetWindowTags` on the Dock window from a user process (read-only), if acceptable.
