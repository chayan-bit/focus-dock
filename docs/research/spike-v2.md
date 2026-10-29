# Phase 4 spike results (S1-S13, macOS 27.0 / 26A428, Apple Silicon)

Status: final for this machine after runs F-I (2026-10-29); every precondition the spike can use is met, and only S4 (full status area), S9 (bar auto-hide off) and S11 (needs a second Shortcut import) stay open.
Run E had 4 Desktops, Accessibility, notifications and the imported Shortcut but no Screen Recording; runs F-I had Screen Recording too.
All screen-recording tests ran with the window tool that parks windows off-screen stopped, and it was restarted and checked after each run.
Run A (2026-10-28) ran everything that needs no grant; run B re-checked every precondition from inside the spike app, found none of the user steps done yet, and changed nothing on the system.
Harness: [`Spikes/`](../../Spikes/) is a separate SwiftPM package, never linked into `FocusDock` or `FocusDockCore`.
`FocusDockSpike.app` holds only a C loader that never changes, so its ad-hoc signature and TCC grants survive rebuilds; all test code is in `libSpikeKit.dylib`, loaded at runtime.
Tests run through LaunchServices (`Spikes/run.sh <test> <dir>`), and the harness confirms the TCC responsible process is the spike app itself.
Raw results: [`spike-v2/results-a.jsonl`](spike-v2/results-a.jsonl) (run A), [`spike-v2/results-d.jsonl`](spike-v2/results-d.jsonl) (run D), [`spike-v2/results-e.jsonl`](spike-v2/results-e.jsonl) (run E), [`spike-v2/results-f.jsonl`](spike-v2/results-f.jsonl) (runs F-I, plus the spring fits), per-frame series in [`spike-v2/s6-fit-input/`](spike-v2/s6-fit-input/).
Harness lesson (run D): tests that wait by nesting the run loop must not run inside a GCD main-queue block, because the main queue does not drain re-entrantly and AppKit, UserNotifications and ScreenCaptureKit callbacks stall; the harness now schedules with `CFRunLoopPerformBlock` and waits with `nextEventMatchingMask` + `sendEvent`, which also delivers Carbon hotkey events.
The same rule applies to FocusDock: any synchronous wait on the main thread must pump events, or Carbon hotkeys and notification callbacks are lost until it returns.
Every state change a test makes is pushed onto a restore stack that runs before the result is written, also on timeout.

## Summary

| Test | Status | One-line result |
|---|---|---|
| S1 bridged move | PASS | The bridged op moved a TextEdit window to another Desktop and back from our unentitled process in 13 ms, without switching Space |
| S2 animated DockSwipe | PASS | The 27 format switches at every velocity; velocity sets the slide length, from 0.53 s down to one frame at 9999; the legacy format is ignored |
| S3 universal-owner gate | PASS | Foreign `SLSSetWindowAlpha` returns 0 (success) and silently does nothing |
| S4 status item Cmd-drag | BLOCKED (environment) | On 27 a status item has no window of its own; on a full bar new items sit hidden under the notch, so there is nothing to drag |
| S5 banner AX tree | PASS | Banner is `AXGroup`/`AXNotificationCenterBanner`; its custom action was performed via AX and our delegate received it |
| S6 system springs | PASS (60 fps) | Slide response 0.52 s, damping fraction 0.91; Mission Control exit 0.28 s, 0.99; magnification in about 0.12 s, 0.75 |
| S7 AX setFrame and proxy seam | MEASURED | AX resize p95 12 ms on a heavy app, move p95 1.1 ms; the spec's proxy shows a double image, covering the destination removes it |
| S8 Carbon hotkeys under Secure Input | PASS | F18 Carbon hotkey fired with Secure Input on (synthetic keystroke) |
| S9 status items with the bar auto-hidden | BLOCKED-USER-SETTING | Control passed with the bar visible: bar-window crop at the AX frame shows the item, `AXPress` fires it |
| S10 accent colour coverage | PARTIAL | Active AppKit windows recolour live with no relaunch; background windows show no accent pixels either way; restore exact |
| S11 Focus name as Shortcut input | FAIL (as built) | Both branches stop with "Please choose a value for each parameter in this action"; Focus never changed |
| S12 off-Space thumbnails | FAIL (foreign windows) | Our own window on another Space captures live; another app's window there captures as solid black |
| S13 usernoted DB | PASS | Read-only copy of `db`, `db-wal`, `db-shm` opened; schema unchanged from the documented `record` table |

## S1 bridged MoveWindowsToManagedSpace

- Status: PASS (run E, 4 Desktops, the window tool that parks windows stopped for the run and restarted after).
- `SLSBridgedMoveWindowsToManagedSpaceOperation` exists; methods: `initWithWindows:spaceID:`, `windows`, `spaceID`, `invokeFallback`, `initWithCoder:`, `encodeWithCoder:`.
- `SLSPerformAsynchronousBridgedWindowManagementOperation` resolves through the in-memory symtab (same mangled name as yabai and `tools/rea/probe.m`).
- Call used: `[[cls alloc] initWithWindows:@[@(wid)] spaceID:sid]` then `SLSPerformAsynchronousBridgedWindowManagementOperation(op)` (yabai `space_manager.c`).
- Each row moves the window from the current Desktop to the next one, polls `SLSCopySpacesForWindows(cid, 0x7, wids)` until it changes, then moves it back and reads it back again.

| Window | Call | Moved | Latency | On screen after | Active Space unchanged | Restored |
|---|---|---|---|---|---|---|
| Own scratch window | bridged op | yes | 13.3 ms | no | yes | yes |
| Own scratch window | `SLSMoveWindowsToManagedSpace` | yes | 1.1 ms | no | yes | yes |
| TextEdit scratch window (other process) | bridged op | yes | 12.7 ms | no | yes | yes |
| TextEdit scratch window (other process) | `SLSMoveWindowsToManagedSpace` | no | - | yes | yes | yes (never moved) |

- Reading: on 27 the bridged op moves another app's window from a process with no entitlements and no SIP change; the direct call is still gated to our own windows and fails silently, like S3.
- The bridged op is asynchronous: the call returns at once and the Space change shows up about 13 ms later, so callers must poll or wait for the window-moved notification before acting on the new state.
- The moved window leaves the screen without switching the active Space, which is what routing rules need.
- Spec changes:
  - 3.1 table: replace "UNKNOWN on 27, spike S1" with "works on 27 for any window, async, about 13 ms (spike S1)".
  - 5.1: route other apps' windows with the bridged op; use `SLSMoveWindowsToManagedSpace` only for FocusDock's own windows, and verify every move by reading `SLSCopySpacesForWindows` back.
  - 12 (risks): delete "The bridged move may be entitlement-gated on 27"; replace it with "the bridged op is private and may change in a point release; the read-back detects that, and AeroSpace stays the fallback".

## S2 animated DockSwipe

- Status: PASS (run H for velocities and chains at velocity 4, run I for chains at velocity 9999).
- Format: on 27 the Dock ignores the DockControl event as SHELL-SPEC 3.1 describes it (fields 55, 110, 123, 124, 129, 132 only); the legacy-format probe did not switch in any run.
- The format that works is InstantSpaceSwitcher's (MIT, 2026): an IOHID fluid-gesture payload (event type 23, flavor 3, 16.16 fixed progress and velocity) appended to the serialized event under tag 4205, plus a companion `kCGSEventGesture` (55 = 29) event after each DockControl event.
- On 27 "next Space" is a negative sign with natural scrolling on, flipped again with it off, and only Ended carries velocity.
- Port: [`Spikes/Sources/SpikeKit/DockSwipe.m`](../../Spikes/Sources/SpikeKit/DockSwipe.m).
- Gesture: Began, Changed x10 (progress step 0.03 at 120 Hz, about 100 ms of events), Ended at the given velocity, out to the next Desktop and back, with a marker window tracked per frame.

| Ended velocity | Ended to active Space change (out / back) | Ended to marker at rest (back) |
|---|---|---|
| 0.25 | 565 / 565 ms | 533 ms |
| 1 | 541 / 545 ms | 535 ms |
| 4 | 524 / 530 ms | 498 ms |
| 16 | 226 / 219 ms | 218 ms |
| 9999 | 21 / 21 ms | 16 ms (one frame) |

- Every run switched out and back and the harness returned to the starting Desktop.
- The active-Space id changes when the slide is almost over, not when it starts, so FocusDock must not treat that notification as "slide started".
- Velocity up to about 4 gives the full system slide; 16 shortens it; 9999 switches in one frame, with no slide and no SIP.
- Chained 3-Desktop jump (three gestures posted back to back), time from first event to the target Desktop being active:
  - velocity 4, no gap: 856 ms; velocity 4, 0.25 s gaps: 1333 ms;
  - velocity 9999, no gap: 329 ms, almost all of it the 3 x 10 Changed events; velocity 9999, 0.25 s gaps: 1059 ms.
- The Dock queues gestures posted during a slide instead of dropping them: three slides at velocity 4 took 856 ms, not 3 x 530 ms.
- Harness note: a borderless marker window never reached the screen on 27 (zero marker pixels in every frame of run F), so the marker is a titled window; FocusDock's own overlay windows should be checked for the same.

## S3 universal-owner gate

- Status: PASS (the gate is measured).
- Call: `SLSSetWindowAlpha(SLSMainConnectionID(), wid, 0.5)`, read back with `SLSGetWindowAlpha`, then restored.
- Own window: CGError 0, alpha read back 0.5, restored to 1.0.
- Window of a second spike process (same signer, different connection): CGError 0, alpha read back 1.0.
- Window of a throwaway TextEdit instance on a scratch file: CGError 0, alpha read back 1.0.
- `SLSGetWindowOwner` confirms the foreign windows belong to other connections.
- No WindowServer, WindowManager or Dock log line mentions the refused call.
- Reading: the universal-owner gate holds on 27, and it fails silently: the CGError cannot detect it, only a read-back can.
- Spec change: 3.2 stays as written; add that any SPI mutation on a foreign window must be verified by read-back, because the server reports success.
- Pending: a Screen Recording capture to confirm nothing changes on screen either.

## S4 status item Cmd-drag

- Status: BLOCKED by the environment (run D, with Accessibility).
- Finding: our `NSStatusItem` buttons live in an `NSStatusBarWindow` whose `windowNumber` is 0, and `CGWindowListCopyWindowInfo` has no window for them.
- The whole status area is one full-width layer-24 window owned by MenuBarAgent; one more full-width layer-24 window belongs to WindowServer.
- The other windows at layers 23-25 belonged to third-party apps and were panel-sized, not item-sized.
- AX still lists our two items as children of our own `AXExtrasMenuBar`.
- Reading: on 27 status items are not per-item windows; Ice's model (one window per item, found by `CGSGetProcessMenuBarWindowList`) no longer describes the bar.
- Run D: the `NSStatusBarWindow` frame is a placeholder (both items reported the same frame), so the test reads real frames from our own `AXExtrasMenuBar` children.
- AX also gave both of our items the same frame, x 814, width 62, under the notch: the status area on the test machine is full, so new items are placed in the hidden overflow.
- The Cmd-drag (mouse down, 12 drags, mouse up, Command flag, posted at the HID tap) changed nothing and no `NSStatusItem Preferred Position` key was written; with hidden items this is not evidence either way.
- Settling it needs room in the status area, which means the user hiding or quitting some status items; the spike will not do that.
- Spec impact is small: FocusDock's own bar replaces Apple's, so dragging inside Apple's bar only matters for the S9 mirror, and there AX gives the item's real frame.
- Spec change (already certain): 5.4 "SCK image of each item window" must become "SCK capture of MenuBarAgent's bar window cropped to each item's AX frame", pending S9.

## S5 notification banner AX tree

- Status: PASS (run D).
- Planned run: post our own banner with a unique token and a custom action `FDS Act`, dump NotificationCenter's AX tree with every string that is not ours redacted to its length, climb from our text to the first ancestor with actions, perform `FDS Act` (or `AXPress`), and check our `UNUserNotificationCenterDelegate` received the response.
- PASS needs both: our banner found in the tree, and the action delivered back to us.
- Banner element: `AXGroup` with subrole `AXNotificationCenterBanner`, five levels under the NotificationCenter application, inside an `AXWindow`/`AXSystemDialog` and an `AXHostingView`.
- Its `AXDescription` is "app name, title, body" in one string; the title is also a child `AXStaticText`.
- Actions on the banner: `AXPress` plus custom actions; ours appears as `Name:FDS Act\nTarget:0x0\nSelector:(null)`.
- Performing that custom action delivered `fds.act` to our `UNUserNotificationCenterDelegate` with no visible UI, so FocusDock can fire a banner's action buttons through AX.
- Redacted tree: [`spike-v2/s5-ax-tree.json`](spike-v2/s5-ax-tree.json).
- Spec change: 5.6 can name the subrole `AXNotificationCenterBanner` as the banner locator, parse `AXDescription` (app, title, body), and match action buttons by the `Name:` prefix of custom actions.

## S6 system spring constants

- Status: PASS, at 60 fps (the built-in display reports `maximumFramesPerSecond` 60; the spec asked for 120 fps recordings).
- Fit: [`Spikes/fit_spring.py`](../../Spikes/fit_spring.py), a unit-mass damped spring with free start time, endpoints and initial velocity; `--selftest` recovers 0.350 s and 0.860 from noisy 60 Hz synthetic data.
- Space slide: from the S2 recordings (the "Move left/right a space" hotkeys are off, so the Ctrl+Arrow variant was skipped); marker left edge, return slide.
- Mission Control: `CoreDockSendNotification("com.apple.expose.awake")` and again to exit, marker window width.
- Magnification: top edge of one Dock icon in a one-pixel column at its centre under a posted cursor (Dock tile 75, large 85, so the travel is only 10 points).

| Segment | Samples | response (s) | dampingFraction | stiffness | damping | Settle to 1% (data) | RMS (% of travel) |
|---|---|---|---|---|---|---|---|
| Space slide, velocity 0.25 | 67 | 0.521 | 0.913 | 145.5 | 22.0 | 0.42 s | 0.41 |
| Space slide, velocity 1 | 70 | 0.516 | 0.916 | 148.5 | 22.3 | 0.40 s | 0.05 |
| Space slide, velocity 4 | 71 | 0.522 | 0.914 | 145.0 | 22.0 | 0.38 s | 0.05 |
| Space slide, velocity 16 | 75 | 0.304 | 0.884 | 427.9 | 36.6 | 0.22 s | 0.16 |
| Mission Control exit | 84 | 0.277 | 0.992 | 514.6 | 45.0 | 0.33 s | 0.28 |
| Mission Control enter | 73 | 0.098 | 2.159 | 4113 | 277 | 0.27 s | 0.90 |
| Magnification in | 71 | 0.119 | 0.753 | 2804 | 79.7 | 0.04 s | 1.07 |

- Stiffness and damping are for unit mass (CoreAnimation `mass = 1`); `response` and `dampingFraction` are the SwiftUI pair.
- The slide is one spring, not velocity-dependent, up to velocity 4: response 0.52 s, damping fraction 0.91, RMS under 0.5% of a 1187-point travel.
- Mission Control enter does not start from rest (fitted initial velocity about 9800 pt/s), so it reads as an overdamped ease-out of about 0.27 s; exit is close to critically damped.
- Magnification in is rough (10 points at 1-point resolution); magnification out could not be fitted, because the icon is back at rest within about 0.2 s and only three frames lie in between.
- Velocity 9999 gave no fit: the switch is one frame.

## S7 AX setFrame timing and proxy seam

- Status: MEASURED (run F).
- Heavy app: a TextEdit instance of our own on a 30000-line wrapped plain-text scratch file, so every resize relays out the whole document.

| Call (60 each) | p50 | p95 | max | Calls per second |
|---|---|---|---|---|
| `kAXSizeAttribute` | 2.46 ms | 11.98 ms | 18.62 ms | 202 |
| `kAXPositionAttribute` | 0.31 ms | 1.11 ms | 1.68 ms | 2903 |

- SCK delivered 20 screen frames during the 0.30 s resize loop, about one per display refresh.
- So the spec's "expected 15-40 fps" for per-frame `setFrame` is too pessimistic for the call cost: a move costs about 1 ms, and a resize fits a 60 Hz frame except at the tail.
- Not measured: whether the app's content keeps up with per-frame resizes; the call returning does not prove the window was redrawn.
- Proxy, as 5.2 is written (snapshot proxy at the old frame, one AX move, animate the proxy): 3 of the 6 frames in the first 100 ms show the real window already at its destination as well as the proxy, a visible double image.
- Proxy with the destination covered by an SCK snapshot of what is behind it until the proxy lands: 0 of 6 frames doubled.
- Both variants: 3 frames (about 50 ms) after the proxy lands still differ from the final image by more than 15% of the desktop-to-window contrast, before the cross-fade finishes.
- Design note: the double image happens because without SIP the real window cannot be hidden during the animation.

## S8 Carbon hotkeys under Secure Input

- Status: PASS (run D).
- `RegisterEventHotKey(kVK_F18, 0, ...)` returned 0; F18 posted at the HID tap fired the handler once with Secure Input off.
- With a frontmost helper holding `EnableSecureEventInput()` in a focused secure field (`CGSIsSecureEventInputSet` true, helper frontmost), the same F18 fired the handler once again.
- Secure Input was off again afterwards.
- Spec impact: keep 5.8 as written; the Carbon leader layer works under Secure Input.
- Planned run: register F18 with `RegisterEventHotKey`, post it once with Secure Input off and once while a frontmost spike helper holds `EnableSecureEventInput()` in a secure text field, which is what Terminal's Secure Keyboard Entry does; Terminal itself is not touched.
- `CGSIsSecureEventInputSet` is read before, during and after, so the run proves Secure Input was really on and is off again.
- Limit: the keystroke is synthetic (posted at the HID tap); a physical key press is not covered.

## S9 status items while Apple's bar is auto-hidden

- Status: BLOCKED-USER-SETTING for the auto-hidden case; the visible-bar control passed (run F).
- `CGSGetMenuBarAutohideEnabled` returns false and `_HIHideMenuBar` is unset, so the bar is not auto-hidden on the desktop; the spike does not change the setting.
- Control: SCK capture of MenuBarAgent's full-width layer-24 bar window, cropped to our item's frame from our own `AXExtrasMenuBar` (`{{885, 4.5}, {70, 24}}`), shows exactly our item ([`spike-v2/s9-item-visible-control.png`](spike-v2/s9-item-visible-control.png)).
- `AXPress` on the item returned 0 and its action fired in our process.
- SCK lists the bar window as not on screen, yet captures it; whether that still holds while the bar is auto-hidden is the open part.

## S10 accent colour coverage

- Status: PARTIAL (run F, second attempt; the first crashed in the harness before changing anything, fixed in `SelectTextViaAX`).
- Original state: `AppleAccentColor` and `AppleHighlightColor` unset; set `AppleAccentColor = 0` (red) via `CFPreferencesSetValue` in the any-application domain plus `AppleColorPreferencesChangedNotification` and `AppleAquaColorVariantChanged`; restored by deleting the key, read back as unset.

| Target | Pixels changed | Red pixels before / after | Restored vs before |
|---|---|---|---|
| Spike AppKit window (active) | 9.5% | 12 / 793 | identical |
| System Settings (Appearance page) | 7.9% | 28 / 60 | 6.3% differs |
| Finder window on `/Applications` | 0.4% | 4 / 4 | identical |
| TextEdit with text selected | 0% | 0 / 0 | identical |
| Font Book | 0% | 0 / 0 | identical |

- The active AppKit window recoloured every accent control (checkbox, default button, slider, segmented control, switch, selection) within 2.5 s, with no relaunch: [before](spike-v2/s10-spike-appkit-before.png), [after](spike-v2/s10-spike-appkit-after.png).
- TextEdit, Font Book and Finder were background windows during the captures; background AppKit windows draw selection and controls in grey, so 0% does not show whether they follow the change.
- System Settings changes because its own accent picker shows the value; its 6.3% after the restore is page state, not the accent (the key read back as unset).
- Only the spike's captures are published; the others can show account, file or folder names.

## S11 Focus name as Shortcut input

- Status: FAIL as built (run E); the question "can a Focus be chosen by name through Shortcut Input" is not settled yet.
- [`Spikes/S11/make_shortcut.py`](../../Spikes/S11/make_shortcut.py) writes `FocusDock Set Focus`: if input is `Off`, it turns off the current Focus, otherwise it runs Set Focus with the Focus parameter bound to Shortcut Input; it outputs the current Focus.
- `shortcuts sign --mode anyone` signs it without UI scripting; it rejects an input file without the `.shortcut` extension ("isn't in the correct format").
- Importing a signed Shortcut always shows an Add Shortcut sheet that the user must confirm.
- Run: `shortcuts run "FocusDock Set Focus"` with input `Do Not Disturb`, then `Off`, each once through `-i <file>` and once through stdin.
- All four runs exited 1 within 0.7 s with "Error: Please choose a value for each parameter in this action.", wrote no output, and left the Focus assertion store empty before and after.
- Two causes fit and this run cannot tell them apart:
  - `Off` branch: no Focus was on, so Get Current Focus returned nothing and Set Focus got an empty Focus parameter; that branch needs a guard whatever the answer.
  - Name branch: Set Focus does not coerce a text variable into its Focus parameter, or not in the serialized form the script writes.
- Settling it needs a second variant imported (one more user click): a Shortcut that only runs Set Focus with Focus bound to Shortcut Input and no `Off` branch, plus one built in the Shortcuts editor to compare its serialized parameter with ours.
- Spec change (5.7 Focus via Shortcut): until that variant passes, do not rely on passing a Focus name as input; plan for a generated Shortcut with one `If input is <name>` branch per Focus, each with the Focus chosen as a fixed value, and guard Turn Off with "if a Focus is on".

## S12 thumbnails of windows on other Spaces

- Status: FAIL for other apps' windows (run F).
- Method: switch to Desktop 2, open our clock window and a TextEdit scratch window there, return to Desktop 1, then capture each with `SCScreenshotManager` and `initWithDesktopIndependentWindow:`.
- Our clock window on the other Space: listed, not on screen, captured twice 1 s apart, and the two images differ (the clock ticked), so the capture is live ([1](spike-v2/s12-clock-other-space-1.png), [2](spike-v2/s12-clock-other-space-2.png)).
- TextEdit's window on the other Space: listed, not on screen, captured as a solid black image (mean luma 0, variance 0): [`spike-v2/s12-textedit-other-space.png`](spike-v2/s12-textedit-other-space.png).
- Control: the clock window on the current Space captured normally.
- One foreign app was tested; a second (for example a browser) would show whether black is universal for foreign windows.

## S13 usernoted DB

- Status: PASS for reading on 27.
- Path unchanged: `~/Library/Group Containers/group.com.apple.usernoted/db2/{db,db-wal,db-shm}`; the three files were copied with plain reads into a scratch directory and opened read-only with `sqlite3 -readonly`.
- Tables: `app`, `categories`, `dbinfo`, `delivered`, `displayed`, `record`, `requests`, `snoozed`.
- `record(rec_id, app_id, uuid, data, request_date, request_last_date, delivered_date, presented, style, snooze_fire_date)`, `data` a binary plist with `app`, `date`, `req` (`titl`, `body`, `iden`, `thre`, `dest`, `usda`, `intrp`), `srce`, `styl`, `uuid`.
- The WAL is live: it grew between two runs a minute apart, so watching `db-wal` for writes is a workable change signal.
- Not settled by this run: whether 27 still requires Full Disk Access for this path; keep Full Disk Access in onboarding until a clean-machine check.
- The copy was deleted after the schema read; no notification content is recorded here.

## Preconditions (checked from inside FocusDockSpike.app, runs B-I, 2026-10-29)

| Precondition | Needed by | State |
|---|---|---|
| 2+ user Desktops (live `SLSCopyManagedDisplaySpaces`) | S1, S2, S6 slide, S12 | present: 4 (run E) |
| Accessibility (`AXIsProcessTrusted`) | S2, S4, S5, S6 slide and magnification, S7, S8, S9, S10, S12 | granted (run D) |
| Screen Recording (`CGPreflightScreenCaptureAccess`) | S2, S6, S7, S9, S10, S12 | granted (run F; missing in run E, when SCK failed with `SCStreamErrorDomain` -3801) |
| Notification authorization | S5 | granted (run D) |
| `FocusDock Set Focus` Shortcut imported (`shortcuts list`) | S11 | present (run E) |
| Apple menu bar auto-hide | S9 | off (user setting, not changed) |
| "Move left/right a space" shortcuts | S6 Ctrl+Arrow variant only (optional) | off |

- Run C re-checked all of them live and found the same state: 1 Space, the spike listed under Accessibility but switched off, no Screen Recording entry, notifications not determined, no Shortcut.
- Run D showed the system prompts from inside the app and polled every 5 s for 10 minutes: Accessibility and notifications were granted; Screen Recording, the Shortcut import and the extra Desktops did not happen before the timeout.
- Run E re-checked live: Desktops went from 3 to 4 while the checks ran, and Screen Recording was still not granted to `FocusDockSpike.app`, even in a fresh launch.
- The window tool that parks windows off-screen is stopped only for the Space tests, and only once 2+ Desktops exist; its restart is on the restore stack.

## SHELL-SPEC changes from this spike

- 3.1 "Window to another Space": "works on 27 for any window, async, about 13 ms (spike S1)" instead of UNKNOWN.
- 3.1 "Spaces: switch with the native slide": the event is the 27 DockSwipe format (IOHID fluid-gesture payload under tag 4205 plus a companion 55 = 29 gesture event, ported from InstantSpaceSwitcher, MIT); fields 55 = 30 and 110 = 23 alone are ignored on 27.
- 3.1 "Status items" row and 5.4: "SCK capture of MenuBarAgent's bar window cropped to each item's AX frame, clicks via `AXPress`" instead of "SCK image of each item window"; status items have no window of their own on 27 (S4, S9 control).
- 3.1 "Accent colour": add that the change is live for active AppKit windows with no relaunch, and that the restore ledger must delete the key when it was unset.
- 3.1 "Overview" and "Cmd-Tab switcher", 5.5: live SCK thumbnails only for windows on the current Space and for FocusDock's own windows; other apps' windows on other Spaces capture black, so show the last frame captured while their Space was current, refreshed on every visit, marked stale.
- 3.2 "Jump to any Space instantly": no longer impossible; a DockSwipe with Ended velocity 9999 switches in one frame, and 3 Desktops take 329 ms (mostly event posting), so the cross-fade fallback is not needed.
- 3.2 "Hide the real window under an animation proxy" alternative: "cover the destination with an SCK snapshot of what is behind it until the proxy lands" instead of "accept about one frame of seam".
- 5.1 Switch: `workspace.switch` velocity 1 gives the system slide (0.54 s); `workspace.jump` becomes k chained gestures at velocity 9999 with no cap, or at the configured velocity when the user wants to see the slides; drop `maxChained` and the cross-fade fallback.
- 5.1 Switch: the active-Space change arrives near the end of the slide (about 520 ms at velocity 1), so surfaces that react to "Space changed" (bar, borders) must start from the gesture, not from that notification.
- 5.1 Move: route other apps' windows with the bridged op; `SLSMoveWindowsToManagedSpace` only for FocusDock's own windows; verify every move by reading `SLSCopySpacesForWindows` back (S1, S3: foreign SPI calls fail silently).
- 5.2: replace "an expected 15-40 fps with tearing" with the S7 numbers (AX resize p95 12 ms, move p95 1.1 ms on a heavy app); keep the proxy for resizes; per-frame AX position for pure moves is cheap enough to try, pending a visual check.
- 5.2 proxy sequence: before the AX move, cover the destination with a snapshot of what is behind it; after landing, hold the proxy until the destination matches it (at least 3 frames, about 50 ms, at 60 Hz) before the cross-fade.
- 5.6: name `AXNotificationCenterBanner` as the banner locator, parse `AXDescription` as "app, title, body", and fire action buttons by the `Name:` prefix of custom actions (S5).
- 5.7 Focus: do not rely on passing a Focus name as Shortcut input; generate one `If input is <name>` branch per Focus with a fixed Focus value, and guard Turn Off with "if a Focus is on" (S11, pending a second variant).
- 6 Motion: "fitted from 120 fps recordings" becomes "fitted from 60 fps recordings on the 60 Hz built-in panel"; the defaults block gains the fitted system values:
  - `workspace.switch` slide as recorded: spring response 0.52, damping 0.91 (for FocusDock surfaces that follow the slide);
  - `overview.open` / `overview.close`: response 0.28, damping 0.99 (Mission Control exit), enter as a 0.27 s ease-out;
  - `dock.magnify`: response 0.12, damping 0.75 (rough, 10-point travel).
- 11 Phase 4 list: S2 and S6 recordings are 60 fps on this machine.
- 12 Risks: delete "The bridged move may be entitlement-gated on 27"; add "the bridged op is private and may change in a point release; the read-back detects it, and AeroSpace stays the fallback".
- 12 Risks: "about one frame of seam" becomes "a double image unless the destination is covered, and about 3 frames of mismatch after landing on a heavy app (S7)".
- 12 Risks: add "other apps' windows on other Spaces cannot be captured live (S12)".
- Harness lesson for 4.1: any synchronous wait on the main thread must pump events (run D), and borderless overlay windows must be checked on 27, since the spike's borderless marker never reached the screen (run F).

## S14

- S14 (permission prompt tool wire trace and Windows poll latency) is reported separately in [spike-v2-s14.md](spike-v2-s14.md).
