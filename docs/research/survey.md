# Reuse survey: AI-native focus dock (Swift, macOS 26/27) - 2026-10-28

Evidence tags: [read] = I read source/docs; [search] = search snippet only; [prior] = my background knowledge, not verified today.
Thariq's dock source (AeroSpace.swift, Chrome.swift, ...) is NOT public: github.com/thariqs has 39 repos, none is the dock (nearest: ai-newtab). So no fork-the-original option.

## 1. What is "jev"
RESOLVED. Jev = TypeSafe AI's "System One" model (early access 2026-09-15), a typed-decision model, not a chat model [search+read docs].
- Input: state (text/JSON) + typed questions. Output: Choice (pick one + probabilities + confidence), Score (ordered rubric), Noul (P(yes) 0-1). Vendor claims 70-500 ms, ~$0.042/M input tokens (vendor figures, unverified).
- API: POST https://api.typesafe.ai/v1/systemone, Bearer TYPESAFE_API_KEY, model "jev-latest" (currently jev-1.13.0) [read docs.typesafe.ai/introduction/quickstart].
- SDKs: official Python + TS (MIT, typesafe-ai/typesafe-sdk-*). No Swift SDK; plain URLSession POST is enough. Docs do not state text-only; treat as text-only (awesome list says hosted model is text-only).
- Offline option: ollaya-dev/ollaya (https://github.com/ollaya-dev/ollaya) (Apache-2.0, pushed 2026-10-26) serves open decision models behind a Jev-compatible /v1/systemone; the TS/Python SDK works with base URL swap. Gives a local fallback with the same wire format.
- Fit: perfect for (a) "is this notification urgent / needs answer by X" (Choice+Score), (b) "which mode does this activity belong to" (Choice over mode ids). Pick: call Jev over HTTP from Swift; keep the question schema in config.
- Caveat: awesome-jev lists warn about bulk-submitted, unproven repos; I only trusted typesafe.ai docs/org repos.

## 2. Swift dock replacements / panels
All fresh repos, small. Pick = write our own thin panel, copy the pattern from OpenDock; borrow window-AX code from DockDoor only if GPL is OK.
- ejbills/DockDoor - https://github.com/ejbills/DockDoor - GPL-3.0, 6.4k stars, last push 2026-10-27. Not a dock replacement (window previews/alt-tab overlay on the real Dock), but best reference for AX window enumeration (`_AXUIElementGetWindow`, borrowed from AltTab) [read].
- josejuanqm/docky - https://github.com/josejuanqm/docky - GPL-3.0, 1.4k stars, push 2026-10-27, ~58k LOC Swift. Full Dock replacement. Hides native Dock by writing com.apple.dock prefs (autohide, autohide-delay, tilesize...) with a separate watchdog helper process that restores prefs if the app dies; uses private SkyLight/CGS for space reservation [read]. Best reference for "hide native Dock safely", but GPL = can't copy into a non-GPL app.
- Ripcu/OpenDock - https://github.com/Ripcu/OpenDock - MIT, 1 star, push 2026-10-05, ~6.4k LOC. DockPanel: NSPanel subclass, [.borderless,.nonactivatingPanel], level .floating, collectionBehavior [.canJoinAllSpaces,.stationary,.ignoresCycle], NSHostingView SwiftUI content, anchored bottom-centre; icons via NSWorkspace.shared.icon(forFile:), running apps via NSRunningApplication; hides native Dock with `defaults write com.apple.dock autohide true` + autohide-delay 1000, saving and restoring originals [read]. Best license + size fit. Tiny community, so treat as a pattern, not a dependency.
- Others seen (not read): cxrobx/frosty (MIT), kosmodock (Apache-2.0), ai-dock (MIT), Wharf (GPL fork of Docky), tungsten-edge (GPL, per-window taskbar).
- Reuse verdict: no dependency worth taking. Net-new ~300 lines: NSPanel + SwiftUI HStack, NSWorkspace for icons/running state/launch, `defaults` autohide toggle with restore-on-exit (copy Docky's watchdog idea). Justification: every candidate is either GPL, a full dock with features we don't want, or a 1-star MIT repo.
- Note: dockutil (Apache-2.0, 1.6k stars) only edits the real Dock's items; not needed.

## 3. AeroSpace
- nikitabobko/AeroSpace - https://github.com/nikitabobko/AeroSpace - MIT, 23.6k stars, last commit 2026-10-01, latest tag v0.21.3-Beta [read]. Still labelled Beta; config has `config-version` (currently 2) as the breaking-change mechanism.
- Drive via CLI (talks to the running server over a socket): `aerospace workspace <name>`, `list-workspaces --all|--focused --json`, `list-windows --all|--workspace X --json --format`, `move-node-to-workspace --window-id N <ws>`, `focus --window-id N`, `list-apps`, `layout`, `reload-config` [read docs].
- New `aerospace subscribe [--all] <event>...` streams JSON lines: focus-changed, focused-workspace-changed, focused-monitor-changed, mode-changed, window-detected (windowId, workspace, appBundleId, appName), binding-triggered; sends initial state on connect [read docs]. This is the live-state feed for the dock (no polling). aerospace-iconz (MIT, https://github.com/ankondeadlarx/aerospace-iconz) shows the exact Swift pattern: spawn `aerospace subscribe` via Process, reduce events, kill children on exit. Also fz68/ribbon (MIT).
- Mapping: one AeroSpace workspace per mode (W, B, S). Put app->workspace routing in `on-window-detected` rules by bundle id (Chrome PWA shims have own bundle ids, see 4). Switching mode = `aerospace workspace B`. Hidden workspaces park windows in a bottom-corner pixel; with our dock as an NSPanel this is fine (AeroSpace guide recommends Dock bottom+autohide, consistent with hiding native Dock).
- Stability: CLI surface is documented man-page style and moving slowly, but Beta. Pin a version, wrap all calls in one `AeroSpaceClient`, use --json everywhere (iconz has a CLIParsing layer for the same reason). Config edits by an "agent" = write TOML + `reload-config`.
- Pick: AeroSpace as-is, CLI + subscribe. Do not reimplement tiling/workspaces. Alt (no tiling dependency): AX hide/minimize by bundle id per mode, but that re-invents AeroSpace badly.

## 4. Chrome control (per-mode tabs / web apps)
Thariq's Chrome.swift/TabPrompt.swift are not public; inference below is mine [prior].
- Likely Chrome.swift = AppleScript/JXA: enumerate windows+tabs (title, URL), activate a tab, open URL in a window; TabPrompt = an LLM prompt/picker for "which tab". Peek.swift probably = hover preview of windows/tabs.
- Option A, AppleScript/JXA (`osascript`): built in, no install, needs Automation permission prompt. Lists windows/tabs/URLs, `set active tab index`, `open location`. "Execute javascript" is off unless View > Developer > Allow JavaScript from Apple Events [search: chromium.org/developers/applescript]. Slow-ish but robust. Tab-group objects: UNVERIFIED in dictionary, check `sdef /Applications/Google\ Chrome.app`.
- Option B, CDP: Chrome 136+ ignores --remote-debugging-port on the default profile; needs a non-default --user-data-dir [read: developer.chrome.com/blog/remote-debugging-port]. Means a separate, logged-out profile. Wrong for the user's real logged-in Chrome. A chrome://inspect toggle exposes a WebSocket but not /json discovery (one user report, trycua/cua#2916) - flaky.
- Option C, extension + Native Messaging: the only way to get tab events (onActivated, titles, groups) live from the real profile; costs an extension + native host. Chromium itself recommends this over Apple Events JS.
- Option D, pinned web apps: Chrome "Install as app" creates a .app shim in ~/Applications/Chrome Apps.localized with its own bundle id; it appears as a normal running app (NSWorkspace icon, AeroSpace app-bundle-id rules, dock globe badge is just our overlay). Alternative `open -na "Google Chrome" --args --app=URL`. [prior]
- Pick: D for the pinned web apps (zero code, AeroSpace-friendly) + A for tab listing/switching and URL read (classification). Add C only if live tab events prove necessary. Skip B.

## 5. Notifications (macOS 26/27)
- Read: (a) usernoted SQLite at ~/Library/Group Containers/group.com.apple.usernoted/db2/db, TCC-gated by Full Disk Access since Sequoia, unsupported store, may break on OS updates; copy before reading [read: tacogips/apple-gateway design-notifications.md; search: 9to5mac/objective-see]. Poll/watch the WAL; contains title/body/bundle id. Reference readers: AceroM/dotfiles hammerspoon notifdb.py, gift-is-coding/macos-notification-reader (tiny, no license). Apple patched notification-redaction CVEs in 26.3 (CVE-2026-20603), so re-test on 27.
  (b) Accessibility observation of Notification Center banners (AXObserver on com.apple.notificationcenterui): works with Accessibility permission only, but fragile across OS UI changes and misses notifications that never show a banner; apple-gateway explicitly rejected it as too fragile. UNVERIFIED on 27.
  (c) Slack direct: Slack API (Socket Mode / Events with a user token, or `dnd.*`), needs workspace app approval; gives full message text and, notably, `dnd.setSnooze` can truly hold Slack pings [prior]. Per-service integrations beat scraping where the user controls the workspace.
- Hold/suppress without SIP changes: you cannot cancel another app's notification from outside. What works: (1) activate a Focus mode whose allow-list excludes the distracting apps - toggle with Shortcuts "Set Focus" (`shortcuts run`; arodik/macos-focus-mode npm uses exactly this; legnoh/focus-cli MIT reads state; eugenehp/macos-focus uses private API, avoid); the Focus allow-lists must be set once by hand in System Settings. (2) Focus Filters (SetFocusFilterIntent) only configure YOUR app. (3) INFocusStatus only tells your app whether the user is in Focus. (4) Held notifications then land in Notification Center / usernoted db, so "held list + AI classify + popover" = Focus mode hides banners, we read the db (FDA) and re-surface via our own panel. Messages also hidden by Focus remain readable in the db [prior; test on 27].
- Pick: Focus-mode-per-dock-mode (Shortcuts) for suppression + usernoted db read for content + Jev classify. Accept FDA grant and that the db is unsupported; wrap reader behind a protocol so Slack-API or AX can replace it.

## 6. Activity classification
- Signals: NSWorkspace frontmost app + didActivateApplicationNotification (bundle id), AX kAXFocusedWindow title (needs Accessibility), browser URL via Chrome/Safari AppleScript, optional ScreenCaptureKit screenshot -> VLM. Start with app+title+URL as text and feed Jev Choice over mode ids; screenshots only if text is ambiguous (Jev is text-only).
- ActivityWatch (https://github.com/ActivityWatch/activitywatch) - MPL-2.0, 19.4k stars, push 2026-10-26; aw-watcher-window (MPL-2.0, push 2026-10-19) and aw-watcher-web exist; Python/Rust, local REST server on :5600. Reuse option: run aw-server + watchers and read events via REST, but adds a heavy Python/Rust stack and a second permission surface. For a native Swift app, ~60 lines of NSWorkspace+AX is simpler; borrow ActivityWatch's event model (app/title/url + heartbeat merging) only.
- bharatrameshwar/commonplace (MIT, 19 stars, push 2026-09-25): same idea in Python (5 s capture, Ollama classify) - reference for sampling cadence, not a dependency.
- Pick: native NSWorkspace+AX+AppleScript URL sampler -> Jev Choice (cached by app+title hash). Keep ActivityWatch as an optional export, not a dependency.

## 7. Friction/countdown prior art [prior, UX only]
- one sec (iOS/macOS): intercepts opening a distracting app, forces a breathing pause, then asks "continue?"; the delay can escalate with repeated opens.
- Opal / ScreenZen / Freedom: scheduled blocks plus a timed "break glass" with limited unlocks per day.
- Pattern to copy: a visible exit timer per mode (`exitDelaySeconds`), one "Stay" action that shortens/extends the wait per press, and a deterministic rule in code (Jev only classifies, never decides to block).

## Overall plan (what to build vs reuse)
Reuse: AeroSpace (CLI+subscribe), Jev API (or Ollaya local), Focus via Shortcuts, Chrome PWA shims + AppleScript, OpenDock panel pattern, aerospace-iconz subscribe pattern (MIT). Net-new: DockView/Model/Config/classifier glue, notification db reader, countdown UX.
UNRESOLVED / needs a spike on this macOS 27 machine: usernoted db path + FDA behaviour, Chrome tab-group AppleScript support, whether NC AX observation still works.
