# E2E Phase 3 (themes), 2026-10-28

Build: `scripts/build-app.sh` from the Phase 3 working tree, run on this Mac (macOS 27, MacBook Air, 1470x956 pt, one screen).
Omarchy pinned at `aba49d22cf77b4a8fd1859c721d6bbc6e986a27e`; `scripts/sync-backgrounds.sh tokyo-night catppuccin-latte gruvbox` downloaded 17 images, all checksums matched.
btop 1.4.7 and JankyBorders (`org.nixos.jankyborders`) from Nix; `~/.config/btop/` did not exist; Claude Code's `theme` was `"auto"`; Zed's `theme` was the object `{ "mode": "system", "light": "One Light", "dark": "One Dark", }`.
Before the run I copied `~/.config/zed/settings.json`, `~/.claude/settings.json` and the wallpaper store `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`, and recorded `NSWorkspace.desktopImageURL` per screen (Catalina.heic, dynamic).
Crops are the bottom 97 pt of the screen at 1x; they show only the dock strip and the wallpaper behind it.

## Results

| Check | Result | Evidence |
|---|---|---|
| No theme: dock looks as in Phase 2 | pass | `e2e-phase3/0_no_theme.png` |
| `theme set tokyo-night` (dark): glass tinted navy, collapsed pills and running dots in the accent, live without restart | pass | `1_tokyo-night.png` |
| `theme set catppuccin-latte` (light): light glass, dark symbols, blue accent | pass | `2_catppuccin-latte.png` |
| `theme set gruvbox` (dark, warm): teal accent, warm glass | pass | `3_gruvbox.png` |
| Theme submenu: checkmark on the current theme (Gruvbox), 23 themes + Reset Theme, enabled; choosing Nord from it applied Nord from the dock process | pass (driven through Accessibility, as in Phase 2) | `4_nord_from_menu.png`, log `set nord` |
| Zed: `~/.config/zed/themes/focusdock.json` written (family and theme "FocusDock", appearance from mode); `settings.json` line 66 became `"theme": "FocusDock",`, nothing else changed | pass | `theme-set.log` |
| btop: `color_theme = "focusdock"` in a new `~/.config/btop/btop.conf`, link `themes/focusdock.theme -> ~/.local/state/focusdock/current/theme/btop.theme`, `pkill -USR2 -x btop` sent | pass | `theme-set.log` |
| JankyBorders: `borders active_color=0xff7aa2f7 inactive_color=0xaa414868` (Tokyo Night), `0xff1e66f5 / 0xaaacb0be` (Latte), `0xff7daea3 / 0xaa665c54` (Gruvbox) | pass | `theme-set.log` lines |
| Wallpaper: `desktopImageURL` became `.../tokyo-night/backgrounds/0-liftoff.webp`, then `.../catppuccin-latte/backgrounds/1-color-fade.webp`, then `.../gruvbox/backgrounds/1-the-backwater.jpg`; WebP works as a desktop picture | pass | NSWorkspace query |
| Nord has no synced backgrounds: wallpaper left unchanged, logged | pass | log `theme has no backgrounds` |
| Claude Code: `~/.claude/themes/focusdock.json` (`name` FocusDock, `base` dark/light, `claude` = accent), `settings.json` `"theme": "custom:focusdock"`, hooks and every other key untouched | pass | file + `grep` |
| WezTerm and Neovim files: `wezterm.lua` and `neovim.lua` load with `nvim --headless --clean -l` (`loadfile`), 8 ansi + 8 brights + tab_bar; `zed.json` and `claude.json` parse as JSON | pass | headless check |
| Three `theme set` runs started at once: final theme, Claude file (`base` light), accent and wallpaper all agree (catppuccin-latte) | pass | log, files |
| `theme reset`: Zed and Claude `settings.json` byte-identical to the copies (`cmp`), modes kept (0600 / 0644); `~/.config/btop/`, `~/.claude/themes/`, `~/.config/zed/themes/focusdock.json` gone; borders set to `0x00000000`; `desktopImageURL` back to Catalina.heic with the same options; `current/theme` removed | pass | `cmp`, `ls`, NSWorkspace query, `5_after_reset.png` |
| Wallpaper store after reset | first run: fail, fixed, re-run: pass | see below |
| Final state: no theme, FocusDock quit, native Dock `autohide` 0 and `autohide-delay` absent | pass | `defaults read` |

## The wallpaper store finding

On the first reset the per-screen URL came back, but `Index.plist` lost the `style: dynamic` option of the Catalina dynamic wallpaper: `NSWorkspace.setDesktopImageURL` has no way to say "dynamic".
I put the copied store back by hand (`cp` + `killall -KILL WallpaperAgent`, which launchd restarts and which then reads the file) and the only remaining differences were timestamps.
`WallpaperTarget` now saves the store once with the URLs and, on reset, restores the URLs, then the store, then restarts WallpaperAgent the same way.
Re-run of set tokyo-night, set catppuccin-latte, reset with the rebuilt app: Zed and Claude settings `cmp`-identical, wallpaper URLs identical, store XML differs only in 10 `<date>` lines (WallpaperAgent stamps them on load), nothing left in `originals/`.

## Apps live

Fresh windows opened only for this run, starting from no `current/theme`: WezTerm running an ANSI swatch (`wezterm start --always-new-process`), a second WezTerm started with `--config-file ~/.config/wezterm/wezterm.lua`, Neovim on a scratch Swift file, btop, and Zed (not running before).
After each `focusdock theme set`, a 3 s wait, then `screencapture -l <window id>` of those windows only and the sRGB median of a 9x9 background patch.
Crops are in `e2e-phase3/apps/<step>-<app>.png`; nothing was restarted between steps.
The process list in the btop crops is pixelated for publishing; the medians below were measured on the original captures.

| Step | Expected bg | WezTerm (default config) | WezTerm (Nix config) | Neovim | btop | Zed |
| --- | --- | --- | --- | --- | --- | --- |
| 0 none | - | #1c1c1c | #24273a | #222436 | #000000 | #282c33 |
| 1 tokyo-night | #1a1b26 | #1c1c1c (no change) | #191b26 | #191b26 | #191b26 | #191b26 |
| 2 catppuccin-latte | #eff1f5 | #1c1c1c (no change) | #eff1f5 | #eff1f5 | #eff1f5 | #eff1f5 |
| 3 gruvbox | #282828 | #1c1c1c (no change) | #282828 | #282828 | #282828 | #282828 |
| 4 reset | step 0 | #1c1c1c | #24273a | #222436 | #000000 | #282c33 |

Every retinted window is within 1/255 on one channel of the colors.toml background (the tokyo-night red channel, display-profile rounding), and reset returns every window to its step-0 colour.

Findings:

- **WezTerm does not retint with the user's real config.** An unmanaged `~/.wezterm.lua` (2026-02-20, time-of-day scheme) exists, and WezTerm loads `$HOME/.wezterm.lua` before `~/.config/wezterm/wezterm.lua`, so the Nix include never runs; the user's own WezTerm (`/Applications/WezTerm.app`) uses that file too.
  The same windows started with the Nix config retint live, including the first set from no theme.
  Not changed here: removing or merging `~/.wezterm.lua` changes the user's terminal look, so it is their call.
- **Neovim kept a light `background` into a dark theme.** After catppuccin-latte, `:colorscheme gruvbox` rendered gruvbox light (#fbf1c7), because gruvbox follows `background`.
  Fixed in `~/.config/nvim/lua/plugins/focusdock-theme.lua`: it now sets `background` from the resolved `mode` in `current/theme/focusdock.toml` before `:colorscheme`, and restores the startup `background` on reset; the re-run above is with the fix.
- Neovim applies the switch only once it is back in its main loop: in this config Mason prints hit-enter prompts at startup, and until they are dismissed no scheduled callback (the watcher) runs.
- The Nix WezTerm status bar (left/right status, tab titles) still uses hard-coded Catppuccin Macchiato colours, so under a light theme the status segments stay dark; only `tab_bar.background` follows the theme.
- `~/.config/nvim/lazy-lock.json` is byte-identical to before the run; no plugin was updated.

Clean-up: all test windows closed (the user's WezTerm left alone), Zed quit, no theme set, FocusDock not running, Dock `autohide` 0, btop and Zed theme keys back to the originals.

## Not covered here

- Multiple screens: only the built-in display was connected; the code keys saved wallpapers by display id.
