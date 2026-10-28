# Phase 1 E2E run (2026-10-28)

Machine and setup as in [phase0.md](phase0.md): built-in display 1470x956 pt at 2x, dark appearance, dark sea wallpaper, `tilesize` 75, native Dock autohide off.
FocusDock built with `scripts/build-app.sh` and launched with `open build/FocusDock.app`.
Every screenshot is a `screencapture -R` crop of the Dock strip (bottom 105 pt) or of the label area only; evidence is in [e2e-phase1/](e2e-phase1/).
Measurements are pixel profiles of 2x crops, so 1 px = 0.5 pt and positions are good to about +-0.5 pt.
Input was synthesised with CGEvent (mouse move, click, right-click); the frontmost app was read with `lsappinfo front`; the native Dock state with `CoreDockGetAutoHideEnabled` via dlsym (getter only).
Calculator was added as an extra tile with the launch-argument hook `--args -FocusDockExtraApps '("/System/Applications/Calculator.app")'`, because it is not in the user's Dock.

## Results

| # | Check | Result |
|---|---|---|
| 1 | Native Dock hides on launch | PASS: getter `true` while running, state file `{"originalAutoHide":false}` |
| 2 | Geometry matches the native Dock | PASS after fixes; deltas below; material differs (see gaps) |
| 3 | Hover label with another app frontmost, no key focus | PASS: label shown with Finder, Safari and Calculator frontmost; FocusDock never frontmost |
| 4 | Clicks on the transparent canvas pass through | PASS: click at (60, 903) inside the panel bounds (x -24..1495) activated Finder (desktop) over Calculator |
| 5 | Running tile activates, non-running tile launches with bounce | PASS after a crash fix: Calculator launched and frontmost within 0.4 s, one bounce; Calculator and Finder tiles activate their running apps; Calculator quit afterwards |
| 6 | Right-click platter > Quit FocusDock | PASS: getter `false`, state file deleted, watchdog exited (normal `quit app` also PASS) |
| 7 | `kill -9` of the main process | PASS: watchdog restored autohide `false` 0.02 s after the kill, deleted the file and exited |
| 8 | Final state | PASS: FocusDock and watchdog not running, getter `false`, `defaults read com.apple.dock autohide` = 0, no state file, Calculator not running |

## Geometry deltas (FocusDock minus native, pt, tilesize 75)

Compared against [native_before.png](e2e-phase1/native_before.png) with [focusdock_strip.png](e2e-phase1/focusdock_strip.png); FocusDock has no Trash or second divider (v1 non-goal), so its platter is 115 pt narrower and every x is compared relative to the Finder tile.

| Feature | Native | FocusDock | Delta |
|---|---|---|---|
| Platter top / bottom edge (from screen bottom) | 100 / 5 | 100 / 4.5 to 5 | 0 / <= 0.5 |
| Icon art top..bottom (crop y) | 22.0..82.5 | 22.0..82.5 | 0 |
| Icon art width (Finder) | 60.5 | 61.0 | +0.5 (1 px) |
| Tile pitch (7 dots) | 79 | 79 | 0 |
| Dot diameter / centre y | 4 / 94.0 | 4 / 94.0 | 0 / 0 |
| Last pinned dot to first running dot | 115 | 115 (was 114) | 0 after fix |
| Divider line x from Safari dot | 58.5 | 59.0 (was 57.5) | +0.5 after fix |
| Divider length / thickness | 71 / 1 | 71 / 1 | 0 |
| Corner radius | 30 | 30 | visual overlay match ([left_end_native_vs_focusdock.png](e2e-phase1/left_end_native_vs_focusdock.png)) |
| Label body height / gap above platter | 23 / 10.75 | 23 / 11 | 0 / +0.25 |
| Label width "Finder" / text ink width | 66 / 39.4 | 65 / 39.5 | -1 / +0.1 |
| Label tail tip above platter | 3 | 3.5 | +0.5 |
| Label fill (dark) | rgb(34,34,36) | rgb(36,36,36) | +2 |
| Bounce apex / rise / hold / fall | 20 / unobserved / 0.1 s / 0.30 s | 20 / 0.27 s / 0.15 s / 0.27 s | 0 / - / +1 frame / -2 frames |

Colours (L confidence, same wallpaper): running dot native rgb(138,162,193), FocusDock rgb(149,161,176); divider native rgb(79,105,130), FocusDock rgb(84,100,117).
The native colours are bluer because the Dock blends them with the glass (vibrancy).

## Bugs found and fixed in this run

1. Crash on the first launch click: SIGSEGV in `-[NSRunningApplication removeObserver:forKeyPath:]` because the KVO observation outlived the `NSRunningApplication` it observed. The watchdog restored the native Dock during that real crash. Fix: keep the app alive with its observation and invalidate before release (`Workspace.swift`).
2. Window level was 3 (floating), not 20: setting `isFloatingPanel` after `level` resets it. Fix: set the level after `isFloatingPanel` (`DockPanel.swift`); `CGWindowListCopyWindowInfo` now reports layer 20.
3. Divider slot was 35 pt (phase0 AX value); on-screen dots show 36 pt, and the line sits 1 pt right of the slot centre. Fixed in `DockMetrics`.
4. Platter had no specular rim: content drawn inside a glass container is blended as vibrant, so the rim is drawn outside it. Top rim now lum 91 vs native 94.
5. A finished launch snapped the icon to rest mid-air; it now lands the current bounce (`DockMetrics.bounceTimeToRest`), as the Dock does.
6. Label tail was a straight triangle; it now has concave flanks and a rounded tip like the native cartouche.

## Known gaps (not fixed)

- Material: public `.glassEffect(.regular)` is a heavier frost than the Dock's private `GlassMaterialProvider.Configuration.dock`; the native platter shows wallpaper texture, ours is a smooth blur. `.clear`, `NSGlassEffectView`, `appearsActive = true` and reporting the panel as key all rendered identically, so this stays a documented gap of the public API.
- The native Dock sliding up at the bottom edge: fixed, see below.
- Running-only app order follows `NSWorkspace.runningApplications`; two apps (Claude, Discord) are in the opposite order to the native Dock.
- Once, early in the run, a second, stale label for the next tile stayed visible next to the hovered one; not reproducible in 3 fresh launches plus tile-to-tile moves and glides. Watch for it.
- Light appearance, shadow and the bounce rise and repeat period are still unmeasured (`shortcut:` comments in `DockMetrics.swift`).

## Evidence files

- `native_before.png`, `native_after_restore.png`: native Dock before launch and after the final quit.
- `focusdock_strip.png`: FocusDock with the final build.
- `left_end_native_vs_focusdock.png`: 2x zoom of the left end, native on top.
- `focusdock_hover_label.png`: the Finder label (final tail shape).
- `bounce_frames.png`: 10 frames of the Calculator launch bounce (60 fps capture).
- `edge_no_reveal_after_priming.png`: cursor held at the bottom edge after FocusDock primed a fresh Dock itself.

## Dock pop-up fix (approved by the user, 2026-10-28)

Problem: the autohidden native Dock slid up over FocusDock when the cursor touched the bottom screen edge.
Fix: while FocusDock runs, `com.apple.dock autohide-delay` is 1000 (float). The original value is recorded in the state file next to autohide (nil when absent), with the same never-overwrite rule, and restored on quit and by the watchdog (the key is deleted if it was absent).
Baseline before the run: `autohide-delay` absent, `autohide` 0.

Does the running Dock pick up a changed delay? No.
With the pref at 1000 and autohide toggled on by `CoreDockSetAutoHideEnabled`, a cursor at (735, 955.5) for 2 s still revealed the native Dock ([edge_native_reveals_before_restart.png](e2e-phase1/edge_native_reveals_before_restart.png)).
This matches the teardown: the Dock reads `autohide-delay` only in an init path.
`CoreDockSetAutoHideEnabled(true)` does persist `autohide = 1`, so a restarted Dock comes back hidden.
I restarted the Dock once (`killall Dock`) with the pref at 1000; the same edge test then showed no reveal ([edge_no_reveal_after_restart.png](e2e-phase1/edge_no_reveal_after_restart.png)).
That one restart was manual; FocusDock now does it at launch (see below).

Re-run checks:

| Check | Result |
|---|---|
| 1 Native Dock hides; pref written | PASS: getter `true`, `autohide-delay` 1000 while running |
| Edge reveal while running | PASS after the one restart (twice: with the pref first applied, and on a later launch) |
| 4 Pass-through click on the transparent canvas | PASS: (60, 903) activated Finder over the frontmost app |
| 6 Right-click > Quit FocusDock | PASS via the menu with keyboard selection (Down, Return): getter `false`, `autohide` 0, `autohide-delay` absent again, no state file, watchdog exited. Synthetic left clicks on the menu item did not select it 3 times in this session (they did in the first run); a real-mouse check is still owed |
| 7 `kill -9` | PASS: watchdog restored autohide 0.11 s after the kill, deleted `autohide-delay`, removed the file and exited |
| Final state | FocusDock and watchdog not running, `autohide` 0, `autohide-delay` absent (its original), no state file, Calculator not running |

## Automatic Dock priming (approved by the user, 2026-10-28)

At launch FocusDock records the originals, writes the delay, and then decides with `DockPriming.decide` (pure, in FocusDockCore, unit-tested):
- the running Dock (PID and `sysctl` start time) equals `primed-dock.json`, or started after the delay was written: primed, hide now;
- otherwise: send it SIGTERM once and poll every 100 ms, up to 5 s, for the relaunched Dock;
- no Dock within 5 s: restore the originals, log, leave the Dock visible.
Autohide is enabled only after the primed Dock is recorded. Quit and the watchdog restore as before and keep `primed-dock.json`.
Deviation from the proposed design: a Dock whose start time is after the delay write also counts as primed, so a Dock that launchd is relaunching anyway (or that FocusDock just restarted) is accepted without a second restart.
The start time guards against PID reuse: a reused PID with a different start time is restarted.

Run (baseline: `autohide` 0, `autohide-delay` absent, no state files):

| Step | Result |
|---|---|
| `killall Dock` once by hand to simulate a fresh login Dock (PID 44466) | done |
| Launch FocusDock | PASS: one log line "restarting the Dock (pid 44466)", Dock PID 44466 -> 44522 within 0.5 s and no further change over 6 s; record `{"pid":44522,"startTime":1793162604.377513}`; `autohide` 1, delay 1000 |
| Edge, cursor at (735, 955.5) for 2.5 s | PASS: only FocusDock at level 20, no native Dock window ([edge_no_reveal_after_priming.png](e2e-phase1/edge_no_reveal_after_priming.png)) |
| Quit (AppleScript `quit`) | PASS: `autohide` 0, `autohide-delay` absent, `native-dock.json` gone, watchdog exited, `primed-dock.json` kept |
| Relaunch | PASS: no restart log, Dock PID still 44522; edge test again shows no reveal |
| `kill -9` the main process | PASS: watchdog restored `autohide` 0, deleted `autohide-delay`, removed `native-dock.json`, exited |
| Final state | FocusDock and watchdog not running, getter `false`, `autohide` 0, `autohide-delay` absent, only `primed-dock.json` (`{"pid":44522,...}`) remains |

Remaining limitation: the primed Dock keeps 1000 in memory after FocusDock quits.
That is harmless while autohide is off, but if the user turns autohide on themselves before the next Dock restart, their Dock will not reveal at the edge until it restarts.
