# FocusDock

A native macOS dock replacement organised around focus modes.
Design and evidence: [docs/SPEC.md](docs/SPEC.md), [docs/research/rea-dock.md](docs/research/rea-dock.md).

## Status: Phase 3 (themes)

- A Liquid Glass platter at the bottom centre of the main screen, at the Dock's own window level, on every Space, never taking key focus.
- Left: one pill per mode. The active mode is a capsule in its colour with its symbol and name; the others are small circles with just the symbol (hover for the name).
- Right of a divider: the active mode's apps, then its web apps (Chrome icon with a globe badge; a click runs `Google Chrome --app=<url>` in a new window).
- Running dot, glass hover label, launch bounce until the app finishes launching.
- Leaving a mode with an exit delay turns the target pill into a countdown ("Social 0:30") next to a white **Stay** button; each extra click on the countdown pill shortens the wait, Stay or a click on the current mode cancels it.
- When the countdown ends the mode switches: dock tiles, AeroSpace workspace, Focus shortcut, menu bar item.
- Menu bar item: the mode's symbol and name (or the countdown), a mode menu with the same friction, Theme, Capabilities, Edit modes.json, Reveal config folder, config problems and warnings, Quit; a warning triangle joins the symbol while `modes.json` or `shell.jsonc` has problems.
- The system Dock is auto-hidden while FocusDock runs and restored on quit, on SIGTERM/SIGINT/SIGHUP, and by a watchdog process if FocusDock crashes.
- Respects Reduce Transparency (opaque platter) and Reduce Motion (fade pulse instead of a bounce, no rolling countdown digits).

- Themes: Omarchy's 23 themes and its `colors.toml` + template format; `focusdock theme set <name>` (or the menu's **Theme** submenu) retints the dock, WezTerm, Neovim, Zed, btop, JankyBorders, the wallpaper and Claude Code, and `focusdock theme reset` puts every original back (see below).

Not yet: badges, magnification, right-click app menus, activity classification, notifications (later phases, see SHELL-SPEC section 7).

## Modes: `~/.config/focusdock/modes.json`

On first launch FocusDock writes a default with three modes, filled with whichever of these apps are installed:

| Mode | Workspace | Apps | Leaving it |
|---|---|---|---|
| Writing | W | Obsidian, Notion, Notes, Claude, Chrome, web app Drive | 10 s, 3 s less per extra press, 30 s to Social |
| Building | B | WezTerm, Zed, Cursor, Chrome, Claude, web app GitHub | same |
| Social | S | Slack, WhatsApp, Discord | free |

Edit the file in any editor (or let Claude Code edit it); FocusDock reloads it on save.
Comments (`//`, `/* */`) and trailing commas are allowed.
The file is checked against [schemas/modes.schema.json](schemas/modes.schema.json), which editors can use too, then for references between modes.
An invalid file is rejected: the menu lists every problem with its line, column and JSON path (for example `modes.json:7:16 modes[1].color: must be a #RRGGBB colour`) and the last good config stays live.
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

## Themes

```sh
scripts/install-cli.sh                       # puts `focusdock` in ~/.local/bin when that is on PATH
scripts/sync-backgrounds.sh [theme ...]      # optional: the themes' wallpapers (about 69 MB, checksummed)
focusdock theme list                         # 23 themes, "*" on the current one
focusdock theme set "Tokyo Night"
focusdock theme next                         # or prev
focusdock theme reset
```

- The themes and templates are Omarchy's (MIT, pinned commit in [THIRD_PARTY.md](THIRD_PARTY.md)); the format is unchanged, so an Omarchy theme directory works as is.
- Your own themes go in `~/.config/focusdock/themes/<name>/` (same name overrides a shipped theme file by file), your own templates in `~/.config/focusdock/themed/*.tpl`.
- A theme cloned from git may only bring colours and images: Lua, terminal configs and `vscode.json` from it are ignored and named on stderr.
- Every switch renders into `~/.local/state/focusdock/current/next-theme`, swaps it into `current/theme` in one step under a lock, then retints in parallel; a slow retint from an older switch never lands after a newer one.
- Re-applying the current theme moves to its next background; each theme remembers its last background.
- Zed, btop and Claude Code get only their `theme` / `color_theme` key changed; the first switch saves your values and reset restores them byte for byte.
- The exact files and include points are in [docs/THEMES.md](docs/THEMES.md).

## Commands

```sh
focusdock config check [file]                # modes.json and shell.jsonc, or one file; file:line:col problems, exit 1 if any
focusdock restore                            # replays the restore ledger by hand, as the watchdog does after a crash
focusdock capabilities                       # each private-API capability: available, missing symbols, or needed permission
```

- `config check` never touches the running dock; a file that does not exist counts as clean, since defaults apply.
- `restore` prints each key it put back and exits 1 if one did not read back; that key stays in the ledger.
- `capabilities` judges permissions as this process sees them, so from a terminal it shows the terminal's grants; the menu bar's **Capabilities** submenu shows the app's own.

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
scripts/coverage.sh        # the same tests with coverage; fails below 80% lines on FocusDockCore, as CI does
scripts/build-app.sh       # prints the path of build/FocusDock.app
```

The app is signed ad hoc unless `FOCUSDOCK_SIGN_IDENTITY` names a code-signing identity.
macOS ties Accessibility and Screen Recording grants to the signature, and an ad hoc signature changes with every build, so each rebuild loses the grants.
A local self-signed identity keeps them across rebuilds; create it once:

1. Open Keychain Access and choose **Keychain Access > Certificate Assistant > Create a Certificate...**.
2. Enter a name of your choice, set **Identity Type** to **Self Signed Root** and **Certificate Type** to **Code Signing**, then choose **Create**.
3. Check that it is listed: `security find-identity -v -p codesigning`.
4. Export the name in your shell profile: `export FOCUSDOCK_SIGN_IDENTITY="<the name you chose>"`.

The identity stays in your login keychain; nothing in this repository creates or reads it.

## Run

```sh
open build/FocusDock.app
```

To quit, choose **Quit FocusDock** from the menu bar item, or right-click an empty part of the platter.
Quitting normally, `kill <pid>`, or Ctrl-C in a terminal all bring the system Dock back.
The latest end-to-end results are in [docs/research/e2e-phase3.md](docs/research/e2e-phase3.md).

## How the system Dock is hidden

FocusDock calls the `CoreDockSetAutoHideEnabled` SPI, resolved at runtime with `dlsym`; the Dock applies it live, no restart.
It also sets `com.apple.dock autohide-delay` to 1000 s so the hidden Dock does not slide up when the cursor touches the bottom edge.
Before hiding it appends your original autohide setting and `autohide-delay` (value or absent) to the restore ledger, `~/.local/state/focusdock/restore.jsonl`.
The ledger has lines only while FocusDock has the Dock hidden: a normal quit replays it, reads each setting back, and empties it.
The running Dock reads `autohide-delay` only when it starts, so at launch FocusDock restarts the Dock once (SIGTERM, same as `killall Dock`) unless the running Dock already has the delay.
It knows that from `~/Library/Application Support/FocusDock/primed-dock.json`, which records the PID and start time of the last Dock started with the delay in place, or from a Dock that started after FocusDock wrote the delay.
That record survives quits, so relaunching FocusDock in the same login session does not restart the Dock again.
FocusDock enables autohide only once the primed Dock is running; if no Dock comes back within 5 s, it restores the settings and leaves the Dock visible.
If FocusDock crashes, its watchdog (the same binary started with `--watchdog <pid>`) replays the ledger; the next launch replays anything still there before hiding again, so it never records "hidden" as your original.
If the system Dock ever stays hidden, run `focusdock restore`, or `defaults write com.apple.dock autohide -bool false && killall Dock`.

## Permissions

Phase 2 needs none; Shortcuts may ask once whether FocusDock can run shortcuts.
Accessibility (badges, window titles) and Automation for Chrome arrive in later phases.

## Layout

- `Sources/FocusDockCore` themes: `ThemeColors` (colors.toml reader and resolver), `ColorMath` (mix, gradients), `TemplateRenderer`, `ThemePaths` + `ThemeRules` (layout, precedence, git safety rule, background choice), `ThemeStaging`, `ThemeEngine` (set, swap, retint batches, reset), `ThemeTargets` (Zed, Claude Code, btop, saved originals), `SettingsText` (one-key JSONC and conf edits), `ShellTheme`, `FileLock`.
- `Sources/FocusDock` themes: `ThemeCLI`, `ThemeSystem` (engine wiring, JankyBorders and wallpaper targets), `ThemeMenu`, `ShellThemeWatcher`, `ShellStyle`.
- `Themes/`, `Templates/`, `schemas/`: shipped themes, templates and config JSON Schemas, copied into the app by `scripts/build-app.sh`.
- `Sources/FocusDockCore`: pure, unit-tested logic: `Config` (modes.json model and cross-reference checks), `ConfigDocument` (JSONC, JSON Schema and Codable pipeline with positioned problems), `JSONCPositions`, `DefaultModes`, `ModeMachine` (the mode-switch state machine, SPEC 6), `WindowRouting` (window routing, executable lookup, Focus shortcut names), `FocusFollow` (subscription events, jump-to-other-mode decision, echo token), `DockMetrics` (every visual constant), `PlatterLayout` (geometry shared by drawing and hit-testing), `TileList` (a mode's tiles), `NativeDockKeeper` (hide/restore decisions), `DockPriming` (whether the running Dock must restart).
- `Sources/FocusDock`: the AppKit/SwiftUI app: `ModeController` (runs the machine's side effects), `ConfigStore` (load, default, hot reload), `AeroSpace`, `Focus`, `MenuBar`, `DockPanel`, `DockHostingView` (mouse input), `DockView`/`PillView`/`TileView`, `Model`, `Workspace`, `NativeDock`, `DockPrimer`, `ProcessRunner`.
