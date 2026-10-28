# FocusDock

A native macOS dock replacement organised around focus modes.
Design and evidence: [docs/SPEC.md](docs/SPEC.md), [docs/research/rea-dock.md](docs/research/rea-dock.md).

## Status: Phase 2 (modes)

- A Liquid Glass platter at the bottom centre of the main screen, at the Dock's own window level, on every Space, never taking key focus.
- Left: one pill per mode. The active mode is a capsule in its colour with its symbol and name; the others are small circles with just the symbol (hover for the name).
- Right of a divider: the active mode's apps, then its web apps (Chrome icon with a globe badge; a click runs `Google Chrome --app=<url>` in a new window).
- Running dot, glass hover label, launch bounce until the app finishes launching.
- Leaving a mode with an exit delay turns the target pill into a countdown ("Social 0:30") next to a white **Stay** button; each extra click on the countdown pill shortens the wait, Stay or a click on the current mode cancels it.
- When the countdown ends the mode switches: dock tiles, AeroSpace workspace, Focus shortcut, menu bar item.
- Menu bar item: the mode's symbol and name (or the countdown), a mode menu with the same friction, Edit modes.json, Reveal config folder, warnings, Quit.
- The system Dock is auto-hidden while FocusDock runs and restored on quit, on SIGTERM/SIGINT/SIGHUP, and by a watchdog process if FocusDock crashes.
- Respects Reduce Transparency (opaque platter) and Reduce Motion (fade pulse instead of a bounce, no rolling countdown digits).

Not yet: badges, magnification, right-click app menus, activity classification, notifications (later phases, see SHELL-SPEC section 7).

## Modes: `~/.config/focusdock/modes.json`

On first launch FocusDock writes a default with three modes, filled with whichever of these apps are installed:

| Mode | Workspace | Apps | Leaving it |
|---|---|---|---|
| Writing | W | Obsidian, Notion, Notes, Claude, Chrome, web app Drive | 10 s, 3 s less per extra press, 30 s to Social |
| Building | B | WezTerm, Zed, Cursor, Chrome, Claude, web app GitHub | same |
| Social | S | Slack, WhatsApp, Discord | free |

Edit the file in any editor (or let Claude Code edit it); FocusDock reloads it on save.
An invalid file is rejected: the menu lists every problem with its JSON path (for example `modes[1].exit.to.socal: no mode has id "socal"`) and the last good config stays live.
Deleting the file brings the default back.

```json
{
  "version": 1,
  "initialMode": "writing",
  "modes": [
    {
      "id": "writing", "name": "Writing", "symbol": "pencil", "color": "#F0892B", "workspace": "W",
      "apps": ["md.obsidian", "com.apple.Notes"],
      "webApps": [{ "name": "Drive", "url": "https://drive.google.com" }],
      "focus": "Writing",
      "exit": { "delaySeconds": 10, "perPressSeconds": 3, "to": { "social": 30 } },
      "allow": "Long-form writing, docs, notes, research reading",
      "private": false
    }
  ]
}
```

- Required per mode: `id` (unique), `name`, `symbol` (an SF Symbol name), `color` (`#RRGGBB`), `workspace` (an AeroSpace workspace name).
- Optional: `apps` (bundle ids, in dock order; find one with `osascript -e 'id of app "Zed"'`), `webApps`, `focus`, `exit` (absent means leaving is free; `to` overrides the delay per target mode id), `allow` and `private` (used from Phase 3).
- `initialMode` is used when the last active mode no longer exists; FocusDock otherwise remembers the active mode across launches.

## AeroSpace

FocusDock drives [AeroSpace](https://github.com/nikitabobko/AeroSpace) through its CLI; it never writes the AeroSpace config (Nix owns it).

- Activating a mode runs `aerospace workspace <workspace>`.
- New windows are routed at runtime from `aerospace subscribe window-detected focus-changed`: an app listed in exactly one mode moves to that mode's workspace, an app in several modes goes to the current mode's workspace, any other app stays where AeroSpace put it. Web apps count as Chrome.
- Jumping to a window on another mode's workspace (Cmd-Tab, an AeroSpace binding, clicking a notification) counts as asking for that mode: its countdown starts and FocusDock puts you back on the current mode's workspace. Jumping again while it counts down neither resets nor shortens it; jumping to a third mode's window retargets the countdown with that mode's delay. When it completes you land on the window you jumped to; Stay cancels. A jump into a mode you can leave for free just switches, and workspaces that belong to no mode are left alone.
- `aerospace` is looked up on `PATH`, then `/run/current-system/sw/bin`, `/etc/profiles/per-user/$USER/bin`, `/opt/homebrew/bin` and `/usr/local/bin`.
- Without AeroSpace (not installed or not running) the dock and modes still work, and the menu shows "AeroSpace unavailable"; the subscription retries with backoff up to 30 s.

## Focus modes

A mode with `"focus": "Writing"` turns on the macOS Focus "Writing" when it activates; a mode without `focus` turns Focus off.
macOS has no public API for this, so FocusDock runs Shortcuts you create once:

1. System Settings > Focus > **+** > Custom: create a Focus named after each `focus` value (for example "Writing", "Building") and choose its allowed people and apps.
2. In the Shortcuts app, create a shortcut named **FocusDock Writing**: add the action **Set Focus**, set it to "Turn **Writing** On" (optionally "Until Turned Off").
3. Repeat for every `focus` value ("FocusDock Building", ...).
4. Create **FocusDock Off** with one **Set Focus** action per Focus above, each set to "Turn **<Focus>** Off".
5. Relaunch FocusDock or save a change to `modes.json`; FocusDock re-reads the shortcut list on every config load.

Missing shortcuts are listed in the menu (for example `Shortcut "FocusDock Writing" not found`); nothing else is affected.
FocusDock only ever runs shortcuts whose names start with "FocusDock ".

## Build

Requires Xcode with the macOS 27 SDK (Swift 6.4); runs on macOS 26 or later.

```sh
swift test                 # unit tests (FocusDockCore)
scripts/build-app.sh       # prints the path of build/FocusDock.app (ad-hoc signed)
```

## Run

```sh
open build/FocusDock.app
```

To quit, choose **Quit FocusDock** from the menu bar item, or right-click an empty part of the platter.
Quitting normally, `kill <pid>`, or Ctrl-C in a terminal all bring the system Dock back.
The latest end-to-end results are in [docs/research/e2e-phase2.md](docs/research/e2e-phase2.md).

## How the system Dock is hidden

FocusDock calls the `CoreDockSetAutoHideEnabled` SPI, resolved at runtime with `dlsym`; the Dock applies it live, no restart.
It also sets `com.apple.dock autohide-delay` to 1000 s so the hidden Dock does not slide up when the cursor touches the bottom edge.
Before hiding it writes your original autohide setting and `autohide-delay` (value or absent) to `~/Library/Application Support/FocusDock/native-dock.json`.
That file exists only while FocusDock has the Dock hidden: a normal quit restores both settings and deletes it.
The running Dock reads `autohide-delay` only when it starts, so at launch FocusDock restarts the Dock once (SIGTERM, same as `killall Dock`) unless the running Dock already has the delay.
It knows that from `~/Library/Application Support/FocusDock/primed-dock.json`, which records the PID and start time of the last Dock started with the delay in place, or from a Dock that started after FocusDock wrote the delay.
That record survives quits, so relaunching FocusDock in the same login session does not restart the Dock again.
FocusDock enables autohide only once the primed Dock is running; if no Dock comes back within 5 s, it restores the settings and leaves the Dock visible.
If FocusDock crashes, its watchdog (the same binary started with `--watchdog <pid>`) restores from the file; the next launch also keeps the recorded original instead of recording "hidden".
If the system Dock ever stays hidden, run `defaults write com.apple.dock autohide -bool false && killall Dock`.

## Permissions

Phase 2 needs none; Shortcuts may ask once whether FocusDock can run shortcuts.
Accessibility (badges, window titles) and Automation for Chrome arrive in later phases.

## Layout

- `Sources/FocusDockCore`: pure, unit-tested logic: `Config` (modes.json schema and validation), `DefaultModes`, `ModeMachine` (the mode-switch state machine, SPEC 6), `WindowRouting` (window routing, executable lookup, Focus shortcut names), `FocusFollow` (subscription events, jump-to-other-mode decision, echo token), `DockMetrics` (every visual constant), `PlatterLayout` (geometry shared by drawing and hit-testing), `TileList` (a mode's tiles), `NativeDockKeeper` (hide/restore decisions), `DockPriming` (whether the running Dock must restart).
- `Sources/FocusDock`: the AppKit/SwiftUI app: `ModeController` (runs the machine's side effects), `ConfigStore` (load, default, hot reload), `AeroSpace`, `Focus`, `MenuBar`, `DockPanel`, `DockHostingView` (mouse input), `DockView`/`PillView`/`TileView`, `Model`, `Workspace`, `NativeDock`, `DockPrimer`, `ProcessRunner`.
