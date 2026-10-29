# Fleet view and host agent - research (2026-10-28)

Input for SHELL-SPEC.md section 9 (spec v2).
User request: a terminal-style view of every SSH-connected machine with its status, plus an agent that can make changes on any of them, with a full native UI.
Hosts are named by generic role only; the repo is public.
Docs facts below were read from code.claude.com on 2026-10-28; UI facts about Zed, Cursor and Warp are from memory and not re-verified.

## 1. The fleet (resolved from the user's ssh config)

- The fleet is whatever `Host` stanzas the user's ssh config defines; FocusDock never opens key files.
- Only `ssh -G <alias>` is needed to resolve a host (HostName, User, ProxyJump, ProxyCommand); never parse the file or touch keys.
- Hosts are referred to by role below; the real aliases live only in the user's local `fleet.jsonc`, never in this repo.

| Role (example alias) | Class and rules |
| --- | --- |
| `cpu-box` | Own Linux box; default for private work, CPU-heavy builds and tests; jobs run under a memory cap (for example MemoryMax=12G, MemorySwapMax=0) and a bounded runtime; no extra confirmation. |
| `shared-gpu-a` | Windows, large workstation GPU, shared; first GPU choice; check reachability and `nvidia-smi` first; no confirmation. |
| `shared-gpu-b` | Linux, many cores, large datacenter GPU, shared, no sudo, reachable only from one private network; GPU use capped per job (`gpuMaxGB`); access has an end date. |
| `shared-gpu-c` | Shared Linux GPU host run by a third party; check site rules, occupancy, CUDA, bounded runtime. |
| `paid-gpu` | PAID cloud GPU instance, kept stopped when unused; every instance start and every GPU job needs fresh explicit confirmation; never infer approval. |
| `cloud-*` | Other cloud instances; some reach the box through a cloud-CLI ProxyCommand that exits when there is no external IP, so a stopped box fails fast without being started. Two instances can share a name stem, so key everything by alias, never by name similarity. |
| `hosted-studio` | Hosted notebook entry with keepalives; billing unknown, so it defaults to `paid`. |
| `local-vm` | Local Linux VM included from a VM tool's ssh config; not a remote machine. |

- Shared hosts (`shared-gpu-*`): touch only the user's own processes, never reboot or restart shared services.
- Proposal: a `fleet.jsonc` overlay beside the ssh config with per-alias `os`, `class` (own, shared, paid), `confirm` (none, per-start, per-job), `gpuMaxGB`, `pollSec`.
- Default for any alias not in the overlay and any cloud-generated name: `class: paid`, `confirm: per-job`, so an unknown box can never be started or loaded silently.

## 2. Collecting status natively

Decision: shell out to `/usr/bin/ssh` with a managed ControlMaster per host; do not link a Swift SSH library.

- Why OpenSSH: it is the only client that honours the user's real config (ProxyJump, cloud-CLI ProxyCommand, ssh-agent, Keychain, third-party agents, known_hosts policy).
- Citadel (MIT, v0.12.1, last commit Apr 2026, pre-1.0) depends on a fork of swift-nio-ssh, so it adds supply-chain risk and still lacks ProxyCommand.
- swift-nio-ssh (Apache-2.0, Apple, active Oct 2026) is transport only; we would rebuild config, agent and host-key handling.
- Revisit only if we need many hundreds of sessions or a sandboxed (App Store) build.

Mechanics:
- Launch with explicit flags so the user's config is untouched: `-o ControlMaster=auto -o ControlPath=<short path> -o ControlPersist=10m -o BatchMode=yes -o ConnectTimeout=4 -o ServerAliveInterval=15 -o ServerAliveCountMax=2`.
- Put sockets in `~/.local/state/focusdock/cm/%C`; the macOS unix socket path limit is 104 bytes, so keep the prefix short.
- One poll is one `ssh host '<script>'` that prints sentinel-delimited sections, so a warm poll costs one RTT, not one per metric.
- Linux script reads `/proc/loadavg`, `/proc/meminfo`, `df -P`, `nvidia-smi --query-gpu=index,name,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits`, `ps -u $USER` top 5 by CPU with elapsed time, `tmux ls`, `systemctl --user list-units --state=running`.
- Windows (`shared-gpu-a`): superseded by spike S14 (`spike-v2-s14.md`): CIM, WMI, `wmic` and `typeperf` are denied to an unelevated ssh logon, so one cmd-composed exec runs `nvidia-smi` from cmd plus a .NET-only `powershell -NoProfile -NonInteractive -EncodedCommand <b64>` for CPU, memory and disk.
- Detect OS once per host (`uname -s` succeeds, else `ver`) and cache it in the overlay; PowerShell start costs roughly 0.3 to 1 s, so poll Windows every 15 s or slower (measured about 1.3 s warm, 2.9 s cold in S14).
- Latency budget: UI paints the last sample instantly with an age badge; warm Linux poll under 500 ms on LAN, Windows under 1.5 s, cold connect under 4 s; hard-kill any poll at 6 s.
- Cadence: 5 s for the focused host, 15 to 30 s for visible cards, paused when the panel is hidden; cap 4 concurrent polls; jittered start so hosts do not align.
- States per host: `up`, `degraded` (RTT or sample age high), `unreachable` (timeout or no route), `off` (cloud instance stopped or ProxyCommand fails fast), `auth` (BatchMode failure).
- Unreachable handling: exponential backoff 5 s up to 120 s, one-line reason from ssh stderr, never a modal; hosts reachable only from one private network show `off network` when the Mac is elsewhere, not an error.
- Use `NWPathMonitor` to drop masters (`ssh -O exit`) and retry immediately when the network path changes.
- For hosts on an overlay network, its own status command (for example `tailscale status --json`) gives online state without an ssh attempt.
- Paid hosts: status for `paid-gpu` and the `cloud-*` hosts comes from the cloud CLI's read-only describe call plus a TCP probe; the poller must never start an instance, only a confirmed action may.

## 3. Prior art and what to copy

| Tool | Take |
| --- | --- |
| btop | Box layout, braille or block sparklines, per-core bars, `/` filter, theme tokens (FocusDock already imports Omarchy themes, which style btop). |
| Glances (`--browser`) | Multi-server browser with one colour-coded row per machine, alert thresholds. |
| Netdata | Per-node card with alert state, drill-down on click. |
| k9s and ctop | List plus detail, `:` command, `/` filter, `?` help overlay, single-key verbs (shell, logs, kill) shown in a footer. |
| Termius and Tabby | Host groups, quick connect, snippets, tabbed sessions, per-host colour tag. |
| Wave (Apache-2.0, 22k stars, v0.14.5) | Blocks in a tiled workspace, SSH connection manager, AI panel that reads terminal output and files, `wsh` CLI to drive the UI. |
| Warp | Command blocks (input and output as one selectable unit), agent mode with per-command approval, palette. |

Native SwiftUI panel spec:
- One monospace grid (SF Mono or the theme font), one row per host: state dot, alias, OS glyph, RTT, load, CPU bar, MEM bar, DISK bar, GPU util and mem, own-jobs count, tmux count, sample age.
- Badges: `shared`, `$ confirm` (paid), `win`; colours come from theme tokens, never hard-coded.
- Sparklines: 60 samples in a ring buffer drawn with `Canvas`; no charting dependency.
- Keys: `j/k` move, `Enter` open host detail, `/` filter, `:` command, `a` agent for host, `t` terminal for host, `1-9` jump, `r` refresh, `?` help, `Esc` back.
- Host detail: GPU table, top own processes with kill (own only, confirm), tmux sessions with attach, disk, recent log of state changes.

Embedding a real terminal:
- SwiftTerm (MIT, 1.7k stars, v1.99.1 on 2026-10-21, pushed 2026-10-28): AppKit `TerminalView` and `LocalProcessTerminalView`, used by CodeEdit and shipping SSH clients; wrap in `NSViewRepresentable`.
- Pointing `LocalProcessTerminalView` at `ssh <alias>` with the same ControlPath makes interactive login near-instant because the master is already up.
- libghostty (Ghostty is MIT): `libghostty-vt` is a C and Zig library whose behaviour is mature, but the README says it is untagged and its API signatures are still changing; community Swift bindings (termio-sh/libghostty-swift, MIT) are weeks old.
- Choice: SwiftTerm now behind a small `TerminalSurface` protocol; revisit libghostty when it tags a version, for GPU rendering and better fidelity.

## 4. Agent integration

### 4.1 Hosting options

| Option | Fit |
| --- | --- |
| A. Agent SDK (TypeScript) sidecar | Gives `canUseTool`, in-process hooks, in-process SDK MCP servers, but needs a bundled Node or Bun runtime and a JSON bridge to Swift. |
| B. Swift spawns `claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages` | No extra runtime; same protocol the SDKs use; chosen for v1. |
| C. Community Swift SDKs (kiliczsh, ya-luotao, melMass) | 1 star each, no licence detected; read for protocol, do not depend. |

- The Agent SDK itself runs the Claude Code binary underneath, so B removes one hop; A is the upgrade if we want hooks written in TypeScript.
- Recommendation: B, with the wire structs ported to Swift `Codable` and a golden-file test against recorded streams.

Verified protocol (Python SDK source, `_internal/query.py`):
- stdout is JSON lines: `system` init (lists tools and `mcp_servers` status), partial stream events, `assistant`, `user` (tool results), `result`.
- stdin takes `{"type":"user","message":{"role":"user","content":...},"parent_tool_use_id":null}`, so a second prompt or an image can arrive mid-run.
- Permission round trip: CLI emits `{"type":"control_request","request_id":...,"request":{"subtype":"can_use_tool","tool_name","input","tool_use_id","permission_suggestions","decision_reason","blocked_path","title","display_name","description"}}`.
- App answers with a `control_response` carrying `{"behavior":"allow","updatedInput":{...},"updatedPermissions":[...]}` or `{"behavior":"deny","message":...,"interrupt":bool}`.
- The callback may stay pending indefinitely; for long waits a `PreToolUse` hook can return `defer` and the session resumes later.
- Other control requests: `initialize`, `hook_callback`, interrupt, `set_permission_mode`; model and mode can change live.
- Whether the SDK passes `--permission-prompt-tool stdio` was not located in source; confirm with a trace before relying on it.

Flags confirmed in the CLI reference: `-p`, `--output-format`, `--input-format`, `--include-partial-messages`, `--include-hook-events`, `--replay-user-messages`, `--permission-mode` (default, acceptEdits, plan, auto, dontAsk, bypassPermissions), `--permission-prompt-tool`, `--permission-prompts none|host`, `--mcp-config`, `--strict-mcp-config`, `--allowedTools`, `--disallowedTools`, `--tools`, `--session-id` (UUID), `--resume`, `--fork-session`, `--append-system-prompt`, `--max-turns`, `--max-budget-usd`, `--settings`, `--add-dir`, `--bare`.

Constraints to respect:
- Docs: third-party products may not offer claude.ai login or its rate limits without approval; use API-key auth, or spawn the user's own installed `claude` (their login) and keep this a personal tool.
- Branding: do not name the panel "Claude Code"; use "Claude Agent" or a FocusDock name.

### 4.2 FocusDock as MCP server

- CLI accepts stdio, `http` and `sse` servers only; no unix socket transport is documented.
- Plan: ship a tiny stdio shim `focusdock-mcp` that forwards to the app over a 0600 unix socket in `~/.local/state/focusdock/`; fallback is loopback HTTP with a per-session bearer token.
- Official `modelcontextprotocol/swift-sdk` (1.5k stars, pushed 2026-10-25, licence not auto-detected, check before use) can serve this on the app side.
- Tools are named `mcp__focusdock__*`; allow-list with `mcp__focusdock__fleet_status` style rules (wildcard only after a literal server prefix).
- Tools: `fleet_status`, `fleet_exec(host, cmd, cwd, timeout)`, `fleet_tmux(host, session, send)`, `fleet_job_start(host, spec)`, `fleet_job_stop(host, id)`, `mac_action(id)` from the shared action registry, `mac_applescript(script)`.

### 4.3 Permissions, in evaluation order

Docs order: hooks, deny rules, ask rules, mode, allow rules, `canUseTool`.
- Start sessions in `default` mode with a narrow `allowedTools` (read-only fleet tools, Read, Grep); everything mutating falls to `canUseTool` and becomes a native approval card.
- Deny raw `Bash(ssh *)`, `Bash(scp *)`, `Bash(rsync *)` in `disallowedTools`, but treat that as defence in depth: docs say scoped Bash rules match as written and wrappers escape them, so the real control is that remote work only exists as `fleet_exec`.
- `PreToolUse` hook runs before everything, even in `bypassPermissions`, so it carries the hard rules: resolve `host` against `fleet.jsonc`, force `confirm` for paid and unknown hosts, refuse touching processes not owned by the user on shared hosts, refuse reboot or service restart verbs, append to an audit log.
- Paid host: the approval card names the exact job, shows estimated cost and the stopped-to-running transition, and sets `suppressAlwaysAllowRule`; the app discards any `updatedPermissions` suggestion for these hosts so "always allow" cannot exist.
- Staging jobs: `fleet_job_start` wraps commands in `systemd-run --user -p MemoryMax=12G -p MemorySwapMax=0 -p RuntimeMaxSec=...` itself, so the cap is code, not a prompt.
- GPU placement rule (`shared-gpu-a`, `shared-gpu-b` within `gpuMaxGB`, `shared-gpu-c`, then `paid-gpu`) goes in `--append-system-prompt` for planning and is re-checked in the hook.
- `AskUserQuestion` arrives through the same callback with 1 to 4 questions of 2 to 4 options; render a native choice card and return `answers` keyed by question text.
- Hooks to subscribe to: `PreToolUse` (policy, audit), `PostToolUse` (timeline entry, diff), `PermissionRequest` (notification if the app is not frontmost), `Stop`; `--include-hook-events` mirrors them on the stream.
- Sessions: one UUID per (host, task) via `--session-id`; `--resume` after relaunch; `--fork-session` for "try another approach"; transcripts already live in the CLI's own projects directory.

### 4.4 Acting on the Mac and on hosts

- Mac: Peekaboo MCP for screen and Accessibility, FocusDock action registry for modes, themes and windows, `mac_applescript` limited to an allow-list of apps and verbs, Bash with scoped allow rules (`Bash(git status *)`) for the rest.
- Heavy Mac work stays refused by the placement rule; the agent is told to route builds and tests to `cpu-box`.
- Remote: only through `fleet_*` tools over the existing ControlMaster, so there is no second auth path and every call is auditable.
- A per-host agent tab sets cwd to a local scratch dir and injects host facts (OS, class, GPU, free RAM from the last sample, rules) into the system prompt.
- Alternative not chosen: run `claude` on the remote host inside a SwiftTerm pane; useful for long jobs but bypasses our policy hook, so offer it only as an explicit "open remote agent" action for unshared own hosts.

## 5. UI elements worth having

Sources: Claude desktop and Code, Zed agent panel, Cursor, Warp, Wave (UI items from memory).
- Split layout: fleet grid (left), host detail (centre), agent panel (right), terminal drawer (bottom), all keyboard-resizable.
- Agent panel header: host chip with state dot and class badge, model, permission mode toggle, context meter, session picker.
- Message stream with markdown, streaming text via partial events, and collapsible reasoning.
- Tool-call timeline: one row per call with icon, host, short command, duration, exit status; expand for stdout, stderr and the raw input.
- Approval card: exact command in a monospace block, host and class, working dir, reason from `decision_reason`, buttons Allow once, Allow for this session (hidden for paid), Deny with note, Edit command first (`updatedInput`).
- Diff card for file edits on a host: unified diff with per-hunk accept or reject (Zed review pane, Cursor accept all).
- Question card for `AskUserQuestion` with options, multi-select and free text.
- Plan card in `plan` mode with approve and revise.
- Todo list pinned above the input, as in Claude Code.
- Checkpoints and undo: record pre-state for file edits so one click reverts; show it on the timeline.
- Queued messages and interrupt button (Esc) because stdin accepts new user messages mid-run.
- Terminal pane: SwiftTerm bound to the host, with "send selection to agent" and "run agent suggestion here" actions (Wave and Warp blocks).
- Cost and budget strip using `--max-budget-usd`; hard stop banner.
- Audit tab: append-only log of every call with timestamp, host, decision and who approved.
- Empty and error states: unreachable host shows the ssh reason and a retry key; paid host shows "stopped, start needs confirmation".

## 6. Build order and risks

1. `FleetStore` plus poller (Linux script first), card grid with fake and real data, no agent.
2. Windows script, state machine, backoff, `fleet.jsonc` overlay, `ssh -G` import.
3. SwiftTerm drawer attached to a host through the shared ControlPath.
4. Stream-json client, approval and question cards, session store, golden tests.
5. `focusdock-mcp` shim and `fleet_*` tools with the `PreToolUse` policy hook and audit log.
6. Paid-host flow with a read-only cloud state read and per-start and per-job confirmation.

Risks:
- Protocol drift: the stream-json schema is versioned by the CLI; pin a minimum `claude` version and fail soft on unknown event types.
- Auth and branding terms above; decide personal tool versus distributable before polish.
- ControlMaster sockets left behind after a crash; sweep on launch.
- Fleet output goes to the model; respect the `private` mode rule in SHELL-SPEC section 10 and redact env and token-looking strings in samples.
- Not verified: Citadel and SwiftTerm runtime behaviour.
- Settled by spike S14: Windows poll latency, and the `--permission-prompt-tool stdio` flag the SDKs pass.
