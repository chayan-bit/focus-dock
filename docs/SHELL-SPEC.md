# FocusDock Shell - spec v2 (draft, 2026-10-28; amended 2026-10-29 with the Phase 4 spike results and the Phase 5 resolutions)

Spec v2 turns FocusDock from "a dock that drives other tools" into a fully native macOS shell: one Swift process that owns Spaces, borders, bar, switcher, notifications, system controls, a fleet view and an agent console, Omarchy-style.
It supersedes spec v1 (git history); [SPEC.md](SPEC.md) stays the source of truth for the dock, modes, activity and notification classification, and [THEMES.md](THEMES.md) for the theme contract.
Evidence: [research/rea-macos-ui.md](research/rea-macos-ui.md) (REA teardown of the macOS 27 UI, every finding tagged), [research/fleet-agent.md](research/fleet-agent.md) (fleet view and agent console), [research/omarchy-macos.md](research/omarchy-macos.md) (feature map), [research/rea-dock.md](research/rea-dock.md) (Dock look and feel), [research/spike-v2.md](research/spike-v2.md) and [research/spike-v2-s14.md](research/spike-v2-s14.md) (Phase 4 spike on macOS 27, S1-S14).
Tags come from rea-macos-ui.md: PUBLIC, TCC (public API behind a privacy permission), SPI (private symbol callable from our own process), SIP (needs SIP relaxed), IMPOSSIBLE.

## 1. Goals and non-goals

Goals:
- A UI-level experience in the spirit of Thariq's FocusDock demo and Omarchy, not glued tools: every surface the user touches is drawn by FocusDock.
- Every transition animates smoothly and natively; no window is ever parked off-screen (AeroSpace's model, rejected).
- Maximum customisability: layout, widgets, hotkeys, motion and theme tokens of every surface are config, live-reloaded and validated, with errors shown in the UI.
- A terminal-style view of every SSH-connected machine with live status, and an integrated agent with a full native UI that can act on the Mac and on those machines under explicit approval.
- Fail safe: any system state FocusDock changes is restored when it quits or crashes.

Non-goals:
- Requiring SIP relaxed, shipping a scripting addition, or injecting into any Apple process; SIP-tagged findings are listed in 3.2 and not planned.
- Replacing or restyling the lock screen, Mission Control, Control Center modules or system notification banners.
- App Store distribution (we call SPI) and managed-Mac deployment.
- Multi-monitor in the first cut of each surface; the data model is per display from day one.

## 2. What exists today (Phases 0-3 shipped)

- Dock shell: glass panel at the Dock's window level with measured metrics, running dots, hover cartouche, native Dock autohidden with a watchdog that restores it.
- Modes: `modes.json` with hot reload and validation, mode pills, the countdown state machine, a menu bar status item, Focus via one Shortcut per Focus.
- Windows: AeroSpace workspaces per mode through `AeroSpace.swift` (CLI plus `subscribe` events).
- Themes: Omarchy-compatible engine with atomic swap and live retint of FocusDock, WezTerm, Neovim, Zed, btop, JankyBorders, wallpaper and Claude Code.

## 3. Capability matrix

### 3.1 What FocusDock uses

| Surface | Technique | Tag | Permission |
|---|---|---|---|
| Spaces: list, current | `SLSCopyManagedDisplaySpaces`, `SLSGetActiveSpace` | SPI | none |
| Spaces: switch with the native slide | synthetic DockSwipe events in the 27 format (IOHID fluid-gesture payload under tag 4205 plus a companion field 55 = 29 gesture event, ported from InstantSpaceSwitcher, MIT; fields 55 = 30 and 110 = 23 alone are ignored on 27) to the session tap, spike S2 | TCC | Accessibility |
| Spaces: instant jump | the same DockSwipe with Ended velocity 9999: one frame, no slide; 3 Desktops take 329 ms (spike S2) | TCC | Accessibility |
| Window to another Space | `SLSBridgedMoveWindowsToManagedSpaceOperation`: works on 27 for any window, async, about 13 ms (spike S1) | SPI | none |
| Window frames, raise, focus | AX position, size, `kAXRaiseAction` | TCC | Accessibility |
| Window events | `SLSRegisterNotifyProc` + `SLSRequestNotificationsForWindows`, AX observers | SPI / TCC | Accessibility |
| Borders | own windows ordered relative to the target via `SLSTransactionOrderWindow` (JankyBorders method) | SPI | none |
| Foreign window animation | ScreenCaptureKit snapshot proxy, destination covered by a snapshot of what is behind it, one AX move under it, cross-fade | TCC + SPI | Screen Recording, Accessibility |
| Own surfaces animation | SwiftUI springs, `CASpringAnimation`, display-link pacing | PUBLIC | none |
| Bar | non-activating panel at `NSWindow.Level.statusBar`, notch via `safeAreaInsets` and auxiliary top areas | PUBLIC | none |
| Bar: app menus | AX `kAXMenuBarAttribute` tree + `AXPress` | TCC | Accessibility |
| Bar: third-party status items | SCK capture of MenuBarAgent's bar window cropped to each item's AX frame (status items have no window of their own on 27), click via `kAXExtrasMenuBarAttribute` + `AXPress` | TCC | Screen Recording, Accessibility |
| Hide Apple's menu bar | user setting "Automatically hide: Always", or opt-in `CGSSetMenuBarAutohideEnabled` | PUBLIC / SPI | none |
| Notifications: silence | per-mode Focus via one Shortcut | PUBLIC | none |
| Notifications: read | usernoted DB read-only copy; live banners via AX | TCC | Full Disk Access, Accessibility |
| Volume, mute, output | CoreAudio | PUBLIC | none |
| Built-in brightness | `DisplayServicesSetBrightness[Smooth]` | SPI | none |
| Night Shift, True Tone | `CBBlueLightClient`, `CBTrueToneClient` | SPI | none |
| Wi-Fi | CoreWLAN | PUBLIC | Location (SSID only) |
| Bluetooth power | `IOBluetoothPreferenceSetControllerPowerState` | SPI | none |
| Focus state | `INFocusStatusCenter` read, Shortcut set | TCC / PUBLIC | Focus status |
| Dark or light appearance | `SLSSetAppearanceThemeLegacy` (System Events as fallback) | SPI / TCC | none / Automation |
| Accent colour, wallpaper | `AppleAccentColor` default + notification (live for active AppKit windows with no relaunch, spike S10; the restore ledger deletes the key when it was unset), `NSWorkspace.setDesktopImageURL` | PUBLIC | none |
| Input: leader key | `hidutil` Caps Lock to F18, Carbon `RegisterEventHotKey` | PUBLIC | none |
| Input: Hyper chords (optional) | active `CGEventTap` | TCC | Accessibility |
| Cmd-Tab switcher | `CGSSetSymbolicHotKeyEnabled(1/2, false)` + own panel with live SCK thumbnails for current-Space windows and stale last-seen frames elsewhere (S12) | SPI + TCC | Screen Recording |
| Overview | own panel of SCK thumbnails per real Space (live for current-Space windows, stale last-seen frames elsewhere, S12) | TCC | Screen Recording |
| Mission Control, Show Desktop | `CoreDockSendNotification("com.apple.expose.awake")` and siblings | SPI | none |
| Lock | `SACLockScreenImmediate`, Ctrl-Cmd-Q keystroke fallback | SPI | none |
| Fleet | `/usr/bin/ssh` with a managed ControlMaster per host | PUBLIC | none |
| Agent | `claude -p` stream-json child process with `--permission-prompt-tool stdio` (spike S14) + `focusdock-mcp` stdio shim | PUBLIC | inherits the app's grants |

Every SPI symbol is resolved with `dlsym` at launch into a capability registry; a missing symbol hides the widget or action that needs it and lists it on a Capabilities page, never crashes.
Phase 5: the page is the menu bar's **Capabilities** submenu and `focusdock capabilities`; the native Dock hide resolves CoreDock through the same registry and is skipped when the symbols are gone.
Catalog entries may carry a `minimumOS`; the SPI drift test skips an entry below it, and skipped entries are reviewed by hand.

### 3.2 Not possible without SIP (not planned)

| Want | Why it needs SIP | What we do instead |
|---|---|---|
| Alpha, scale, shadow, level, sticky on other apps' windows | only the universal-owner connection (Dock) may mutate foreign windows; a foreign call returns success and does nothing (spike S3) | effects on our proxies and borders only; any SPI mutation on a foreign window is verified by read-back |
| Hide the real window under an animation proxy | `SLSTransactionSetWindowSystemAlpha` on a foreign window | cover the destination with an SCK snapshot of what is behind it until the proxy lands, then cross-fade (spike S7) |
| Create, destroy or reorder user Desktops | Dock-internal `add_space` / `remove_space` / `move_space` | user creates N Desktops once in Mission Control |
| Host or list status items through Apple's channel | `com.apple.private.menubar.allow` | SCK mirror + AX press |
| Observe all notifications live, control Do Not Disturb directly | `usernotifications.observation`, `donotdisturb.*` entitlements | DB + AX, Focus via Shortcut |
| Restyle Mission Control, Exposé, Stage Manager, Control Center | code inside Dock, WindowManager, ControlCenter | own overview and panels |
| Replace the lock screen UI | loginwindow on the sealed system volume | IMPOSSIBLE; theme via wallpaper and `LoginwindowText` |

Spike S2 removed "jump to any Space instantly, without the slide" from this table: a DockSwipe with Ended velocity 9999 switches in one frame with no SIP (3.1).

## 4. Architecture

### 4.1 Processes
- `FocusDock.app` (`LSUIElement`): one process hosting every surface as a module: dock, bar, command bar, switcher, overview, cards, OSD, borders, fleet view, agent console, wallpaper.
- Watchdog: the same binary in watchdog mode (exists today), extended to replay the restore ledger (4.3) when the parent dies.
- `focusdock` CLI: the same binary with arguments: `theme`, and since Phase 5 `config check [file]`, `restore` and `capabilities`; `space` and `mode` come with Phase 6.
- `focusdock-mcp`: a stdio shim the `claude` CLI launches, forwarding to the app over a 0600 unix socket in `~/.local/state/focusdock/`.
- Children: one `claude` process per agent session; one `ssh` ControlMaster per polled host.
- Pure logic (layouts, motion resolution, policy, config validation, fleet parsing) lives in `FocusDockCore` with unit tests, as today.
- Main-thread rule (spike run D): any synchronous wait on the main thread must pump events (`nextEventMatchingMask` + `sendEvent`), or Carbon hotkeys and AppKit, UserNotifications and ScreenCaptureKit callbacks are lost until it returns; nested run loops must not run inside a GCD main-queue block.
- Quit never waits on the main thread either: `applicationShouldTerminate` returns `.terminateLater`, replays the restore ledger off the main thread, then replies; a replay stuck for 5 s replies anyway and the watchdog finishes it.
- AppKit's `.terminateLater` wait spins the run loop inside `terminate:`, and libdispatch never drains the main queue re-entrantly, so every quit trigger calls `terminate:` from a run-loop block and the reply arrives the same way (`CFRunLoopPerformBlock` in the common modes, which include `NSModalPanelRunLoopMode`), never through the main queue; `scripts/check-quit.sh` guards this.
- Borderless overlay windows must be checked on 27: the spike's borderless marker window never reached the screen (run F).

### 4.2 Permissions onboarding
- Nothing is requested at first launch, Accessibility included: the first module that declares it (Phase 6) asks for it.
- Each module declares the permissions it needs; without them it renders a quiet disabled state with one "Grant" button that opens the exact System Settings pane, and starts working when the grant appears (polled, no relaunch).
- Order offered: Accessibility (Spaces, windows, menus), Screen Recording (animation proxies, switcher, status mirrors), Full Disk Access (notifications), Location (Wi-Fi name), Automation (only if an integration needs it).
- A stable signing identity is required so TCC grants survive rebuilds; `scripts/build-app.sh` signs with `FOCUSDOCK_SIGN_IDENTITY` when it is set (README, Build) and ad hoc otherwise; nothing touches the keychain automatically.
- Probes: Accessibility is `AXIsProcessTrusted` plus `CGPreflightPostEventAccess`; Screen Recording is `CGPreflightScreenCaptureAccess`; Full Disk Access is whether the usernoted db opens; Location is the authorisation status only; Automation is probed per target app when an integration needs it.
- A Screen Recording grant must take effect without a relaunch; this and the Settings pane URLs are checked by hand at acceptance, and a "Relaunch FocusDock" item is added if the preflight stays cached.

### 4.3 Crash restore
- Every setter on system state first appends the original value to `~/.local/state/focusdock/restore.jsonl`: native Dock autohide, menu bar autohide, symbolic hotkeys 1 and 2, the `hidutil` key mapping, Focus, appearance, accent colour (the key is deleted when it was originally unset), Night Shift.
- Clean quit, the watchdog and the next launch all replay the ledger in reverse and truncate it; `focusdock restore` does the same by hand.
- Each restored value is read back before its line is dropped; a key that does not read back stays in the ledger for the next replay.
- At launch the watchdog starts before any setter runs and a stale ledger is replayed before the Dock is hidden; Phase 1-4's `~/Library/Application Support/FocusDock/native-dock.json` is imported into the ledger once, then deleted.
- State that dies with the process needs no entry: borders, proxies, bar, cards.

## 5. Surfaces

### 5.1 Spaces and windows (replaces AeroSpace)
- Real macOS Spaces are the workspaces; modes bind to Space indices (`"space": 3`), which replaces `workspace` in `modes.json` v2 (v1 files keep loading while AeroSpace is the fallback).
- The user creates the Desktops once by hand in Mission Control; FocusDock counts them at launch and shows a card if a mode points at a Space that does not exist.
- Switch: synthetic DockSwipe Began, Changed x10, Ended in the 27 format (3.1) with a velocity from the motion config, so the slide is Apple's own; `workspace.switch` velocity 1 gives the system slide (about 0.54 s), and velocities up to about 4 give the same slide.
- Jump: a jump of k Spaces is k chained gestures, at velocity 9999 for an instant jump (3 Desktops take 329 ms, mostly event posting) or at the configured velocity when the user wants to see the slides; the Dock queues gestures posted during a slide, so chains are not dropped; there is no cap on k and the jump never needs a cross-fade.
- The active-Space change arrives near the end of the slide (about 520 ms at velocity 1), so surfaces that react to Space changes (bar, borders) start from the gesture, never from that notification.
- Move a window to a Space: the bridged move operation, which works on 27 for any window from an unentitled process and is asynchronous (about 13 ms, so wait for the move before acting on it); `SLSMoveWindowsToManagedSpace` only for FocusDock's own windows, since it fails silently on foreign ones; every move is verified by reading `SLSCopySpacesForWindows` back, because foreign SPI calls report success when they did nothing (S1, S3); the moved window leaves the screen without switching the active Space; routing rules (`apps` per mode, plus title and URL rules) run on window-create events.
- Frames: AX; FocusDock's own tiler (layouts `float`, `columns`, `monocle`, per Space, computed in `FocusDockCore`) applies frames through the animated move in 5.2.
- Borders: own transparent windows ordered just above each managed window, following its frame from notify-proc events, colours and width from theme tokens; JankyBorders is dropped.
- AeroSpace stays only as a fallback behind `spaces.engine = "aerospace"` until the native engine has soaked for a week (spikes S1 and S2 passed); then `AeroSpace.swift` and its Nix entry are removed.

### 5.2 Animating other apps' windows
- Capture the window with ScreenCaptureKit and cover the destination with a snapshot of what is behind it (without SIP the real window cannot be hidden, so an uncovered destination shows a double image: 3 of the first 6 frames in spike S7, 0 when covered).
- Show the image in a proxy window at the window's frame, animate the proxy per display-link frame, issue one AX frame change under it, hold the proxy until the destination matches it (at least 3 frames, about 50 ms at 60 Hz), then cross-fade the proxy out.
- Resizes keep the proxy: an AX resize costs p95 12 ms (p50 2.5 ms) on a heavy app and an AX move p95 1.1 ms (spike S7), so one call fits a 60 Hz frame except at the tail, but the call returning does not prove the window was redrawn.
- Per-frame AX position for pure moves is cheap enough to try, pending a visual check.
- Borders and the tiler's neighbours animate on the same clock and motion key, so a tile change reads as one movement.

### 5.3 Dock
- As SPEC.md, plus: every transition (reveal, magnify, bounce, pill expand, countdown, app-set swap on mode change) reads its timing from the motion config.

### 5.4 Bar
- Own full-width glass bar as a non-activating panel at status-window level; segments split around the notch.
- Left: mode, Spaces, the frontmost app's menus (AX tree rendered as our own menu, actions via `AXPress`); centre: clock or the active countdown; right: widgets, then mirrored third-party status items.
- Status item mirrors: status items have no window of their own on 27 (S4), so FocusDock captures MenuBarAgent's full-width bar window with SCK, crops it to each item's frame read from AX, and forwards clicks with `AXPress`; this passed with the bar visible (S9 control), and whether the bar window stays capturable while Apple's bar is auto-hidden is not yet run (open question 10).
- Apple's bar is hidden by the user setting by default; the SPI toggle is opt-in and recorded in the restore ledger.

### 5.5 Command bar, switcher, overview
- Command bar (`Leader Space`): menu tree in Omarchy's JSONC schema, app and file launcher, agent prompt; every entry calls the shared action registry, which the menu, hotkeys, CLI and agent all use.
- Cmd-Tab: system hotkeys 1 and 2 disabled via SPI (ledgered), own switcher of apps and windows across Spaces with live SCK thumbnails for windows on the current Space and FocusDock's own windows; other apps' windows on other Spaces capture as black (S12), so show the last frame captured while their Space was current, refreshed on every visit and marked stale; picking a window on another Space slides there, then raises it.
- Overview: grid of real Spaces with live SCK thumbnails for current-Space windows and the same stale last-seen frames elsewhere (S12), drag a window to another Space (bridged move); Apple's Mission Control stays one key away via `CoreDockSendNotification`.

### 5.6 Notifications
- Each mode names a Focus; FocusDock runs one Shortcut, `FocusDock Set Focus`, passing the Focus name (or `Off`) as input; this is the only remaining Shortcuts use.
- Do not rely on passing a Focus name straight into Set Focus: both branches of the first build failed (spike S11, remaining check in open question 9); the Shortcut is generated with one `If input is <name>` branch per Focus, each with the Focus chosen as a fixed value, and Turn Off guarded by "if a Focus is on"; today's one-Shortcut-per-Focus scheme stays as the fallback.
- Held items come from a read-only copy of the usernoted DB (Full Disk Access), watched via its WAL (spike S13: copy `db`, `db-wal` and `db-shm`, open read-only; the schema is unchanged and the WAL grows live; whether 27 still needs Full Disk Access is unconfirmed).
- Live banners are located by the `AXNotificationCenterBanner` subrole, `AXDescription` parses as "app, title, body", and action buttons are fired by the `Name:` prefix of the banner's custom actions (spike S5: performing one delivered the response to the posting app with no visible UI).
- FocusDock renders its own cards (SPEC.md 8) with history and per-mode decks; system banners are never restyled.

### 5.7 System controls
- Widgets and panels for volume and output, brightness, Night Shift and True Tone, Wi-Fi, Bluetooth, Focus, appearance, accent, wallpaper, battery, stay-awake and lock, each built on its row in 3.1.
- Focus control is the generated Shortcut of 5.6.
- Own OSD for the volume and brightness keys FocusDock handles; the system OSD remains for keys we do not own.
- Every SPI-backed widget hides when its symbol is missing; external-display brightness (DDC) is deferred until researched.

### 5.8 Input
- At login FocusDock sets `hidutil` Caps Lock to F18 (no permission; ledgered, so quitting restores Caps Lock).
- F18 is a leader: tapping it arms a layer of Carbon hotkeys for 1.5 s with an on-screen hint after 400 ms; Carbon hotkeys keep working under Secure Input (spike S8).
- Optional Hyper: an active event tap turns F18-held into Cmd+Ctrl+Opt+Shift for chords; it needs Accessibility and goes deaf under Secure Input, so the leader layer is always the documented path.
- Omarchy `Super+X` bindings map to `Leader X` (and `Hyper+X` with the tap on); a cheat sheet is generated from the bindings.

### 5.9 Lock and wallpaper
- Lock via `SACLockScreenImmediate`, falling back to the Ctrl-Cmd-Q keystroke; the lock screen is themed only by wallpaper and `LoginwindowText`.

## 6. Motion

- One motion engine resolves an element key to a spec; every FocusDock surface asks it, none hard-codes a duration.
- A spec is a spring (`response`, `damping`), a duration plus curve, or a `via` for system-driven moves (`dockSwipe`, `proxy`).
- `speed` multiplies every duration (0 = instant); `reduceMotion` (`system`, `always`, `never`) swaps movement for cross-fades, as the Dock does under Reduce Motion.
- Element keys: `dock.reveal`, `dock.magnify`, `dock.bounce`, `pill.expand`, `countdown.tick`, `workspace.switch`, `workspace.jump`, `window.move`, `window.resize`, `window.tile`, `border.follow`, `bar.reveal`, `bar.widget`, `menu.open`, `commandBar.open`, `switcher.open`, `overview.open`, `overview.close`, `card.enter`, `card.exit`, `osd.show`, `fleet.row`, `agent.panel`.
- Defaults copy the system where it has an analogue: Dock timings from rea-dock.md, and the Space slide, Mission Control and magnification springs fitted from 60 fps recordings on the 60 Hz built-in panel (spike S6).
- Fitted values (spring `response` in seconds, `damping` as the fraction): Space slide 0.52 and 0.91, one spring up to velocity 4, for FocusDock surfaces that follow the slide; Mission Control exit 0.28 and 0.99, with enter as a 0.27 s ease-out because it starts with high velocity; magnification in 0.12 and 0.75, rough because the travel is 10 points.
- `overview.close` is the 0.28 and 0.99 spring; `dock.bounce` is a timed 0.70 s `dockBounce` curve (the Dock's rise, hold and fall), which a `speed` or an override stretches; `dock.reveal` has a provisional cosine default until it is measured.
- Frames are paced by the display link at the panel's refresh rate (120 Hz on ProMotion); a debug overlay shows dropped frames per element key.

```jsonc
"motion": {
  "speed": 1.0, "reduceMotion": "system",
  "defaults": { "spring": { "response": 0.35, "damping": 0.86 },
                "spaceSlide": { "response": 0.52, "damping": 0.91 } },
  "elements": {
    "workspace.switch": { "via": "dockSwipe", "velocity": 1.0 },
    "workspace.jump":   { "via": "dockSwipe", "velocity": 9999 },
    "overview.open":    { "duration": 0.27, "curve": "easeOut" },
    "dock.magnify":     { "spring": { "response": 0.12, "damping": 0.75 } },
    "window.move":      { "via": "proxy", "duration": 0.22, "curve": "easeInOutCos" },
    "card.enter":       { "spring": { "response": 0.4, "damping": 0.75 } } } }
```

## 7. Customisation

- Files in `~/.config/focusdock/`: `modes.json` (exists), `shell.jsonc` (surfaces, motion, input, spaces), `menu.jsonc` (command bar tree, Omarchy schema), `fleet.jsonc` (hosts); each has a JSON Schema in `schemas/` used by the loader, the agent skill and editors.
- Every file is watched; a valid change applies live with the configured motion, an invalid one keeps the last good config and shows a card plus a bar badge with file, line, column and the schema message.
- Phase 5 ships the status-item badge (`exclamationmark.triangle.fill` in place of the mode symbol, never widening the item, which the notch would otherwise hide behind its overflow chevron), the problem list in the menu (`file:line:col path: message`) and `focusdock config check [file]`; the card and the bar badge reuse the same `ConfigProblem` list when those surfaces land.
- Files are parsed as JSON5, which accepts a little more than JSONC; the schemas use JSON Schema 2020-12 through swift-dynamicjson (Apache-2.0, pinned in `Package.resolved`).
- `modes.json` stays at schema version 1 until Phase 6 adds `space`; in `shell.jsonc` only `motion` is checked and every other section is an open object until its surface lands.
- Every surface exposes its layout (position, size, segments, order), widgets (which, where, per-widget options), hotkeys (all data, every binding rebindable) and motion keys.
- Colours are theme tokens (`accent`, `background`, `muted`, ANSI names), never hex in surface config; a per-surface `tokens` block may remap them; Omarchy themes keep working unchanged (THEMES.md).
- A `focusdock` skill documents the files, schemas and safe-edit rules for agents.

```jsonc
{
  "version": 2,
  "spaces": { "engine": "native", "count": 6, "tiler": { "default": "columns", "gaps": 8 } },
  "bar": { "height": 32, "left": ["mode", "spaces", "appMenu"], "center": ["clock"],
           "right": ["agentUsage", "fleet", "wifi", "volume", "battery", "statusItems"],
           "widgets": { "clock": { "format": "EEE d MMM HH:mm" } } },
  "dock": { "magnify": true },
  "switcher": { "enabled": true, "thumbnails": true },
  "input": { "leader": "capsLock", "hyperTap": false,
             "bind": { "Leader Space": "commandBar.open", "Leader 1": "space.go 1", "Leader A": "agent.toggle" } },
  "borders": { "width": 2, "active": "accent", "inactive": "muted" },
  "motion": { "speed": 1.0 }
}
```

## 8. Omarchy feature map (v1 map, updated)

| Omarchy | FocusDock v2 |
|---|---|
| Hyprland tiling, workspaces 1-10, animations | Real Spaces, DockSwipe slides, own tiler with proxy-animated moves (5.1, 5.2) |
| Window borders | Own borders from theme tokens (5.1) |
| Bar + widget panels | Own glass bar with app menus and status mirrors (5.4) |
| Omarchy menu, app grid | Command bar on the same JSONC schema (5.5) |
| Keybindings + `Super+K` cheat sheet | Leader layer, optional Hyper, generated cheat sheet (5.8) |
| Themes (`colors.toml` + templates) | Unchanged engine (THEMES.md) |
| Backgrounds per theme, video intros | Wallpaper target; video wallpaper as a desktop-level AVPlayer window later |
| Notifications, history | Focus + DB + AX, own cards (5.6) |
| OSD, audio, Bluetooth, Wi-Fi panels | Own OSD and panels (5.7) |
| Webapps, floating TUIs | Chrome `--app` shims, float rule in the tiler |
| Screenshot, recording, OCR, colour picker, clipboard, emoji | `screencapture`, SCK, Vision, `NSColorSampler`, pasteboard panel |
| Night light, stay awake, lock | Night Shift SPI, IOPM assertion, lock SPI (5.7, 5.9) |
| Agents panel, Quake console, Omarchy skill | Fleet view and agent console (9), `focusdock` skill (7) |
| Update + migrations | nix-darwin generations + numbered migrations in the state dir |

## 9. Fleet view and agent console

Design detail lives in [research/fleet-agent.md](research/fleet-agent.md); this section fixes the decisions.

### 9.1 Fleet view
- Hosts come from the user's ssh config via `ssh -G <alias>`; `fleet.jsonc` adds per-alias `os`, `class` (`own`, `shared`, `paid`), `confirm` (`none`, `per-start`, `per-job`), `gpuMaxGB`, `pollSec`; any alias missing from it is `paid` with `per-job`.
- Example roles: `cpu-box` (own, default for builds and tests, memory-capped jobs), `shared-gpu-a` (Windows), `shared-gpu-b` and `shared-gpu-c` (Linux, shared), `paid-gpu` (cloud, stopped when idle).
- Polling: `/usr/bin/ssh` with a ControlMaster per host, one sentinel-delimited exec per poll (Linux: `/proc`, `df`, `nvidia-smi`, own processes, tmux); Linux 5 s focused, 15-30 s visible, paused when hidden, at most 4 concurrent, hard kill at 6 s.
- Windows hosts (spike S14): the ssh logon is not elevated, so CIM, WMI, `wmic` and `typeperf` all fail with access denied after about 5 s per query; the poll never uses them, and a once-per-host CIM probe is an optional capability, never run inside the budgeted poll unless it succeeded.
- Windows recipe: one ssh exec composed in `cmd`: `nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader & echo @@sys & powershell -NoProfile -NonInteractive -EncodedCommand <base64>`; the PowerShell body uses only .NET (`Microsoft.VisualBasic.Devices.ComputerInfo` for memory, `[IO.DriveInfo]` for fixed disks, `GetSystemTimes` through `Add-Type` for CPU from two samples 100 ms apart) and sets `$ProgressPreference='SilentlyContinue'`.
- `nvidia-smi` runs from `cmd`, because launching it from PowerShell adds 2-3 s; the poll costs about 1.3 s warm and 2.9 s cold; lines end with CRLF; a non-numeric GPU line means "GPU unknown", not host down.
- Windows cadence: every 15 s or slower (15 s visible, 30 s otherwise), never the 5 s focused rate; the 6 s hard kill stays; own-process listing is budgeted separately and polled less often.
- ControlPath rule: the socket path must stay under the 104-byte unix socket limit (longer paths fail with "ControlPath too long" before connecting); use a short state-dir prefix with the hashed `%C` (40 characters).
- States `up`, `degraded`, `unreachable`, `off`, `auth`, `off network`, with backoff and a one-line ssh reason, never a modal; paid hosts are read through the cloud CLI's describe call and never started by the poller.
- UI: one monospace grid row per host (state dot, OS, RTT, CPU, MEM, DISK, GPU, own jobs, sample age), btop-style sparklines drawn with `Canvas`, k9s-style keys (`j/k`, `/`, `:`, `a` agent, `t` terminal, `?`), host detail, SwiftTerm drawer sharing the ControlPath.

### 9.2 Agent console
- Swift spawns `claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages --permission-prompt-tool stdio` directly, replacing v1's TypeScript Agent SDK sidecar; wire structs are `Codable` (unknown keys, event types and `system` subtypes tolerated) with golden-file tests on redacted recorded allow and deny streams.
- `--permission-prompt-tool stdio` is mandatory (spike S14): without it `-p` mode silently denies every tool that would prompt and never emits a request; with it each prompt arrives on stdout as a `control_request` with subtype `can_use_tool` (`tool_name`, `input`, `tool_use_id`, `permission_suggestions`, optional `blocked_path` and `description`; `title`, `decision_reason` and `suppressAlwaysAllowRule` are optional).
- The reply is a `control_response` on stdin with the same `request_id`: `{"behavior":"allow","updatedInput":<the full input object, edited for Edit first>}` or `{"behavior":"deny","message":...,"interrupt":false}`; `updatedPermissions` is optional and carries a chosen `permission_suggestions` entry for "Allow for session".
- `initialize` is optional for permissions: send the first user message straight away, and send `initialize` only when hooks, agents or the command list are needed; answer every `control_request`, unknown subtypes with an error `control_response`, or the turn stalls; keep stdin open for multi-turn and close it to end the process.
- Use the default Claude Code prompt plus `--append-system-prompt`, never `--system-prompt ""`.
- `--setting-sources` is always passed explicitly and never left to default: the default here is none (deterministic), and loading `user` settings is a `shell.jsonc` option, because the user's allow rules and hooks can then pre-empt `can_use_tool`; with none, FocusDock registers its own policy hook itself (hooks in `initialize`), to be confirmed in phase 12.
- Native UI: message stream, tool-call timeline, approval cards (Allow once, Allow for session, Deny with note, Edit first), diff cards, `AskUserQuestion` cards, plan card, todo list, checkpoints with undo, interrupt and queued messages, cost strip with `--max-budget-usd`, audit tab.
- Tools: `focusdock-mcp` exposes `mcp__focusdock__*`: the action registry (`mac_action`: modes, themes, windows, Spaces, held notifications, widgets), `mac_applescript` (allow-listed apps and verbs) and `fleet_status`, `fleet_exec`, `fleet_tmux`, `fleet_job_start`, `fleet_job_stop`; Peekaboo MCP adds screen and Accessibility control.
- Sessions: one UUID per (host, task), `--resume` after relaunch, `--fork-session` for alternatives; the panel is named "FocusDock Agent", never "Claude Code".
- The v1 router stays: on-device Foundation Models for intent parsing and `private` modes, Jev for typed decisions, Claude for multi-step work.
- The v1 agent features keep their order inside phases 12-13: act on the frontmost app, natural-language config edits, tidy windows into modes, theme from wallpaper, screen-aware ask, drop-down console, usage meters, crash diagnosis, calendar modes, voice, App Intents.

## 10. Security model

- FocusDock holds Accessibility, Screen Recording and Full Disk Access, so the agent's reach is bounded by our tools, not by TCC: it acts only through the action registry, `fleet_*`, allow-listed AppleScript, scoped Bash rules and Peekaboo.
- Sessions start in `default` permission mode with read-only tools allowed; every mutating call becomes an approval card through `can_use_tool`, and anything that moves, deletes or sends defaults to a dry run first.
- A `PreToolUse` hook (it runs even in bypass mode) enforces the hard rules: resolve the host against `fleet.jsonc`; paid and unknown hosts always prompt, the card names the exact job and the stopped-to-running transition, their `permission_suggestions` are not offered, `suppressAlwaysAllowRule` is set and any `updatedPermissions` is discarded, so no "always allow" can exist; on shared hosts only the user's own processes may be touched and reboot or service-restart verbs are refused; `fleet_job_start` itself wraps `cpu-box` jobs in `systemd-run --user` with the memory cap and a runtime bound.
- Raw `ssh`, `scp` and `rsync` Bash is disallowed as defence in depth; remote work exists only as `fleet_*` over the existing ControlMaster, so there is one auth path and every call lands in the append-only audit log.
- Text from hosts, notifications, web pages and windows that reaches the model is data, never instructions; approval cards show the literal command, not the model's summary.
- `private` modes never send screen, window, notification or fleet text off the machine; fleet samples are scrubbed of env values and token-looking strings.
- Local IPC: the MCP socket is 0600 in the state dir; the HTTP fallback binds loopback with a per-session bearer token; no other listener exists.
- Config from git-installed themes is colours and images only (THEMES.md); agent config edits are schema-checked before write, with one-step undo.
- Secrets (API keys) live in the Keychain, never in config; the agent uses the user's own installed `claude` login, which keeps FocusDock a personal tool unless open question 7 changes it.

## 11. Phases (replaces v1 section 7)

0-3. Shipped: spike, dock shell, modes, theme engine.
4. Done (2026-10-29), results in [research/spike-v2.md](research/spike-v2.md) (S1-S13) and [research/spike-v2-s14.md](research/spike-v2-s14.md) (S14); this spec is amended with them:
   - S1 PASS: the bridged move works on 27 for any window.
   - S2 PASS: the 27 DockSwipe format switches at every velocity, 9999 in one frame.
   - S3 PASS: the universal-owner gate holds and fails silently.
   - S4 blocked by a full status area: on 27 a status item has no window of its own.
   - S5 PASS: banner subrole, description and custom actions found and fired.
   - S6 PASS at 60 fps: slide, Mission Control and magnification springs fitted.
   - S7 measured: AX resize p95 12 ms, move p95 1.1 ms; the proxy needs the destination covered.
   - S8 PASS: Carbon hotkeys fire under Secure Input.
   - S9 visible-bar control PASS, auto-hide case not run.
   - S10 PARTIAL: active AppKit windows recolour live; background windows are inconclusive.
   - S11 FAIL as built: Focus name as Shortcut input does not work yet.
   - S12 FAIL for foreign off-Space windows: they capture black.
   - S13 PASS: the usernoted DB reads on 27.
   - S14 PASS with Windows redesign: `--permission-prompt-tool stdio` confirmed, CIM replaced by .NET plus `nvidia-smi`.
   - Gate: S1 passed, so no fallback was needed (open question 6 settled).
5. Done (2026-10-29): platform core.
   - Shipped: the capability registry (symbol table, catalog, SPI drift test) with a Capabilities submenu and `focusdock capabilities`; the permission monitor with System Settings deep links and a 2 s poll while a declared grant is missing.
   - Shipped: the restore ledger with read-back, replayed by the watchdog, at launch, on quit through `.terminateLater`, and by `focusdock restore`.
   - Shipped: the motion engine with the S6 defaults, driving the pill and the launch bounce, configured from `shell.jsonc` and reloaded live.
   - Shipped: schema-checked `modes.json` and `shell.jsonc` with positioned problems in the menu, a status-item badge and `focusdock config check`.
   - Shipped: the action catalog and registry; every menu item with an action runs through it.
   - Shipped: `FOCUSDOCK_SIGN_IDENTITY` signing, the `dev.focusdock.app` bundle id, and an 80% line-coverage gate on `FocusDockCore` in CI.
   - Moved later: the Focus status permission (with the Focus widget), the Automation probe (with the first integration that needs it), the `focusdock mode` and `focusdock space` verbs (Phase 6), the config error card and bar badge (with the bar).
6. Spaces: Space model, DockSwipe switching, bridged moves, routing rules, own borders; AeroSpace as fallback; remove AeroSpace and JankyBorders after a week's soak.
7. Window motion and tiler: SCK proxy moves, layouts, border follow.
8. Input and command bar: hidutil leader, Carbon layers, optional Hyper tap, JSONC menu, launcher, cheat sheet; Cmd-Tab switcher and overview.
9. Bar: glass bar, app menus, status mirrors, notch, widgets.
10. Notifications and system controls: one-Shortcut Focus, DB and AX reader, cards, control panels, OSD, lock.
11. Fleet view: FleetStore and poller, Windows script, states, overlay, SwiftTerm drawer.
12. Agent console: stream-json client, cards, sessions, `focusdock-mcp`, `fleet_*`, policy hook, audit, paid-host flow.
13. Activity classification (SPEC.md 7), utilities, remaining agent features, home-manager module, migrations, polish.

Phases 11-12 do not depend on the spike and may run in parallel with 5-10.
Each phase ends with a recording of the real flow and a side-by-side check against the native surface it replaces.

## 12. Risks

- SPI drift on point releases: symbols are checked at launch, and a CI test on a macOS runner fails when a symbol we use disappears.
- DockSwipe is an undocumented event format; if it changes, switching degrades to Ctrl+Number keystrokes with Apple's fixed timing.
- The bridged move is private and may change in a point release; the read-back detects it, and AeroSpace stays the fallback.
- Foreign SPI calls report success while doing nothing (S3); only a read-back detects a refused call.
- Other apps' windows on other Spaces cannot be captured live (S12); the overview and switcher show stale frames there.
- Proxy animation shows a double image unless the destination is covered, and about 3 frames of mismatch after landing on a heavy app (S7); heavy apps may need the proxy held longer.
- Apple's auto-hidden bar can reveal over ours on hover at the top edge; our bar sits one level above it.
- TCC grants reset when the signature changes; a wrong build identity silently disables Spaces, borders and the bar.
- Secure Input silences event taps; the leader layer covers it, Hyper chords do not.
- The usernoted DB format is undocumented and may change.
- stream-json is versioned by the CLI; pin a minimum `claude` version and fail soft on unknown events.
- Without `--permission-prompt-tool stdio` the CLI silently denies tools that need a prompt (S14); a launch self-test sends one prompting tool call and fails loudly if no `can_use_tool` request arrives.
- An unanswered `control_request` stalls the turn; unknown subtypes get an error response.
- Windows hosts may refuse CIM and WMI to an unelevated ssh logon (S14); each Windows capability is probed, never assumed, and Windows polls stay at 15 s or slower.
- Prompt injection through fleet output, notifications or window text; mitigated by the policy hook, literal-command approval cards and the audit log, never by prompt wording alone.
- ControlMaster sockets left behind after a crash; swept at launch; a ControlPath over 104 bytes fails before connecting (S14).

## 13. Decisions

Kept from v1:
1. Terminal: WezTerm, themed through the state-dir include.
2. Bar: native glass bar inside FocusDock; no SketchyBar.
3. Themes: Omarchy format and themes, imported as-is; Nix owns only fixed include lines, runtime state lives in `~/.local/state/focusdock/`.

Changed in v2:
4. Windows: real Spaces with native slides replace AeroSpace workspaces (AeroSpace only as a fallback until the native engine has soaked; spikes S1 and S2 passed).
5. Borders: drawn by FocusDock; JankyBorders and its theme target are dropped.
6. Super key (changed, needs the user's confirmation): v1 chose Caps Lock as Hyper via Karabiner-Elements; v2 uses `hidutil` Caps Lock to F18 as a leader with Carbon hotkeys, plus an optional event-tap Hyper, and drops Karabiner.
7. Agent host: `claude` stream-json spawned from Swift replaces the TypeScript Agent SDK sidecar.
8. FocusDock MCP: a stdio shim plus a 0600 unix socket, because the CLI has no socket transport.
9. Cmd-Tab and overview are FocusDock's own; SPEC.md 4.4's "the system Dock still owns Cmd-Tab" no longer holds.
10. Focus: one generated Shortcut with an `If input is <name>` branch per Focus, replacing one Shortcut per Focus (that scheme stays as the fallback; a bare Focus-name input failed in spike S11).
11. Nix: drop `services.aerospace` (after the soak), `services.jankyborders` and Karabiner; input needs nothing installed.

## 14. Open questions for the user

Answered 2026-10-28:
1. Yes: Caps Lock as an F18 leader with optional Hyper chords; Karabiner is dropped.
2. Four Desktops: one per mode (Writing, Building, Social) plus one free.
3. FocusDock's own tiler on by default, with a per-mode floating override.
4. Hide Apple's menu bar through the user setting, not SPI.
5. Replace Cmd-Tab by default with the mode-aware switcher.
6. Settled by the spike: S1 passed, so windows are routed natively with the bridged move and no fallback is needed.
7. The user's own `claude` login; FocusDock stays a personal tool.
8. Shared hosts prompt on every mutating call; "Allow for session" applies to read-only calls only.

New after the Phase 4 spike (2026-10-29):
9. S11: may the spike import a second, minimal Shortcut (Set Focus bound to Shortcut Input, no `Off` branch) plus one built in the Shortcuts editor for comparison, which costs one confirmation click per import, or is the generated one-branch-per-Focus Shortcut accepted as the plan?
10. S4 and S9: may the follow-up run happen with some status items hidden or quit and Apple's bar set to auto-hide, to settle the Cmd-drag and the auto-hidden mirror, or is the mirror dropped from the first cut of the bar?
11. S12: are stale last-seen thumbnails for other apps' windows on other Spaces acceptable in the overview and switcher, or should the overview briefly visit each Space to refresh them?

The original questions, kept for reference:

1. Confirm decision 6: Caps Lock as an F18 leader (tap, then key) with optional Hyper chords, instead of Karabiner's Hyper.
2. How many Desktops to create, and is it one Space per mode or several Spaces per mode?
3. Tiling: FocusDock's own tiler on by default (Hyprland-like), or floating with snap layouts only?
4. Hide Apple's menu bar via the user setting (default) or let FocusDock toggle it via SPI?
5. Replace Cmd-Tab by default, or put the switcher on a leader key and leave Cmd-Tab alone?
6. If spike S1 fails: keep AeroSpace for routing only, try the unresearched drag-and-switch trick, or route windows by hand?
7. Agent auth: the user's own `claude` login (personal tool) or an API key (distributable build)?
8. Should `shared` hosts allow "Allow for session", or prompt on every mutating call as paid hosts do?
