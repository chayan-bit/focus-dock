# Omarchy on macOS - research input for FocusDock

Date 2026-10-28, macOS 27 host, read-only research.
Tags: [read] = I read the file or ran the command, [search] = web or gh search result, [prior] = my background knowledge, not re-verified.

## 1. Omarchy today (basecamp/omarchy)

- Repo basecamp/omarchy, MIT, 45.8k stars, last push 2026-10-28; latest release v4.0.6 (2026-10-19), pre-release v4.5.0-rc2 (2026-10-27) [read].
- The manual now lives in the repo under `manual/*.md` (51 chapters, rendered by learn.omacom.io); I read the repo copy, plus `docs/*.md` design docs and 558 `bin/omarchy-*` scripts [read].
- Big change since the Omakub/Hyprland-config era: one long-running Quickshell process, `omarchy-shell`, hosts bar, menu, notifications, OSD, lock screen, clipboard history, wallpaper, dock, polkit, reminders, panels and agents as QML plugins [read docs/omarchy-shell.md].
- Correction to the brief: `Super+Space` is the Omarchy menu, `Super+Alt+Space` is the app grid, `Super+K` shows all keybindings [read manual/07-hotkeys.md].

### Window management
- Compositor is Hyprland, configured in Lua (`~/.config/hypr/bindings.lua`, `looknfeel.lua`, `monitors.lua`; shipped defaults in `default/hypr/*.lua`) [read].
- Layouts are per workspace and persistent: dwindle, scrolling, and a floating-workspace mode (titlebars, minimise-to-dock), cycled with `Super+L`; implemented by tagging windows in `default/hypr/workspace-modes.lua` [read].
- Extras: window groups (`Super+G`), pop-out sticky float (`Super+O`), full scratchpad (`Super+S`), Quake console (`Super+Grave`, opens the default agent), per-monitor workspaces 1-10, gap toggle, per-window transparency toggle, single-window square aspect, zoom (`Super+Ctrl+Z`) [read].
- Mechanism for all of it: `bin/omarchy-hyprland-*` scripts calling `hyprctl` [read].

### Bar
- `omarchy.bar` Quickshell plugin; default widgets: menu, workspaces, status indicators (DND, night light, reminder, recording, stay-awake, dictation), clock, Elsewhen world clock, weather, update badge, tray, keyboard layout, agents, bluetooth, network, audio, display, power; media and mic are off by default [read manual/05].
- Widgets are draggable, the bar can sit on any screen edge and be opaque, glassy or clear; CLI: `omarchy bar position|background|move|set|defaults`, `omarchy plugin enable|disable` [read].
- Every right-side widget opens a keyboard-navigable panel (audio with per-app mixer, network with Wi-Fi and DNS, bluetooth with battery, display with brightness and scaling, power with profiles, calendar, world clock) bound to `Super+Ctrl+<letter>` [read].
- Third-party plugins are git repos with `manifest.json` (kinds: bar-widget, bar, panel, overlay, menu, service) cloned to `~/.config/omarchy/plugins/<id>/` and hot-reloaded; they are unsandboxed code [read docs/omarchy-shell.md].

### Launcher and menu
- The menu is data: `default/omarchy/omarchy-menu.jsonc` overlaid by `~/.config/omarchy/extensions/omarchy-menu.jsonc`, dotted ids form the tree, entries are `action` (shell command), `target` (link) or submenu, with `provider`, `when`, `checked`, `disabled` guards; file-watched, no restart [read docs/menu.md].
- Top-level groups: apps, learn, appearance, trigger, setup, install, remove, update, about, system [read].
- App grid and dock (floating-workspace mode) are shell plugins; app list filtering via `default/omarchy/launcher.hides` [read].

### Keybindings
- Super-centric set in `default/hypr/bindings/*.lua` (applications, clipboard, media, tiling, utilities) with user overrides in `~/.config/hypr/bindings.lua` [read].
- Notable: `Super+Return` terminal, `Super+Shift+Return` browser, `Super+C/V/X` unified clipboard, `Super+Ctrl+V` clipboard history, `Super+Ctrl+T` theme picker, `Super+Ctrl+W` background picker, `Super+Shift+Ctrl+A` default agent, `Super+,` act on latest notification [read].

### Themes
- A theme is a directory with `colors.toml` (mode, accent, selection, muted, 4 background steps, 4 foreground steps, 16 ANSI colours) plus optional `backgrounds/`, `preview.png`, `icons.theme`, `keyboard.rgb`, `light.mode`, `neovim.lua`, `vscode.json`, `shell.<section>.toml`, `unlock.png` and silent video intros [read docs/theming.md].
- About 22 shipped themes under `themes/` (catppuccin, tokyo-night, gruvbox, nord, kanagawa, rose-pine, flexoki-light, lumon, ethereal, hackerman, matte-black, vantablack and more); user themes in `~/.config/omarchy/themes/`, installable from git with `omarchy theme install` [read].
- Rendering: `default/themed/*.tpl` use `{{ key }}`, `{{ key_strip }}`, `{{ key_rgb }}`, `{{ mix a b 15% }}` and gradient helpers; user templates in `~/.config/omarchy/themed/*.tpl` run first; existing files in the theme win over templates [read].
- Templates exist for alacritty, btop, chromium, claude, fcitx5, foot, ghostty, helix, hermes, kitty, neovim, obsidian, pi, t3code, vscode, keyboard RGB, hyprland borders and the shell itself (`shell.toml` feeds QML singletons) [read].
- Switching: `bin/omarchy-theme-set` builds `~/.local/state/omarchy/current/next-theme`, renders templates, then `mv` swaps it to `current/theme` atomically under a `flock`, writes `theme.name`, pushes colours to the running shell over IPC, then retints apps in parallel [read].
- Retint is per-app and cheap: kitty `SIGUSR1`, ghostty `SIGUSR2`, alacritty `touch` of its config, btop `SIGUSR2`, helix and opencode restarts, GTK via `gsettings`, VS Code via a generated local extension, Claude Code via `~/.claude/themes/omarchy.json`, Chromium via a root-owned managed policy `BrowserThemeColor` [read].
- Apps include the fixed path rather than being rewritten: `config-file = ?~/.local/state/omarchy/current/theme/ghostty.conf`, kitty `include`, alacritty `general.import` [read config/ghostty/config etc].
- A `theme-set` hook runs `~/.config/omarchy/hooks/theme-set` and `theme-set.d/*` with the theme name [read bin/omarchy-hook].
- Backgrounds: image or video per theme, remembered per theme, cycled with `Super+Ctrl+W`; active file is the symlink `current/background`; the shell crossfades with snapshots and plays an optional intro video via OWE [read].
- Safety rule: themes cloned from git may not ship `*.lua`, terminal configs or `vscode.json` because those execute code [read].

### Webapps, TUIs, capture, notices
- Webapps: `omarchy-webapp-install` writes a `.desktop` entry plus icon, `omarchy-launch-webapp` runs the default Chromium-family browser with `--app=URL`, `Alt+Shift+L` copies the URL; shipped set includes HEY, Basecamp, WhatsApp, X, YouTube, Zoom, Google Photos/Maps/Messages [read].
- TUIs launch in floating terminals (`omarchy-launch-tui`, `launch-or-focus-tui`): btop ("Activity"), lazygit, herdr, tmux, fastfetch, cliamp, Neovim (LazyVim) [read].
- Screenshots: Omasnap overlay with region, window, fullscreen and scrolling capture, annotation editor, auto-save to `~/Pictures/Screenshots` [read manual/12].
- Recording: `omarchy-capture-screenrecording` with desktop and mic audio and webcam overlay; colour picker on `Super+Print`; OCR is `hyprpicker` freeze + `slurp` + `grim` + `tesseract` + `wl-copy` [read bin/omarchy-capture-text].
- Notifications: shell plugin, decks per app, history for one day, `Super+,` acts on the newest, silencing is a flag file `~/.local/state/omarchy/toggles/*-off`, sender is `omarchy-notification-send` [read docs/notifications.md, manual/10, 13].
- Reminders (`omarchy reminder 7 'text'`), clipboard history with images, emoji picker, LocalSend share menu, transcode menu, weather and battery notices [read].

### System: lock, idle, night light, audio, bluetooth, wifi
- Lock, idle, screensaver, night light (`hyprctl hyprsunset temperature`, 4000 K on, 6500 K off) are toggles under `omarchy toggle ...`; lock is a shell plugin holding the Wayland session lock [read].
- Audio via wireplumber (`omarchy-audio-*`), bluetooth (`omarchy-bluetooth-*`), network (`omarchy-network-*`, DNS picker), brightness incl. DDC and Apple panels, hardware quirk scripts `omarchy-hw-*` [read].

### Update and migration
- Omarchy is pacman packages from the omarchy-pkgs repo; `omarchy update` runs a snapshot, the package transaction, then per-user `migrations/*.sh` (timestamp-named, idempotent, markers in `~/.local/state/omarchy/migrations/`), hooks and restart checks; channels stable, RC, edge, dev; rollback via boot-menu snapshots or `omarchy reinstall` [read docs/update-process.md, manual/30].

### AI bits (more than the brief assumed)
- Default-agent concept (`omarchy default agent`, `Super+Shift+Ctrl+A`, `omarchy agent prompt "..."`), 23 agent CLIs installed lazily through mise, one-time notification to choose [read manual/17].
- Agents panel in the bar: per-account plan, 5-hour and weekly meters with reset time, collected every 15 min by `omarchy agent usage-update` from `bin/omarchy-agent-usage-*` (claude, codex, copilot, cursor, ollama, ...) [read].
- Multi-subscription switching (`omarchy agent account add|use|list|copy|autoswitch`) with a notification at 95% of a limit [read].
- Crash diagnosis: systemd-coredump watcher notifies, click hands the crash to the default agent with a "diagnose-crash" skill [read].
- An "Omarchy skill" is symlinked into Claude, Codex, Pi, Antigravity and Hermes skill dirs so agents can edit Hyprland, the bar and themes; the manual calls it experimental, advises plan mode and `omarchy reinstall configs` as the undo [read].
- Themes also sync to Claude Code, Pi, OpenCode and Hermes (`omarchy-theme-set-claude`, `-pi`, `-hermes`) [read].

## 2. Existing macOS ports (all small, none nix-native)

- Nothing above 10 stars; `omacom/omarchy-mac-installer` is Omarchy on Apple Silicon Linux, not macOS, so ignore it [search].
- EhsanulHaqueSiam/macarchy: 0 stars, MIT, pushed 2026-10-04; AeroSpace + skhd + SketchyBar + JankyBorders; Brewfile + GNU stow + `macos-defaults.sh`; claims 144 of 152 mappable Omarchy bindings (SUPER=Option, Omarchy ALT=Command) [read].
- Its unreproducible list: window transparency, single-window square aspect, webcam overlay, laptop-display toggles, scroll-to-switch-workspace, true tabbed groups, Hyprland animations, F9 push-to-talk; Focus toggle needs a hand-made Shortcut because macOS has no Focus CLI [read].
- Its theme step reads Omarchy's `colors.toml` and regenerates SketchyBar `theme.sh` and border colours; helper scripts `omarchy-mac-*` use `osascript`, `screencapture -i`, `caffeinate -d`, `nightlight`, `aerospace workspace S` for scratchpad [read].
- jlargs64/macarchy: 1 star, MIT, pushed 2026-10-26, the most complete; yabai (no scripting addition) + skhd + SketchyBar + JankyBorders, stow-based, no nix mention [read].
- Its theme engine ports all 22 Omarchy themes plus one custom: `theme-set <name>` repoints symlink `~/.config/theme/current`, runs one hook script per app (Ghostty, kitty, Alacritty, iTerm2, VS Code forks, Zed, Zellij, Neovim, SketchyBar, JankyBorders, wallpaper), skips missing apps, user hooks in `~/.config/macarchy/hooks.d/` [read docs/theme-system.md].
- It also ships a `ws` agent: plain-English or voice commands -> 14 MB on-device Cactus Needle model (~40 ms) -> validated tool calls (focus, send_to_space, warp, theme, wallpaper), dry-run by default, vocabulary gate before any model call [read docs/agent.md].
- Also has `macarchy-doctor` and a rescue script for the classic silent failures (secure keyboard entry killing skhd, lost Accessibility grant after an upgrade) [read].
- HarryRandall/macarchy: 6 stars, MIT, pushed 2026-10-21; yabai + skhd + SketchyBar + Ghostty + Raycast, modular `./install window-manager sketchybar themes raycast` with `--dry-run` and backups [read].
- Its `theme-switch` writes only tool-owned generated files (Ghostty `macarchy-theme.ghostty`, btop theme, borders, SketchyBar, Neovim state, macOS appearance, Raycast defaults), and ships a TypeScript Raycast extension as the picker [read].
- Its `bin/set-wallpaper` tries desktoppr first, then Finder AppleScript, System Events AppleScript, then the wallpaper-store plist [read].
- Others seen but not read: nic0der-im/HackermacUI (AeroSpace, SwiftBar, JankyBorders, Ghostty), PitterQuenallata/mac-theme-mallku (SwiftUI menu bar theme app, no SIP), gllmt/macarchy (OmniWM + Raycast), avb7/macarchy, bweave/omakub-macos [search].
- Reuse verdict: port Omarchy's `colors.toml` themes directly (MIT) and borrow jlargs64's hook-per-app shape; nobody has a native shell, a nix module, or a Liquid Glass UI, so the FocusDock layer is genuinely new.

## 3. macOS equivalents (versions from this machine's nixpkgs)

- Hyprland -> AeroSpace 0.21.3-Beta, MIT, in nixpkgs, `services.aerospace` (nix-darwin) and `programs.aerospace` with launchd (home-manager) [read].
- AeroSpace fakes workspaces by parking windows off-screen, has no config include, no animations, no per-window opacity, no groups or tabs; it does have binding modes, `subscribe` JSON event stream, `list-windows`, `layout`, `join-with`, `summon-workspace`, `trigger-binding` [read docs].
- Alternative yabai 7.1.25 (nixpkgs, `services.yabai`): BSP tiling with more window control but the scripting addition needs SIP changes, and macOS 27 support is UNRESOLVED; FocusDock's spec already chose AeroSpace [read].
- Waybar/omarchy-bar -> SketchyBar 2.24.1, GPL-3.0, `services.sketchybar` takes a config script and runs it from the store; runtime control with `sketchybar --reload`, `--set`, `--bar` [read].
- SketchyBar cannot draw Liquid Glass; a native NSPanel bar inside FocusDock can, and is the same window technique as the dock, so prefer native and keep SketchyBar as the cheap Phase 1 option [prior].
- Window borders -> JankyBorders 1.9.0, GPL-3.0, `services.jankyborders`; the nix-darwin module exposes only static launch args, but re-running `borders active_color=0x... inactive_color=0x...` updates the live instance [read].
- Omarchy menu -> own SwiftUI panel (recommended: same JSONC tree schema, same hot-reload, doubles as the agent command bar); Raycast 2.7.3.0 in nixpkgs is proprietary and only themeable via its own appearance prefs, with script commands as the action hook [read, prior].
- Other launchers: Spotlight (no theming, surfaces App Intents), Sol (ospfranco/sol, MIT, 3.2k stars; not in nixpkgs by that name, cask status UNRESOLVED) [search, read].
- Keys: AeroSpace has built-in binding modes but no per-app chords; skhd 0.3.9 (asmvik/skhd, last push 2025-12) covers non-WM actions and breaks under Secure Keyboard Entry; Karabiner-Elements 15.7.0 (nixpkgs) can synthesise a Super/Hyper key since macOS has none [read, prior].
- Ghostty 1.3.1 (nixpkgs `ghostty-bin`, home-manager `programs.ghostty`): `config-file = ?path` optional include, `theme = light:X,dark:Y`, `background-blur`, `macos-glass-regular`/`macos-glass-clear` on macOS 26+; 1.3.0 added AppleScript `perform action "<keybind action>"`, so `reload_config` should work but is UNRESOLVED until tried [search].
- Zed: user themes in `~/.config/zed/themes/*.json`, `theme` setting accepts `{mode, light, dark}`, `theme_overrides` keyed by theme name; live reload behaviour UNRESOLVED [search].
- btop 1.4.7 (nixpkgs, `programs.btop`): theme file in `~/.config/btop/themes`, Omarchy reloads with `SIGUSR2` [read, prior].
- Neovim: Omarchy loads a per-theme `neovim.lua` at startup; macarchy ships a LazyVim plugin spec and state file [read].
- Wallpaper: desktoppr 0.5 (nixpkgs, Apache-2.0) `desktoppr all <img>`, or `NSWorkspace.setDesktopImageURL(_:for:options:)` per screen from FocusDock itself with no dependency [read, prior].
- Video wallpapers and intros have no system support; an own desktop-level borderless AVPlayer window is the only route, effort UNRESOLVED [prior].
- Capture: `screencapture -i`, ScreenCaptureKit for recording, Vision `VNRecognizeTextRequest` instead of tesseract, `NSColorSampler` for the picker [prior].
- Night light: `nightlight` CLI uses a private CoreBrightness API; Night Shift is the supported path [read, prior].
- Stay awake: `caffeinate -d`; lock: `ctrl+cmd+Q` keystroke or `CGSession -suspend` [read].
- Audio, Bluetooth, Wi-Fi panels: CoreAudio, IOBluetooth, CoreWLAN (SSID read needs Location permission), `networksetup` [prior].
- Webapps: Chrome or Brave `--app=URL` works as on Omarchy, or a frameless WKWebView window inside FocusDock with its own profile [read, prior].
- Updates and migrations: nix-darwin generations replace pacman snapshots; migrations become a numbered-script runner in the state dir that Nix does not own [prior].

### What macOS cannot do without SIP changes
- Notification Center banners cannot be restyled; replace by holding them with a Focus mode and drawing own cards (SPEC section 8) [read, prior].
- Lock screen and login window cannot be themed beyond wallpaper and clock style; Omarchy's lock is a custom session-lock surface with no macOS equivalent [prior].
- Per-window opacity, shadow and sticky flags, moving windows between native Spaces, and Dock injection need yabai's scripting addition (SIP partly off) [prior].
- The native Dock cannot be removed, only auto-hidden (as SPEC 4.4) and the menu bar can only be auto-hidden, not replaced [prior].
- Do not make the product depend on SIP changes or elevated privileges, since most users will not have them; this machine's security configuration is out of scope here.

## 4. Theme engine design for a Nix-managed machine

- Core idea: Omarchy never writes into app configs, it writes into its own state dir and apps include a fixed path, so the only thing Nix must own is the include line [read].
- Proposal: theme inputs (`colors.toml`, backgrounds, user templates) may be Nix-declared and read-only; outputs go to `~/.local/state/focusdock/current/theme/` and are never in the Nix store.
- Use Omarchy's `colors.toml` keys and `{{ key }}` template syntax unchanged so the 22 Omarchy themes import verbatim (MIT).
- Atomic swap exactly like `omarchy-theme-set`: render to `next-theme`, `mv` to `current/theme`, `flock` for serialisation, then parallel retint with a generation token so stale retints are skipped [read].
- Per-app include points, each declared once in Nix and never edited again:
- Ghostty: `config-file = ?~/.local/state/focusdock/current/theme/ghostty.conf` (HM `programs.ghostty.settings`), reload via keybind action or AppleScript [read, search].
- WezTerm (the terminal in use here): HM file stays a store symlink; add `local ok, t = pcall(dofile, wezterm.home_dir .. "/.local/state/focusdock/current/theme/wezterm.lua")` and `wezterm.add_to_config_reload_watch_list(path)`, WezTerm reloads on change [read, search].
- SketchyBar: the nix-darwin `config` text ends with `source ~/.local/state/focusdock/current/theme/sketchybar.sh`; apply with `sketchybar --reload` or targeted `--set` for no flicker [read].
- JankyBorders: leave colours out of the Nix options and push `borders active_color=...` from the retint step, plus once at login via a launchd agent or AeroSpace `after-startup-command` [read].
- Zed: today `~/.config/zed/settings.json` is a plain mutable file, so the engine rewrites only the `theme` key with `jq`; do not move it to `programs.zed-editor.userSettings`, which would make it read-only [read, prior].
- Neovim: `~/.config/nvim` is a plain LazyVim tree here; add a small plugin that watches `current/theme/neovim.lua` with `vim.uv.new_fs_event` and re-applies, so open editors update live [read, prior].
- btop: set `color_theme = "focusdock"` once and symlink `~/.config/btop/themes/focusdock.theme` to the state file, then `pkill -USR2 -x btop` [read].
- FocusDock itself and the glass tint: read `shell.toml` and `colors.toml` with a file watcher, no restart.
- The existing `home.nix` already uses `config.lib.file.mkOutOfStoreSymlink` for editable scripts, so the same primitive can expose `~/.config/focusdock/themes` as a live-editable directory in the repo when wanted [read home.nix lines 122-130].
- Prior art confirms both shapes: jlargs64 moves a `current` symlink and runs one hook per app; HarryRandall writes only tool-owned generated files per app and records the chosen theme and background in `~/.local/state/macarchy/themes` [read].
- Keep security parity: themes from a git URL are colour-only, never `*.lua`, shell hooks or terminal configs, as in `INSTALLED_THEME_DENIED` [read].
- Rollback story: Nix generations roll back structure, the state dir roll back is `focusdock theme set <previous>` using a stored `theme.name`.

## 5. Current nix-darwin config (`~/.config/nix-darwin`, read only)

- NOT declared and not installed: AeroSpace, SketchyBar, JankyBorders, skhd, yabai, Ghostty, btop, Raycast, desktoppr [read: `command -v` all empty].
- WezTerm is declared with home-manager (`programs.wezterm`, extraConfig as a Lua string), so `~/.config/wezterm/wezterm.lua` is a read-only store symlink and its include point goes in that Lua string [read].
- Zed is not managed by Nix: `~/.config/zed/settings.json` is a raw, mutable file, so the engine edits only its `theme` key [read].
- Neovim's `~/.config/nvim` (LazyVim) is a raw, mutable tree, so its include point is a small watcher plugin [read].
- Gap list to add for this project (all verified present in nixpkgs): aerospace, sketchybar, jankyborders, ghostty-bin or keep WezTerm, btop, desktoppr, karabiner-elements; services via nix-darwin `services.aerospace`, `services.sketchybar`, `services.jankyborders` [read].

## 6. AI-native agent features that are real today

Platform facts first:
- macOS 27 ships Apple's own `/usr/bin/fm` (Foundation Models CLI): `fm respond`, `fm chat`, `fm schema` (structured output), `fm count-tokens`, `fm serve` (Chat Completions server, models `system` on-device and `pcc` Private Cloud Compute) [read].
- `fm serve` was documented empirically on 127.0.0.1:17601 with `/v1/chat/completions`, streaming default true [search 0Itsuki0/CustomModelForFMCLI].
- Framework side: `LanguageModelSession`, `@Generable` guided generation, `Tool` protocol, check `SystemLanguageModel.default.availability`; a ~4K token context is claimed by one guide and unconfirmed [search].
- `/usr/bin/shortcuts` exists for running Shortcuts, `/usr/bin/osascript` for AppleScript and JXA [read].
- Claude Agent SDK: official TypeScript (`@anthropic-ai/claude-agent-sdk`, 1.8k stars) and Python (`claude-agent-sdk`, MIT, 8.4k stars) with in-process custom tools, hooks and permission callbacks; Swift SDKs are community, 3 stars or fewer, so drive TS/Python or `claude -p --output-format stream-json` as a subprocess [read, search].
- Peekaboo (openclaw/Peekaboo, MIT, 5.4k stars, pushed 2026-10-27): CLI + MCP for screenshots, Accessibility inspection, click/type/menu/dock/window tools and its own `agent`; already connected in this Claude Code [read].

Features, each with mechanism, permission, prior art:
1. Command bar acting on the frontmost app: agent + Peekaboo `see`/`click`/`type` over the AX tree, asking per destructive step; needs Accessibility + Screen Recording; prior art Peekaboo agent, huashu-mac-use (329 stars), computer-use-mcp (50 stars) [read, search].
2. "Tidy my windows into modes": `aerospace list-windows --json` -> classify apps into modes -> propose a `modes.json` diff and apply with `move-node-to-workspace`; no extra permission beyond Accessibility; prior art macarchy `ws` window tools [read].
3. Natural-language config edits: Agent SDK restricted to `~/.config/focusdock` (Read/Edit only), JSON-schema validation before write, hot-reload, one-step undo; Omarchy ships exactly this as a skill with plan-mode advice [read].
4. Theme from wallpaper: palette extraction in Swift (k-means) or Claude vision, emit `colors.toml`, run the theme engine, name it with `fm respond`; no permission beyond file read; prior art pywal-style tools, macarchy goes the opposite way (palette -> wallpaper) [read, prior].
5. Screen-aware ask: one ScreenCaptureKit frame plus AX text of the focused window sent to Claude vision; Screen Recording; prior art Peekaboo `analyze`, screenpipe (22k stars, non-OSI licence) [read, search].
6. Held-notification triage per mode: usernoted DB read -> on-device `fm schema` classification (urgent, needs answer by time) -> card above the dock; Full Disk Access; escalate to Claude only for modes not marked `private` (SPEC section 8) [read].
7. Drift detection: sample app, window title, URL host and ask the local model "does this fit the current mode"; Accessibility + Automation for browsers; on-device so nothing leaves the machine [read SPEC].
8. Local intent router for the command bar: `fm serve` or in-process Foundation Models picks a tool and arguments in milliseconds, escalates multi-step requests to Claude; no permission; prior art macarchy `ws` (Cactus Needle, vocabulary gate, validation, dry-run default) [read].
9. Voice commands: Speech framework on-device recognition or Handy transcription feeding the router; Microphone (+ Speech Recognition) permission; prior art macarchy `ws --voice`, Omarchy dictation backends [read].
10. Shortcuts and App Intents bridge: FocusDock exposes App Intents (switch mode, hold notifications, set theme) so Spotlight, Siri and Shortcuts can call it; the agent calls `shortcuts run` for Focus toggles, which needs one hand-made shortcut per Focus (same workaround macarchy documents) [read, prior].
11. AppleScript/JXA tools with a per-app allow-list: Chrome tabs, Mail, Calendar, Finder, Notes; Automation (TCC) prompt per target app; the SPEC's `Chrome.swift` is the first instance [read].
12. Agent usage meters in the bar: Omarchy's collectors read local Claude/Codex logs to draw 5-hour and weekly limits and can auto-switch accounts; a Mac version reads `~/.claude` logs, file access only; OpenUsage.app is already installed here as a UI reference [read].
13. Crash and issue diagnosis: watch `~/Library/Logs/DiagnosticReports/*.ips` with FSEvents, notify, click hands the report to Claude Code with a diagnose skill, as Omarchy does with coredumps; file access only [read, prior].
14. Drop-down agent console: hotkey NSPanel hosting a terminal session of the default agent in the current mode's project directory, as Omarchy's Quake console does; no permission [read].
15. Calendar-driven modes: EventKit read -> suggest or auto-schedule the next mode and hold notifications before meetings; Calendars permission [prior].
- Cross-cutting guardrails: route every agent tool through one allow-list and an append-only audit log, use the SDK's per-tool permission callback, dry-run by default as macarchy does, and never let held-notification text reach a cloud model in `private` modes [read, prior].

## UNRESOLVED
- Ghostty macOS live reload action name and whether SIGUSR2 works on macOS.
- yabai on macOS 27, and whether AeroSpace 0.21.3-Beta has any scrolling-style layout.
- Zed live theme reload and a mutable-settings option in `programs.zed-editor`.
- Sol availability as a nix package or cask, and Raycast script-command theming depth.
- Real size of the Foundation Models context window on macOS 27.
- I did not read HackermacUI, mac-theme-mallku, gllmt/macarchy or the Omarchy QML sources beyond their docs.
