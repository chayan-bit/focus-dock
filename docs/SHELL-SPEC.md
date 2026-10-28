# FocusDock Shell - spec v1 (draft, 2026-10-28)

Extends [SPEC.md](SPEC.md) from "a focus dock" to "Omarchy for macOS, AI-native".
Research input: [research/omarchy-macos.md](research/omarchy-macos.md).
SPEC.md stays the source of truth for the dock, modes, activity and notifications; this file adds the rest of the desktop and the agent layer, and replaces the phase list.

## 1. Shape

- Omarchy itself has converged on one long-running shell process (`omarchy-shell`, Quickshell) that hosts bar, menu, notifications, OSD, lock, clipboard, wallpaper, dock and agents panel as plugins.
- We mirror that: one native Swift process, FocusDock, hosting every surface as an internal module (dock, bar, menu, OSD, cards, agent console, wallpaper).
- Everything that is not a surface is reused: AeroSpace for tiling, JankyBorders for borders, Omarchy's theme format and themes (MIT), Peekaboo for screen and Accessibility control, Apple's on-device Foundation Models (`/usr/bin/fm`), Jev, and Claude.
- Nix installs the tools and owns only fixed include lines; all runtime state lives in `~/.local/state/focusdock/` so live switching never fights read-only store files.

## 2. Omarchy feature map

| Omarchy | FocusDock on macOS | Notes |
|---|---|---|
| Hyprland tiling, workspaces 1-10, layouts | AeroSpace (`services.aerospace`), workspaces per mode plus 1-10 | No animations, opacity or tab groups without SIP changes |
| Window borders | JankyBorders (`services.jankyborders`), colours pushed live by the theme engine | |
| Bar + widget panels | Native glass bar panel in FocusDock; menu bar set to auto-hide | Decided: no SketchyBar |
| Omarchy menu (`Super+Space`), JSONC tree | Command bar panel reading the same JSONC schema, hot-reloaded | Doubles as the agent prompt |
| App grid (`Super+Alt+Space`) | Grid view of the command bar | |
| Keybindings + `Super+K` cheat sheet | AeroSpace bindings for windows, FocusDock global hotkeys for the rest, generated cheat sheet | Super = Caps Lock as Hyper (decision 1) |
| Themes (`colors.toml` + templates, ~22 shipped) | Same format and template syntax, Omarchy themes imported as-is | Section 3 |
| Backgrounds per theme, video intros | `NSWorkspace.setDesktopImageURL` per screen; video wallpaper as a desktop-level AVPlayer window (later) | |
| Notifications (decks, history, `Super+,`) | Held-notification cards (SPEC 8); system banners cannot be restyled | |
| OSD (volume, brightness) | Own glass OSD; system OSD stays unless suppressed | |
| Webapps | Chrome `--app=URL` shims (SPEC 5) | |
| TUIs in floating terminals | AeroSpace floating rule + launch-or-focus helper | |
| Screenshot, recording, OCR, colour picker | `screencapture`, ScreenCaptureKit, Vision OCR, `NSColorSampler` | |
| Clipboard history, emoji picker | Native panel, pasteboard polling | |
| Night light, stay awake, lock | Night Shift, `caffeinate`, lock keystroke | Lock screen cannot be themed |
| Audio, Bluetooth, Wi-Fi panels | CoreAudio, IOBluetooth, CoreWLAN (SSID needs Location) | |
| Default agent, Quake console, usage meters, Omarchy skill, crash diagnosis | Agent layer, section 5 | |
| Update + migrations | nix-darwin generations + numbered migration scripts in the state dir | |

## 3. Theme engine

- A theme is a directory with Omarchy's `colors.toml` (accent, selection, 4 background steps, 4 foreground steps, 16 ANSI) plus optional backgrounds and per-app overrides.
- Templates use Omarchy's syntax (`{{ key }}`, `_strip`, `_rgb`, `mix`); user templates override shipped ones.
- `focusdock theme set <name>` renders into `next-theme`, swaps it to `~/.local/state/focusdock/current/theme` atomically under a lock, then retints every target in parallel with a generation token so a stale retint never wins.
- Targets in v1, with their include point declared once in Nix:
  - FocusDock itself (glass tint, accent, text), live via file watch.
  - WezTerm: `dofile` of the state file + `add_to_config_reload_watch_list`.
  - Neovim (LazyVim): `fs_event` watcher on the generated `neovim.lua`.
  - Zed: rewrite only the `theme` key in its mutable `settings.json`.
  - btop: theme file symlink + `SIGUSR2`.
  - JankyBorders: `borders active_color=...`.
  - Wallpaper: per theme, remembered.
  - Claude Code: `~/.claude/themes/focusdock.json`.
- Themes installed from a git URL are colours and images only, never code (Omarchy's rule).
- An agent can author a theme: wallpaper -> palette -> `colors.toml` -> preview -> apply.

## 4. Command bar and menu

- One SwiftUI panel, `Super+Space`, three things in one input: menu tree, app and file launcher, agent prompt.
- Menu tree is data: `menu.jsonc` shipped + user overlay, dotted ids, `action` / `target` / submenu, `when` and `checked` guards, file-watched (Omarchy's schema, so their menu ideas port directly).
- Typing that matches no menu item goes to the agent router (5.2).
- Every menu action and every agent tool goes through the same action registry, so the keyboard, the menu and the agent can all do exactly the same things.

## 5. Agent layer

### 5.1 FocusDock is an MCP server
- FocusDock exposes its own state and actions as an MCP server on a local socket: modes (get, set, edit), themes (list, set, create), menu actions, windows (via AeroSpace), held notifications, bar widgets.
- Any agent (Claude Code, the built-in router, Codex) drives the desktop through it; Peekaboo MCP adds screen, Accessibility, click and type.
- A `focusdock` skill (like Omarchy's) documents config files, schemas and safe-edit rules for Claude Code.

### 5.2 Three-tier model router
- On-device first: Apple Foundation Models (`fm schema` / in-process `LanguageModelSession`) for intent parsing, short labels and anything in a `private` mode; free, local, milliseconds.
- Jev for typed decisions that need calibrated probabilities: activity-to-mode, notification urgency (SPEC 7-8, your chosen default).
- Claude for multi-step work: the Agent SDK (TypeScript sidecar) or `claude -p --output-format stream-json`, with FocusDock MCP + Peekaboo as tools.

### 5.3 Agent features, in build order
1. Command bar agent that acts on the frontmost app (Accessibility tree, AppleScript, Peekaboo), confirming each destructive step.
2. Natural-language config: "make Building mode block Slack and add Linear" -> schema-checked diff -> apply -> one-step undo.
3. Tidy windows into modes: list windows, propose mode assignment, move them.
4. Theme from wallpaper, and "make it warmer / higher contrast" edits.
5. Screen-aware ask: frame + focused-window text to Claude vision.
6. Drop-down agent console (`Super+Grave`): a terminal running the default agent in the current mode's project.
7. Usage meters in the bar: Claude 5-hour and weekly limits from local logs.
8. Crash diagnosis: new `.ips` report -> card -> hand to Claude Code with a diagnose skill.
9. Calendar-driven modes: suggest or schedule the next mode from EventKit.
10. Voice: on-device Speech -> same router.
11. App Intents: switch mode, set theme, hold notifications from Spotlight, Siri and Shortcuts.

### 5.4 Guardrails
- One allow-list per tool, an append-only audit log of every agent action, dry-run by default for anything that moves, deletes or sends.
- `private` modes never send screen, window or notification text off the machine.
- Agent config edits are validated against the JSON schema before write; the last good config stays live.

## 6. Nix integration

- Add to `home.nix` / `darwin.nix`: `services.aerospace`, `services.jankyborders`, btop, desktoppr only if needed, Karabiner-Elements (Caps Lock to Hyper).
- Add the include lines (WezTerm, Neovim, btop, AeroSpace startup) once; never theme values.
- Later: a home-manager module `programs.focusdock` that builds the app from this repo and installs a LaunchAgent.

## 7. Phases (replaces SPEC.md section 10)

0. Spike: measure the native Dock, verify APIs (in progress).
1. Dock shell: panel, glass, tiles, running dots, hide or restore the native Dock (in progress).
2. Modes: config, pills, countdown, AeroSpace workspaces, Focus toggle, menu bar status.
3. Theme engine: format, renderer, atomic swap, retint targets, Omarchy themes imported, theme picker.
4. Command bar: JSONC menu, launcher, hotkeys, cheat sheet, action registry.
5. Native bar: workspaces, mode, clock, audio, network, Bluetooth, battery, agent-usage widgets with panels.
6. Agent layer: MCP server, skill, router, features 5.3.1 to 5.3.6.
7. Activity and notification triage (SPEC 7-8).
8. Utilities: capture, OCR, colour picker, clipboard, OSD, night light, stay awake, webapps; agent features 5.3.7 to 5.3.11.
9. Polish, home-manager module, migrations.

Each phase ends with a recording of the real flow and a side-by-side check against the native macOS surface it replaces.

## 8. Decisions (2026-10-28)

1. Super key: Caps Lock as Hyper (Cmd+Ctrl+Opt+Shift) via Karabiner-Elements, declared in Nix; every Omarchy `Super+X` binding becomes `Hyper+X`.
2. Terminal: keep WezTerm and theme it through the state-dir include.
3. Bar: native glass bar inside FocusDock; no SketchyBar.
