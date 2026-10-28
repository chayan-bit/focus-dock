# FocusDock

A native macOS dock replacement organised around focus modes.
Design and evidence: [docs/SPEC.md](docs/SPEC.md), [docs/research/rea-dock.md](docs/research/rea-dock.md).

## Status: Phase 1 (dock shell)

- A Liquid Glass platter at the bottom centre of the main screen, at the Dock's own window level, on every Space, never taking key focus.
- Tiles are the native Dock's app list: Finder, your `persistent-apps`, then other running apps after a divider.
- Running dot, glass hover label, launch bounce until the app finishes launching.
- Click launches or activates an app (a running app with no windows reopens one).
- The system Dock is auto-hidden while FocusDock runs and restored on quit, on SIGTERM/SIGINT/SIGHUP, and by a watchdog process if FocusDock crashes.
- Respects Reduce Transparency (opaque platter) and Reduce Motion (fade pulse instead of a bounce).

Not yet: modes, config file, menu bar item, badges, magnification, right-click app menus (later phases, see SPEC section 10).

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

To quit, right-click an empty part of the platter (not an icon) and choose **Quit FocusDock**.
Quitting normally, `kill <pid>`, or Ctrl-C in a terminal all bring the system Dock back.

For testing, extra tiles can be added for one run without touching any preference:
`open build/FocusDock.app --args -FocusDockExtraApps '("/System/Applications/Calculator.app")'`.
The latest end-to-end results are in [docs/research/e2e-phase1.md](docs/research/e2e-phase1.md).

## How the system Dock is hidden

FocusDock calls the `CoreDockSetAutoHideEnabled` SPI, resolved at runtime with `dlsym`; the Dock applies it live, no restart.
It also sets `com.apple.dock autohide-delay` to 1000 s so the hidden Dock does not slide up when the cursor touches the bottom edge.
Before hiding it writes your original autohide setting and `autohide-delay` (value or absent) to `~/Library/Application Support/FocusDock/native-dock.json`.
That file exists only while FocusDock has the Dock hidden: a normal quit restores both settings and deletes it.
The running Dock reads `autohide-delay` only when it starts, so the delay takes effect after the next Dock restart (`killall Dock`, logout or reboot) that happens while FocusDock is running; FocusDock never restarts the Dock itself.
If FocusDock crashes, its watchdog (the same binary started with `--watchdog <pid>`) restores from the file; the next launch also keeps the recorded original instead of recording "hidden".
If the system Dock ever stays hidden, run `defaults write com.apple.dock autohide -bool false && killall Dock`.

## Permissions

Phase 1 needs none.
Accessibility (badges, window titles) and Automation for Chrome arrive in later phases.

## Layout

- `Sources/FocusDockCore`: pure, unit-tested logic: `DockMetrics` (every visual constant), `PlatterLayout` (geometry shared by drawing and hit-testing), `TileList` (persistent-apps parsing and merge), `NativeDockKeeper` (hide/restore decisions).
- `Sources/FocusDock`: the AppKit/SwiftUI app: `DockPanel`, `DockHostingView` (mouse input), `DockView`/`TileView`, `Model`, `Workspace`, `NativeDock`.
