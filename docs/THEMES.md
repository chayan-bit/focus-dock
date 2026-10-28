# FocusDock themes: the contract

This is what other tools (the Nix config, the Neovim plugin, WezTerm, future agents) may rely on.
The engine is a port of Omarchy's (`bin/omarchy-theme-set`, pinned in [THIRD_PARTY.md](../THIRD_PARTY.md)); SHELL-SPEC section 3 has the design.

## Commands

```sh
focusdock theme list            # every theme, "*" marks the current one
focusdock theme current         # exits 1 when no theme is set
focusdock theme set <name>      # "Tokyo Night" and "tokyo-night" both work
focusdock theme next | prev     # alphabetical, wrapping
focusdock theme reset           # back to exactly what was there before any theme
```

`focusdock` is `scripts/install-cli.sh`'s wrapper for `FocusDock.app/Contents/MacOS/FocusDock`; the binary itself takes the same arguments.
Errors go to stderr with exit status 1; a target that fails to retint is reported on stderr but does not fail the switch (as in Omarchy).
The menu bar item has the same list under **Theme**, with **Reset Theme**.

## Inputs

| Path | What |
|---|---|
| `FocusDock.app/Contents/Resources/Themes/<name>/` | Shipped themes (repo `Themes/`): `colors.toml`, and `neovim.lua`, `btop.theme`, `preview.jpg` where Omarchy ships them |
| `FocusDock.app/Contents/Resources/Templates/*.tpl` | Shipped templates (repo `Templates/`) |
| `~/.config/focusdock/themes/<name>/` | User themes; override a shipped theme of the same name file by file |
| `~/.config/focusdock/themed/*.tpl` | User templates; replace the shipped template with the same output name |
| `~/.config/focusdock/backgrounds/<name>/` | Extra backgrounds for a theme |
| `~/.local/share/focusdock/themes/<name>/backgrounds/` | Shipped themes' backgrounds, downloaded by `scripts/sync-backgrounds.sh` (never in the repo) |

`$FOCUSDOCK_RESOURCES` replaces the app's Resources directory (point it at a repo checkout to run from `swift build`).

Precedence when a theme is applied, highest first: a file the theme directory already has, a user template, a shipped template.
A user theme directory containing `.git` (not a symlink) came from a stranger and may only add colours and images: any `*.lua`, `alacritty.toml`, `foot.ini`, `ghostty.conf`, `kitty.conf`, `vscode.json` and every symlink are dropped and named on stderr; the template output takes their place.

`colors.toml` is Omarchy's flat `key = "value"` format, read by Omarchy's own rules: `mode`, `accent`, `selection`, `muted`, `background`, `dark_background`, `darker_background`, `lighter_background`, `foreground`, `dark_foreground`, `light_foreground`, `bright_foreground`, `red`, `yellow`, `orange`, `green`, `cyan`, `blue`, `magenta`, `brown` and the six `bright_*` colours, with the legacy `bg`/`fg`/`colorN` names and derived shades filled in.
Templates use `{{ key }}`, `{{ key_strip }}`, `{{ key_rgb }}`, `{{ mix[_strip|_rgb] a b 15% }}`, `{{ hypr_gradient k fallback }}`, `{{ gradient_start k fallback }}` and `{{ shell_gradient k fallback }}`.

## State: `~/.local/state/focusdock/`

| Path | What | Who reads it |
|---|---|---|
| `current/theme/` | The applied theme, replaced in one `renamex_np(RENAME_SWAP)`; absent when no theme is set | everything below |
| `current/theme/colors.toml` | The palette | any tool |
| `current/theme/focusdock.toml` | Dock colours: `mode`, `glass_tint`, `glass_tint_opacity`, `accent`, `text`, `indicator` | FocusDock (watches `current/`); the Neovim plugin reads `mode` |
| `current/theme/wezterm.lua` | `return { foreground, background, cursor_*, selection_*, ansi, brights, tab_bar, ... }`, a table of WezTerm colour keys | WezTerm: `dofile` + reload watch (Nix) |
| `current/theme/neovim.lua` | The theme's own LazyVim spec, or Omarchy's aether spec from the template | Neovim plugin `focusdock-theme.lua` (also reads `mode` from `focusdock.toml` to set `background`) |
| `current/theme/zed.json` | Zed theme family "FocusDock" with one theme "FocusDock" (appearance from `mode`) | copied to Zed by the engine |
| `current/theme/claude.json` | Claude Code custom theme (`name`, `base`, `overrides`) | copied to Claude Code by the engine |
| `current/theme/btop.theme` | btop theme | btop through the symlink below |
| `current/theme.name` | The theme's name | `theme current`, menus |
| `current/theme.generation` | Token of the last switch or reset; a retint batch whose token is stale does nothing | the engine |
| `current/background` | Symlink to the chosen background image | wallpaper target |
| `current/next-theme/` | Staging directory, only during a switch | nobody |
| `theme-backgrounds/<name>` | The background last used with that theme | the engine |
| `originals/` | The user's own values saved before the first retint, removed by reset | the engine |
| `theme.lock`, `theme-retint.lock` | `flock` files serialising switches and retint batches across processes | the engine |
| `theme-set.log` | What the last retint or reset did, one line per target | people, E2E checks |

Consumers must tolerate `current/theme` disappearing (reset) and being replaced by a new directory (every switch): watch `current/`, not a file's inode, and treat a missing file as "no theme".

## What each target does

| Target | On `set` | On `reset` |
|---|---|---|
| FocusDock | nothing; the running dock watches `current/` and re-tints the glass, collapsed pills, divider and running dots | the dock goes back to the native look |
| WezTerm | nothing; its config includes `current/theme/wezterm.lua` | nothing; the include finds no file |
| Neovim | nothing; the plugin reads `current/theme/neovim.lua` | nothing; the plugin falls back |
| Zed | copies `zed.json` to `~/.config/zed/themes/focusdock.json`; sets the top-level `theme` key of `~/.config/zed/settings.json` to `"FocusDock"`, editing only that value's bytes | puts the saved value text back byte for byte (if the key still says `"FocusDock"`), deletes `focusdock.json` |
| btop | links `~/.config/btop/themes/focusdock.theme` to `current/theme/btop.theme`; sets `color_theme = "focusdock"` in `~/.config/btop/btop.conf`; `pkill -USR2 -x btop` | restores the saved `color_theme` line (or removes ours), removes the link and anything it created, signals btop |
| JankyBorders | `borders active_color=0xffRRGGBB inactive_color=0xaaRRGGBB` (`hyprland_active_border` or `accent`, `hyprland_inactive_border` or `muted`) | `borders active_color=0x00000000 inactive_color=0x00000000` |
| Wallpaper | `NSWorkspace.setDesktopImageURL` with `current/background` on every screen; skipped when the theme has no backgrounds | each screen's saved picture, then the saved `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` and a restart of WallpaperAgent (a dynamic wallpaper's style is only in that store) |
| Claude Code | copies `claude.json` to `~/.claude/themes/focusdock.json`; sets `"theme": "custom:focusdock"` in `~/.claude/settings.json`, editing only that key | restores the saved value (or removes the key), deletes the theme file and `~/.claude/themes/` if it created it |

btop's `color_theme` cannot be the state file's path: btop only loads themes found in its theme directories and matches an absolute path by file name alone, hence the link.
The originals are saved once, before the first retint after a reset, so switching themes repeatedly never records a theme's own value as the user's.
