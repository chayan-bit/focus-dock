# E2E Phase 2 (modes), 2026-10-28

Build: `scripts/build-app.sh` from the Phase 2 working tree, run on this Mac (macOS 27, MacBook Air, 1470x956 pt, tilesize 75, dark wallpaper).
AeroSpace 0.21.2-Beta from nix-darwin (`/run/current-system/sw/bin/aerospace`), workspaces 1-9, W, B, S; focused workspace before the run: 1.
Native Dock before: `autohide` 0, `autohide-delay` absent.
`~/.config/focusdock/modes.json` did not exist, so FocusDock wrote the default.

Input method: Peekaboo's background-only policy refuses foreground clicks and cannot capture the dock panel (window layer 20) or the menu bar, so the dock pills, Stay and the status menu were driven through their Accessibility actions (System Events `AXPress` / menu clicks on the FocusDock process).
Those actions call the same `ModeController` methods as the mouse; the mouse path itself (`PlatterLayout.hit` -> `DockActions`) is covered by `PillLayoutTests`, not by this run.
Evidence crops are the bottom 105 pt of the screen, trimmed by 4 pt at top and bottom and downscaled to 1x; no window content is readable in them.
Mode transitions were read from FocusDock's own log lines (`FocusDock: pill ... pressed`, `FocusDock: mode state ...`).

The user was using the Mac during the run: AeroSpace followed their focus back to workspace 1 several times, the server was briefly disabled by someone else (`aerospace enable off`), and the Writing pill was pressed once from outside the test (log line `pill writing pressed` with no test action at that time).
Each check below was therefore read immediately after its own action.

## Results

| Check | Result | Evidence |
|---|---|---|
| Default config generated from installed apps (Obsidian, Notion, Notes, Claude, Chrome / WezTerm, Zed, Cursor, Chrome, Claude / Slack, WhatsApp, Discord) | pass | `~/.config/focusdock/modes.json` |
| Pills render like the demo: active capsule in mode colour with symbol + name, inactive glass circles, divider, mode tiles, Drive web app with globe badge | pass | [writing_active.png](e2e-phase2/writing_active.png), [building_active.png](e2e-phase2/building_active.png), [social_active.png](e2e-phase2/social_active.png) |
| Writing -> Social shows "Social 0:30" next to a white Stay capsule, ticking each second | pass (0:30, 0:29, 0:28 read 1 s apart) | [social_countdown.png](e2e-phase2/social_countdown.png) |
| Extra presses shorten the wait by 3 s each | pass (0:17 -> 0:13 -> 0:10) | [social_shortened.png](e2e-phase2/social_shortened.png) |
| Stay cancels | pass (state back to `active("writing")`) | [after_stay.png](e2e-phase2/after_stay.png) |
| Countdown completes: dock tiles switch, AeroSpace workspace switches | pass: completion at 0:00 switched to Social and workspace S (first run); Building -> B and Writing -> W read 1.3 s after activation | [social_active.png](e2e-phase2/social_active.png), [building_active.png](e2e-phase2/building_active.png) |
| Menu bar item updates (symbol + name, countdown while pending) | pass via Accessibility: title " Writing", " Social 0:30" ... " Social", " Building" | AX title of FocusDock's status item |
| Menu bar item visible on screen | not visible: on this notched display the crowded menu bar puts it in macOS's "Show Hidden Menu Bar Items" overflow | see Open issues |
| Status menu: modes with checkmark on active, Edit modes.json, Reveal config folder, warnings, Quit FocusDock | pass | AX menu dump below |
| Focus shortcuts missing are reported | pass: `Shortcut "FocusDock Writing" not found`, `"FocusDock Building"`, `"FocusDock Off"` | AX menu dump below |
| Hot reload, atomic save (rename) | pass: `reloaded` 1 s after the save | log |
| Hot reload, in-place write | pass: `reloaded`, TextEdit tile appeared in Writing | [reload_textedit_tile.png](e2e-phase2/reload_textedit_tile.png) |
| Broken edit keeps the last good config with an error | pass: menu shows "modes.json is invalid; keeping the last good config:" and `modes[1].color: "blue" is not a #RRGGBB colour`; dock unchanged | AX menu dump below |
| Deleting modes.json regenerates the default | pass | log |
| Routing: app in one mode (TextEdit only in Building, current Writing) | pass: TextEdit window moved to B | `aerospace list-windows` |
| Routing: app in no mode (Calculator) | pass: stayed on the focused workspace (1) | `aerospace list-windows` |
| Routing: app in several modes (TextEdit in Writing and Building, current Writing) | pass: new window went to W | `aerospace list-windows` |
| "AeroSpace unavailable" in the menu | not observed: AeroSpace was available at every FocusDock command; only unit-level coverage | |
| Quit from the status menu restores the native Dock | pass: `autohide` 0, `autohide-delay` absent, `native-dock.json` removed, `aerospace subscribe` child gone | [native_after_restore.png](e2e-phase2/native_after_restore.png) |

Status menu during the broken-config check (AX titles, separators omitted):

```
Writing ✓ / Building / Social
Edit modes.json / Reveal config folder
modes.json is invalid; keeping the last good config:
modes[1].color: "blue" is not a #RRGGBB colour
Shortcut "FocusDock Writing" not found
Shortcut "FocusDock Building" not found
Shortcut "FocusDock Off" not found
Quit FocusDock
```

## Final state

FocusDock not running, native Dock restored (`autohide` 0, `autohide-delay` absent), TextEdit and Calculator quit, AeroSpace running on workspace 1, `modes.json` back to the generated default.

## Open issues

- The status item lands in the menu bar overflow on this Mac (notch + many extras); it is reachable through "Show Hidden Menu Bar Items", or by Cmd-dragging it right.
- Switching mode moves the user away from windows on other workspaces (here workspace 1); AeroSpace then follows focus back. Mode and AeroSpace workspace can drift apart; FocusDock does not yet follow `focused-workspace-changed`.
- The "AeroSpace unavailable" path was not exercised live.
