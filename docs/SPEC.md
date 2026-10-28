# FocusDock - spec (draft v0, 2026-10-28)

A native macOS dock that replaces the system Dock, organised around focus modes (Writing, Building, Social, ...).
Cloned in spirit from Thariq's demo (x.com/trq212/status/2115135857669881939); his source is not public, so this is a ground-up build.
Evidence: [research/rea-dock.md](research/rea-dock.md) (REA teardown of Dock.app on this Mac, macOS 27) and [research/survey.md](research/survey.md) (reuse survey).

## 1. What the demo does (observed frame by frame)

- Floating glass dock at bottom centre; native Dock is gone.
- Left group: mode pills; the active one expands to icon + name in its colour (Writing orange, Building blue, Social red), inactive ones collapse to a glass circle with an icon.
- Divider, then the active mode's app set; pinned web apps (GitHub, Apple Developer, Drive) carry a small globe badge; running dot under each running app.
- Switching mode swaps the visible windows (empty desktop mid-switch, then the mode's windows return).
- Menu bar extra shows the current mode (hammer + "Building").
- Leaving a focus mode for a distracting one starts a countdown inside the pill ("Social 0:10") with a white "Stay" button; each extra press on the target pill shortens the wait.
- Notifications from distracting apps are held; a card pops above the dock: sender, channel, "held for Social", an AI tag ("Time-sensitive - needs your answer before 3pm"), and "Later" / "Go to Social (30s wait)".
- His source tree: AeroSpace.swift, Chrome.swift, Config.swift, DockView.swift, Model.swift, Peek.swift, TabPrompt.swift, Workspace.swift, scripts/build-app.sh.
- "jev" = TypeSafe AI's Jev typed-decision model (Choice / Score / P(yes) over a JSON state).

## 2. Goals and non-goals

Goals:
- Indistinguishable from the native Dock in look and feel (material, sizes, indicator, hover label, motion, Space behaviour).
- Modes are data: an agent (Claude Code) can add or edit modes by editing one config file, hot-reloaded.
- Deterministic friction: timers and blocking are plain code; the model only classifies.
- Fail safe: if FocusDock crashes, the native Dock comes back.

Non-goals for v1:
- Minimised-window tiles, Trash, stacks/folders, drag-to-reorder, multi-monitor, vertical orientation.
- Window previews on hover (his Peek.swift); add after v1.
- App Store distribution (we use one private SPI, see 4.4).

## 3. Architecture

Swift 6, AppKit shell + SwiftUI views, macOS 26+ (needs the public Liquid Glass APIs), SwiftPM package + `scripts/build-app.sh` that assembles a signed `.app` (`LSUIElement = YES`).

| File | Responsibility |
|---|---|
| `DockPanel.swift` | The NSPanel: level, collection behaviour, positioning, screen changes |
| `DockView.swift` | SwiftUI: mode pills, app tiles, running dots, badges, hover cartouche, countdown |
| `Model.swift` | `@Observable` state + the mode-switch state machine (pure, unit-tested) |
| `Config.swift` | Load/validate `~/.config/focusdock/modes.json`, file-watch hot reload |
| `Workspace.swift` | Running apps, launch/activate, badges (NSWorkspace + AX) |
| `AeroSpace.swift` | One client for the `aerospace` CLI and its `subscribe` event stream |
| `Chrome.swift` | AppleScript bridge: list tabs, active URL, focus/open tab |
| `Activity.swift` | Samples app + window title + URL, asks the classifier, emits drift events |
| `Notifications.swift` | Reads held notifications, classifies them, feeds the popover |
| `Jev.swift` | URLSession client for `POST /v1/systemone` (base URL swappable to a local Ollaya server) |
| `NativeDock.swift` | Hide/restore the system Dock, plus crash-restore watchdog |
| `MenuBar.swift` | Status item with current mode and a mode menu |

Data flow: `Config -> Model <- (AeroSpace events, NSWorkspace events, Activity, Notifications) -> DockView`.
`Model` is the only writer of state; every side effect (switch workspace, launch app, toggle Focus) goes through it.

## 4. Native fidelity (from the REA teardown)

### 4.1 Window
- `NSPanel(styleMask: [.borderless, .nonactivatingPanel])`, `level = CGWindowLevelForKey(.dockWindow)` (20, the same key the Dock uses for 21 of its 27 window-level lookups).
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]`; no `.fullScreenAuxiliary`, so like the Dock it is not shown in fullscreen Spaces.
- `canBecomeKey/Main = false`, `hidesOnDeactivate = false`, clear background, no window shadow (the glass draws its own); app runs as `.accessory`.
- Known gap: the real Dock is the Spaces/Mission Control server and sits outside Space management; we can match its level, not its Space semantics.

### 4.2 Visuals
- Platter: public Liquid Glass (`GlassEffectContainer` + `.glassEffect` per group) so the pill group and app group merge like the Dock's SDF-union shape. The Dock itself uses the private `GlassMaterialProvider.Configuration.dock`; we do not.
- Tile size: read the user's `com.apple.dock` `tilesize`/`largesize` (here 75 / 85, magnification on); defaults 64 pt (52 pt on displays <= 800 pt tall) and 128 pt.
- Running dot: 4x4 pt, radius 2; 3x3 pt, radius 1.5 below 33 pt tiles (read from `DOCKIndicatorLayer`).
- Hover label: capsule glass "cartouche" above the tile, not a tooltip.
- Respect Reduce Transparency (flat fallback) and Reduce Motion (cross-fade instead of bounce/magnify).
- Still unknown, measured in Phase 0: platter corner radius/insets, shadow, indicator colour, magnification falloff, launch-bounce curve.

### 4.3 Behaviour
- Click: launch or activate; click on a running app with no windows reopens it.
- Launch bounce until `isFinishedLaunching`; magnification on hover if the user has it on.
- Right-click menu mirrors `DockMenus.plist`: Options (Keep in Mode, Remove from Mode, Open at Login, Show in Finder) / Show All Windows / Hide / Quit (Option: Force Quit).
- Drag a tile out to remove it from the mode, with the system "poof" sound.
- Badges: read `AXStatusLabel` from the system Dock's `AXApplicationDockItem`s (works while it is autohidden; needs Accessibility).

### 4.4 Hiding the native Dock
- On launch save `CoreDockGetAutoHideEnabled()`, call `CoreDockSetAutoHideEnabled(true)`; the Dock applies it live, no restart. Restore on quit.
- Watchdog: a tiny LaunchAgent helper that restores the saved state if the main process dies (Docky's idea, our code).
- Never touch `static-only` or system files; the system Dock still owns Cmd-Tab, Mission Control and hot corners.

## 5. Modes and config

`~/.config/focusdock/modes.json`, validated on load; an invalid file is rejected with an error in the menu bar and the last good config stays live.

```json
{
  "version": 1,
  "modes": [
    {
      "id": "writing", "name": "Writing", "symbol": "pencil", "color": "#D9822B",
      "workspace": "W",
      "apps": ["com.google.Chrome", "notion.id", "com.apple.Notes", "com.anthropic.claudefordesktop"],
      "webApps": [{ "name": "Drive", "url": "https://drive.google.com" }],
      "focus": "Writing",
      "exit": { "delaySeconds": 10, "perPressSeconds": 3, "to": { "social": 30 } },
      "allow": "Long-form writing, docs, notes, research reading"
    }
  ]
}
```

- `workspace`: AeroSpace workspace for the mode's windows; app routing via AeroSpace `on-window-detected` rules generated from `apps`.
- `webApps`: Chrome "Install as app" shims (own bundle id, works with NSWorkspace and AeroSpace); globe badge is our overlay.
- `focus`: macOS Focus to turn on via `shortcuts run` (allow-lists set once by hand in System Settings).
- `exit`: the friction policy when leaving this mode; `to` overrides per target.
- `allow`: plain-language description handed to the classifier.
- Agent editing: Claude Code edits this file; FocusDock hot-reloads it. No extra API in v1.

## 6. Mode-switch state machine (Model.swift)

States: `active(mode)` and `pending(from, to, deadline)`.
- `request(to)`: if pending to the same mode, cancel; else `deadline = now + from.exit.delay(to)`; if it is <= now, activate at once, else enter `pending`.
- `press(to)` while pending: `deadline -= from.exit.perPress`, floored at now.
- `stay()`: cancel pending.
- Tick at deadline: activate `to` (AeroSpace workspace, Focus mode, dock app set, menu bar).
- Pure functions over an injected clock; unit tests cover cancel, shorten, per-target override, zero delay and config reload during pending.

## 7. Activity classification

- Sample on app activation and every 5 s while active: bundle id, AX focused-window title, Chrome URL (AppleScript).
- Cache by hash of (app, title, host); call Jev only on a cache miss.
- Jev Choice over mode ids + "neutral", with each mode's `allow` text in the state.
- On sustained drift (e.g. 3 samples into another mode) show a nudge card above the dock: "Looks like Social - switch (30s) or Stay"; never auto-switch.

## 8. Notifications

- Suppression: the mode's Focus hides banners from non-allowed apps (the only no-SIP way to hold another app's notifications).
- Reading: the usernoted DB (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`, needs Full Disk Access), read-only copy, watched via its WAL; behind a `NotificationSource` protocol so a Slack API source can replace it.
- Classify each held item with Jev: urgency Score + "needs reply by" extraction; time-sensitive items get the popover card with "Later" / "Go to <mode> (Ns wait)", others queue silently until you enter their mode.

## 9. Permissions and privacy

- Accessibility (window titles, Dock badges), Automation for Chrome, Full Disk Access (notifications DB, Phase 4 only).
- What leaves the machine: app name, window title, URL host, notification sender + text, sent to Jev. The local Ollaya server is the offline option; a per-mode `private: true` flag skips classification entirely.
- API key from the macOS Keychain, never in the config file.

## 10. Phases

0. Spike (1 day): measure platter radius, shadow, indicator colour, magnification and bounce from a 120 fps recording; confirm usernoted DB + FDA, Chrome AppleScript and `CoreDockSetAutoHideEnabled` on macOS 27. Output: numbers back into section 4.
1. Dock shell: panel, glass platter, static app set, running dots, launch/activate, hover label, native Dock hide/restore + watchdog.
2. Modes: config + hot reload, mode pills, state machine + countdown UI, AeroSpace workspaces, menu bar, Focus toggling.
3. Activity: sampler + Jev + drift nudge.
4. Notifications: usernoted reader, classification, popover.
5. Polish: right-click menu, drag-out poof, magnification, Reduce Motion/Transparency, Peek.

Each phase ends with a screen recording of the real flow compared side by side with the native Dock.

## 11. Open decisions

1. Classifier: Jev (needs an early-access key, cheapest, matches the demo) or Claude Haiku via the Anthropic API (you already have access, slower and pricier per call).
2. Window management: adopt AeroSpace (a tiling WM changes how your whole desktop behaves) or a lighter AX hide/show of each mode's apps without tiling.
3. Notification source: usernoted DB + Full Disk Access (all apps, unsupported store) or the Slack API only (robust, Slack only).
4. Home: `~/Code/projects/focus-dock` (its own repo).
