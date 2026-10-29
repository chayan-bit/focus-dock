# How far FocusDock can take over the macOS UI (REA, macOS 27.0 / 26A428, M4)

Question: can one native Swift process own the desktop Omarchy-style, instead of orchestrating AeroSpace, JankyBorders, Shortcuts and config edits?
Scope: static RE of shipped binaries plus read-only probes; nothing injected, no setters called, no settings changed.
Companion to [rea-dock.md](rea-dock.md) (Dock look and feel) and [omarchy-macos.md](omarchy-macos.md) (feature map).

## 0. Method and tags

- Injecting third-party arm64e code into Apple processes (what yabai's scripting addition needs) requires SIP relaxed; even then a self-built binary cannot carry Apple-private entitlements while AMFI enforces them (the default), and system files stay sealed while Authenticated Root is on.
- FocusDock never asks the user to relax SIP, so every finding that needs injection is tagged SIP and treated as unavailable.
- Frameworks live in the dyld shared cache, so SkyLight, HIServices, CoreGraphics, WindowManager.framework etc. were read with `dyld_info -exports/-imports/-objc/-disassemble` straight from the cache.
- Standalone executables (Dock, MenuBarAgent) were opened in REA with Ghidra 12.1.2; Evidence IDs are `ev_*`.
- Dock sha256 `b704affb...e33e` (same build as rea-dock.md); MenuBarAgent sha256 `7bb3f595...1007`.
- Probe [`tools/rea/probe.m`](../../tools/rea/probe.m): `dlsym` for 145 symbols plus getter-only calls; 141 found, the 4 misses explained below.
- Public sources read at HEAD: asmvik/yabai (koekeishiya now redirects there) `dd84572` 2026-06-14, FelixKratz/JankyBorders `a7297ca` 2026-05-14, FelixKratz/SketchyBar `a18fc94`, nikitabobko/AeroSpace `74a1bf1`, jordanbaird/Ice `11edd39` 2025-09-20.
- Tags: PUBLIC, TCC (public API behind Accessibility / Screen Recording / Input Monitoring / Automation / Full Disk Access), SPI (private symbol callable from our process, no SIP change), SIP (needs injection into an Apple process or an entitlement we cannot hold), IMPOSSIBLE.
- Confidence: H read directly from code/data, M strong static inference, L plausible, UNKNOWN with the runtime test that settles it.

## 1. The one fact that decides everything: the universal owner

- Dock's startup function `FUN_10002c95c` calls `CGSSetUniversalOwner()` and `_exit(-1)`s if it fails; that is the only caller (ev_a669ea46, ev_0c915eb7, ev_88bbae9b). H
- SkyLight (which also contains the WindowServer server, `WindowServer` just imports `_SLXServer`) carries the entitlement string `com.apple.private.skylight.universal-owner`. H
- Of the UI agents only Dock holds it (`codesign` entitlements: Dock has `com.apple.private.skylight.universal-owner`; WindowManager has `...skylight.windowmanager`, SystemUIServer `...skylight.statusbar`, MenuBarAgent `...skylight.menubaragent`). H
- Reading: only the universal-owner connection may mutate other processes' windows (alpha, tags, level, transform, space membership); everyone else may only read them and mutate their own windows. M (server-side check not decompiled; matches why yabai runs those ops inside Dock).
- So "SIP" in this doc means "requires SIP relaxed, to run inside Dock (or another entitled Apple process) via injection"; a self-signed private entitlement is not an option while AMFI enforces entitlements.

## 2. Windows and Spaces (SkyLight / CGS)

### What exists on this build
- 1647 SLS/SLPS symbols exported from SkyLight and 913 `CGS*` from CoreGraphics (`skylight.exports`, `cg.exports`). H
- Every SLS/CGS symbol used by yabai (100), JankyBorders (68) and SketchyBar (88) resolves on macOS 27 except four, all benign. H
- `CGSGetConnectionPortById` and `SLSPerformAsynchronousBridgedWindowManagementOperation` are not exported but exist as local symbols; yabai finds them by walking the in-memory symtab and our probe found the latter the same way. H
- `SLSGetWindowSubLevel__Internal` is a yabai-internal helper, and `SLSBridgedMoveWindowsToManagedSpaceOperation` is an ObjC class (probe: class FOUND). H
- Nothing yabai/JankyBorders/SketchyBar call has vanished; what changed is new API, below.

### New on 26/27: the window-management bridge
- SkyLight now has ~80 `SLSBridged*Operation` NSSecureCoding classes covering SpaceCreate/Destroy, Show/HideSpaces, ManagedDisplaySetCurrentSpace, MoveWindowsToManagedSpace, SpaceSetTransform/Alpha/AbsoluteLevel, SpaceAddOwner, plus `SLSWindowManagementFallbackBridge` and prefs `SLSEnableWMBridgedOperations` / `ForceWMBridge`. H
- WindowManager.app implements `performAsynchronousBridgedWindowManagementOperation:` and `performSynchronousBridgedWindowManagementOperation:replyHandler:` and logs `client pid %d missing entitlement` for some calls. H
- Reading: Spaces management is moving from Dock to WindowManager.app over this bridge, with a direct-to-WindowServer fallback. M
- yabai 7.1.25 changelog: "moving windows between spaces works with SIP enabled again" via exactly this async bridged operation. H (source); works on 27: UNKNOWN, settle by one `SLSBridgedMoveWindowsToManagedSpaceOperation` on a scratch window of our own and reading `SLSCopySpacesForWindows` back.

### Capability table
| Capability | Mechanism | Tag | Evidence |
|---|---|---|---|
| Enumerate all windows, frames, owners, levels, spaces | `CGWindowListCopyWindowInfo` (titles need Screen Recording) or `SLSWindowQueryCreate` + `SLSWindowIterator*` | PUBLIC / SPI | probe: 135 windows; exports H |
| Move/resize other apps' windows | AX `kAXPositionAttribute`/`kAXSizeAttribute` | TCC | AeroSpace, yabai do this H |
| Move/resize via SLS (`SLSMoveWindowWithGroup`, `SLSSetWindowTransform`) | only from Dock | SIP | yabai payload.m 643, 626 H |
| Observe window create/destroy/move/resize/level/hide, space change | `SLSRegisterNotifyProc` events 804-816, 1325/1326, 1401 + `SLSRequestNotificationsForWindows` | SPI | JankyBorders events.c/h H |
| Per-window alpha, shadow, level, sticky (tags) on foreign windows | `SLSSetWindowAlpha/Tags/SubLevel`, `SLSSetWindowShadowParameters` | SIP | yabai payload.m 670-808 H |
| Same on our own windows | NSWindow API or SLS on own cid | PUBLIC / SPI | H |
| Overlay drawn relative to a foreign window | own window + `SLSTransactionOrderWindow` relative to target | SPI | JankyBorders yabai.h:95 H |
| Enumerate Spaces, current Space | `SLSCopyManagedDisplaySpaces`, `SLSGetActiveSpace` | SPI | probe: 1 display, 1 space H |
| Switch to an adjacent Space with native animation | synthetic `kCGSEventDockControl` DockSwipe CGEvents | TCC | section 9 H |
| Jump to arbitrary Space, create/destroy user Spaces, reorder | `SLSManagedDisplaySetCurrentSpace`/`SLSShowSpaces` + Dock-internal `add_space`/`remove_space`/`move_space` | SIP | yabai payload.m 433-583 H |
| Move window to another Space | bridged op (no SA) or SA fallback | SPI (UNKNOWN on 27) / SIP | yabai space_manager.c 667-695 H |
| Window and Space transactions, Space-level transform/alpha | `SLSTransaction*`, `SLSTransactionSetSpaceTransform` | SPI own surfaces, SIP for user Spaces | Dock imports these H |

### yabai's scripting addition on THIS build
- `verify_os_version` accepts only majors 12-15 and 26 on arm64, so the shipped SA refuses macOS 27 outright. H (payload.m 220-262)
- Static replay of its macOS 26 byte patterns over this Dock ([`tools/rea/sa_scan.py`](../../tools/rea/sa_scan.py), arm64e slice, M4 = cpusubtype 2):
- `dock_spaces` still hits inside its window (0x30a98); `dppm` 0x509fc, `fix_animation` 0x227508, `add_space` 0x228cbc, `remove_space` 0x18b9a0, `move_space` 0x18c554 all match only before the 26 start offsets; `set_front_window` matches nowhere. H
- So 6 of 7 lookups would fail even with the version gate patched; the functions still exist but moved. M
- Dock is now fat `arm64e` + `arm64e.x1`; the x1 slice matches even fewer patterns, so any port must handle both. H

### Recommendation (windows and Spaces)
- Use real Spaces, not off-screen parking: enumerate with `SLSCopyManagedDisplaySpaces`, switch with synthetic DockSwipe gestures (TCC), move windows with the bridged move op (SPI, verify), and AX for frames (TCC).
- Pre-create N Desktops once by hand in Mission Control (FocusDock cannot create them without SIP), then bind modes to Space indices.
- Draw borders ourselves the JankyBorders way (own SLS windows + notify procs + relative ordering, SPI) and drop JankyBorders.
- Keep AeroSpace only as the tiling engine during migration; its off-screen parking is what the user rejects, so FocusDock's own tiler on top of real Spaces replaces it.
- Do not ship a yabai-style SA: it is SIP, needs re-finding 7 patterns per OS point release on two slices, and is unsupported on 27 today.

## 3. Menu bar

- macOS 27 hosts status items in a new agent, MenuBarAgent (feature flag `MenuBar/MenuBarQFA`), not SystemUIServer. H (LaunchAgent plist, `launchctl print`)
- MenuBarAgent strings: `StatusItemHost`, `ComponentStatusItem*`, `EnableStatusItemEventForwarding`, `listMenuBarItemsForSpaceID:completionHandler:`, `Disallowed application %{public}s`, hide/reveal-hidden-items buttons, `ShowSoftwareNotch`. H (ev_1ced5edb)
- Its XPC services check `Connection missing entitlement: %{public}s pid: %d`; `MBMenuBarItemManager` lives in MenuBarClientCore and the gate strings include `com.apple.private.menubar.allow` (held by SystemUIServer). H (ev_07a0f583, codesign)
- So listing/mirroring other apps' status items through Apple's own channel is SIP; macOS 27 already ships Ice-style hiding natively. M
- Ice (last commit 2025-09-20, pre-26) moves items by posting synthetic Cmd-drag CGEvents and reads `CGSGetProcessMenuBarWindowList`; works on 27 UNKNOWN. H/UNKNOWN
- SkyLight exports `CGSSetMenuBarAutohideEnabled`, `CGSGetMenuBarAutohideEnabled`, `CGSSetMenuBarBounds`, `CGSSetMenuBarCompanionWindow`, `SLSSetMenuBarUseBlurredAppearance`. H
- Reading other apps' menus: AX `kAXMenuBarAttribute` / `AXMenuBarItem` / `AXPress`. TCC. H (public API)
- Status items of other apps: each is a window owned by that app at the status level; image via ScreenCaptureKit (Screen Recording), click via AX `kAXExtrasMenuBarAttribute` + `AXPress`. TCC. M
- Notch: `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea/RightArea` are public; a panel may draw beside the notch, not in it. PUBLIC. H

### Recommendation (menu bar)
- Draw our own full-width glass bar as a non-activating panel at `NSWindow.Level.statusBar` (25) on top of the system bar region, honour the notch via `safeAreaInsets`. PUBLIC.
- Hide Apple's bar by the user setting "Automatically hide the menu bar: Always"; calling `CGSSetMenuBarAutohideEnabled` is SPI and a setter on system state, keep it opt-in.
- App menus: render the frontmost app's AX menu tree in our bar (TCC), as a command-bar section.
- Third-party status items: show AX + ScreenCaptureKit mirrors (TCC); native hosting is SIP. Nothing external kept.

## 4. Notifications

- NotificationCenter.app holds `com.apple.usernotificationsvendor.listener`, `com.apple.private.usernotifications.forwarding`, `com.apple.usernotifications.alert-coordination` and a dozen `com.apple.private.donotdisturb.*` entitlements. H (codesign)
- UserNotificationsCore gates observation with `com.apple.private.usernotifications.observation` / `.systemservice` / `.coreservice`. H (cstrings)
- Public `UNUserNotificationCenter` sees only our own notifications. H
- usernoted DB (`group.com.apple.usernoted/db2/db`) readable with Full Disk Access, schema in rea-dock.md 4. TCC, M (undocumented format).
- Banners and the NC panel are AX-visible windows of NotificationCenter; reading text and pressing action buttons via AX is TCC. M (settle with Accessibility Inspector on a live banner).
- Suppressing banners: a Focus is the only supported lever; DND services (`DNDModeAssertionService`, `DNDModeConfigurationService`) are exported but entitlement-gated. Focus via a user Shortcut + `/usr/bin/shortcuts run` is PUBLIC; direct DND control is SIP.
- Recommendation: a per-mode Focus (Shortcuts) silences banners, FocusDock reads delivered items from the DB (FDA) and live banners via AX, renders its own cards, and acts through AX. Shortcuts stays, because nothing else can toggle Focus without SIP.

## 5. Control Center and system controls

| Control | Mechanism | Tag | Evidence |
|---|---|---|---|
| Volume, mute, output device | CoreAudio `AudioObjectSetPropertyData` | PUBLIC | public API |
| Built-in display brightness | `DisplayServicesSetBrightness[Smooth]` | SPI | DisplayServices exports H |
| External display brightness | DDC/CI over IOAVService | SPI | L (not examined) |
| Night Shift, True Tone | `CBBlueLightClient`, `CBTrueToneClient` (CoreBrightness) | SPI | exports H; `nightlight` CLI works without entitlement M |
| Wi-Fi power, scan, join | CoreWLAN `CWInterface setPower:` | PUBLIC (SSID needs Location) | exports H |
| Bluetooth power | `IOBluetoothPreferenceSetControllerPowerState` | SPI | IOBluetooth exports H |
| Focus state read / set | `INFocusStatusCenter` read (TCC) / Shortcuts set; `DNDStateService` | TCC / PUBLIC / SIP | exports + entitlements H |
| Dark/light appearance | System Events AppleScript, or `SLSSetAppearanceThemeLegacy` | TCC (Automation) / SPI | SkyLight exports H |
| Accent / highlight colour | `AppleAccentColor` global default + distributed notification; running apps refresh unevenly | PUBLIC (UNKNOWN coverage) | settle by toggling once and screenshotting 5 apps |
| Wallpaper (also the lock screen picture) | `NSWorkspace.setDesktopImageURL` | PUBLIC | loginwindow pulls `remoteDesktopPictureForDisplay` from Dock H |
| Control Center modules themselves | ControlCenter.framework + `com.apple.private.controlcenter.*` | SIP | entitlements H |
- Recommendation: own panels for audio, network, Bluetooth, display, appearance and Focus using the rows above; ship SPI rows behind a capability check (`dlsym` at launch, hide the widget if missing).

## 6. Global input

- Hotkeys: Carbon `RegisterEventHotKey` is PUBLIC, needs no TCC, and still fires while Secure Input is on. M (prior; settle by enabling Secure Keyboard Entry in Terminal and pressing a bound key).
- `CGEventTap` listen-only needs Input Monitoring, active taps need Accessibility; under Secure Input (`IsSecureEventInputEnabled`, `CGSIsSecureEventInputSet`) taps stop seeing keystrokes. TCC. H (exports) / M (behaviour)
- Remapping: `/usr/bin/hidutil property --set '{"UserKeyMapping":[...]}'` is PUBLIC, per-boot, no TCC. H
- A true Hyper chord (one key = Cmd+Ctrl+Opt+Shift) cannot be expressed in hidutil, it needs an active event tap (TCC, dies under Secure Input) or Karabiner's DriverKit virtual keyboard.
- Native shortcut ownership: `CGSSetSymbolicHotKeyEnabled` (SPI) disables system hotkeys by id; AltTab uses ids 1 and 2 for Cmd-Tab / Cmd-Shift-Tab (probe: `CGSIsSymbolicHotKeyEnabled(1)` is callable). H
- Recommendation: hidutil Caps Lock -> F18 at login (PUBLIC), F18-prefixed Carbon hotkeys for the leader layer (works under Secure Input), an optional event-tap Hyper for chords (TCC); Karabiner only if the user insists on chord semantics during password entry.

## 7. Mission Control, Exposé, Cmd-Tab, Stage Manager

- Dock still owns Mission Control/Exposé UI (`ExposeCoordinator`, `SpaceSwitcher`, `FluidGestureController`, `SpaceSwitchTransition`) and Stage Manager lives in WindowManager.app. H (ev_be5fafe5, rea-dock.md)
- `CoreDockSendNotification` (HIServices export) accepts `com.apple.expose.awake`, `com.apple.expose.front.awake`, `com.apple.showdesktop.awake`, `com.apple.launchpad.toggle`. SPI to trigger, not to restyle. H (ev_6afea464)
- Restyling or replacing their rendering means code inside Dock/WindowManager: SIP.
- Cmd-Tab: disable natively with `CGSSetSymbolicHotKeyEnabled(1/2, false)` (SPI) and draw our own switcher from `NSWorkspace` + window list + ScreenCaptureKit thumbnails (TCC).
- Stage Manager toggle is a user preference (`com.apple.WindowManager`), not something to automate.
- Recommendation: build our own overview (thumbnails of real Spaces via SCK, TCC) and switcher; trigger Apple's Mission Control only as a fallback.

## 8. Lock screen and login window

- loginwindow reads `LoginwindowText` from `com.apple.loginwindow` (admin pref) and shows the user's desktop picture, fetched from Dock. H (strings)
- `SACLockScreenImmediate` (login.framework export) locks the screen. SPI. H
- The lock UI itself is loginwindow code on a sealed system volume; replacing assets needs SSV disabled. IMPOSSIBLE for FocusDock.
- Recommendation: theme it by wallpaper and LoginwindowText only; lock via `SACLockScreenImmediate` or the Ctrl-Cmd-Q keystroke.

## 9. Animation

### 9.1 Real Spaces with the native slide
- Dock drives Space slides from `DOCKGestureEvent`s (`kDGSwipeLeft/RightGesture`, `fluidGestureStart/Progress/End:`) through `FluidGestureController`, a `SpringBehavior` (`dampingRatio`, `response`, `settlingDuration`) and `SLSTransactionSetSpaceTransform`/`SetManagedDisplayCurrentSpace`. H (ev_be5fafe5, Dock imports)
- A third-party app can feed that path: post `CGEvent`s with field 55 = 30 (`kCGSEventDockControl`), 110 = 23 (DockSwipe), 123 = 1 (horizontal), progress 124, velocity 129, phase 132 Began/Changed/Ended to `kCGSessionEventTap`. H (yabai space_manager.c 945-969, attributed to InstantSpaceSwitcher/BetterTouchTool)
- yabai uses velocity 9999 to skip the animation; a modest velocity with stepped progress gives Apple's own animated slide, and we can scale it. M (settle: post one Began/Changed x10/Ended sequence and screen-record).
- Requirement: posting events needs Accessibility. TCC. It only moves one Space per gesture, so a jump of k Spaces is k chained gestures (or one instant jump plus our own cross-fade).
- Ctrl+Arrow / Ctrl+N synthesis also works (TCC) but uses Apple's fixed timing and needs the "Switch to Desktop N" shortcuts enabled.
- `SLSManagedDisplaySetCurrentSpace`/`SLSShowSpaces` from our connection switch without any animation and are owner-gated: SIP. `SLSSpaceCreate` from our connection creates a private, non-Mission-Control space (SPI) that we may own, layer and transform, useful for overlays, not for user Desktops. M

### 9.2 Animating other apps' windows
- yabai's `window_animation_duration`: capture the window with `SLSHWCaptureWindowList` (Screen Recording), make a proxy window on a fresh connection, animate it per CVDisplayLink frame with `SLSTransactionSetWindowTransform`/`Alpha`, then one real AX `setFrame`. H (window_manager.c 463-700)
- The proxy swap (hide real window via `SLSTransactionSetWindowSystemAlpha` on the foreign wid) goes through the SA; without it the real window stays visible under the proxy. So: proxy animation SPI + TCC, clean swap SIP. H
- Our variant without SA: snapshot with ScreenCaptureKit (TCC), place the proxy above, move the real window once via AX while the proxy covers it, cross-fade out. Seams show for ~1 frame when the app repaints late. M
- AX `setFrame` per frame is not viable: each call is a synchronous IPC into the target app which relayouts; expect 15-40 fps with tearing on heavy apps. M (settle: time 60 `AXUIElementSetAttributeValue` calls on Safari).
- Opacity, scale, shadow on foreign windows (`SLSSetWindowAlpha`, `SLSSetWindowTransform`, shadow params): SIP; on proxies we own: SPI.

### 9.3 Our own surfaces
- Dock, bar, command bar, cards, overlays are our windows: SwiftUI springs / CoreAnimation (`CASpringAnimation`, which Dock itself imports) are all we need. PUBLIC.
- Known system timings: Dock autohide delay 0.15 s, reveal/scale ease `0.5 - 0.5 cos(pi t)`, bounce 60 s + 3 s bursts (rea-dock.md 3).
- Space slide spring (`response`, `dampingRatio`), Mission Control enter/exit and magnification curves are compiled-in Swift constants: UNKNOWN; settle with a 120 fps screen recording of each, fitted to a damped spring, or by enabling Dock's `log-perf-spaceswitch` pref on a test account.
- Respect `NSWorkspace.accessibilityDisplayShouldReduceMotion` (Dock swaps in cross-fades, rea-dock.md 6).

### 9.4 Motion config shape
```jsonc
"motion": {
  "speed": 1.0,                       // global multiplier, 0 = instant
  "reduceMotion": "system",           // system | always | never
  "defaults": { "spring": { "response": 0.35, "damping": 0.86 } },
  "elements": {
    "workspace.switch": { "via": "dockSwipe", "velocity": 1.0 },
    "dock.magnify":     { "spring": { "response": 0.25, "damping": 0.8 } },
    "window.move":      { "via": "proxy", "duration": 0.22, "curve": "easeInOutCos" },
    "card.enter":       { "spring": { "response": 0.4, "damping": 0.75 } } } }
```

## 10. Verdict per area (what FocusDock uses, what stays external)

| Area | Native mechanism | Tag | Keep external? |
|---|---|---|---|
| Spaces | real Spaces, DockSwipe switch, bridged move, AX frames | TCC + SPI | AeroSpace only until our tiler lands |
| Borders | own SLS windows + notify procs | SPI | drop JankyBorders |
| Window animation | SCK proxy + single AX move | TCC + SPI | none |
| Menu bar | own glass bar, AX menus, SCK status mirrors | PUBLIC + TCC | none |
| Notifications | Focus + DB + AX cards | PUBLIC + TCC | Shortcuts for Focus |
| System controls | CoreAudio, CoreWLAN, DisplayServices, CoreBrightness, IOBluetooth | PUBLIC + SPI | none |
| Input | hidutil + Carbon hotkeys (+ optional tap) | PUBLIC (+ TCC) | Karabiner optional |
| Overview / switcher | own SCK overview, symbolic hotkey off | TCC + SPI | none |
| Lock screen | wallpaper + LoginwindowText | PUBLIC | n/a |

## 11. Open UNKNOWNs and the evidence that settles them
- Bridged `MoveWindowsToManagedSpace` from a non-entitled client on 27: one call on our own scratch window, read back `SLSCopySpacesForWindows`.
- Animated (non-instant) DockSwipe sequence and its velocity response: post a Began/Changed/Ended sequence, record at 120 fps.
- Server-side universal-owner gate (no read-only test exists): from a second process call `SLSSetWindowAlpha` on a window of a throwaway test app we own and check the returned CGError.
- Ice-style Cmd-drag of status items under MenuBarAgent: try on a test status item.
- Notification banner AX tree on 27: Accessibility Inspector on a live banner.
- Space slide and Mission Control spring constants: 120 fps recordings.
- Reusable probe sources live in [`tools/rea/`](../../tools/rea/) (`probe.m`, `sa_scan.py`, `strxref.py`); symbol dumps and third-party checkouts are regenerated locally and never committed.
