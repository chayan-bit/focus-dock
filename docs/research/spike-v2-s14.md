# Spike v2 S14 - permission wire trace and Windows poll latency (2026-10-28)

Scope: confirm the exact CLI flags and JSON the official Agent SDK uses for `can_use_tool`, confirm a direct stream-json round trip works from a plain process (the way Swift will drive it), and measure a Windows status poll over ssh.
Closes the two "not verified" items in [fleet-agent.md](fleet-agent.md) section 6.

Versions: `claude` CLI 2.1.296 (Claude Code), Python `claude-agent-sdk` 0.2.174 run with `nix-shell -p uv --run 'uv run --with claude-agent-sdk python run.py'` (session-scoped, nothing installed globally).
Model for every run: `haiku` (cheapest alias), `--max-turns 3`, one tool call per run, roughly 0.008 USD each.

## 1. Part A - permission trace

### 1.1 Method
- A shim script was set as the SDK's `cli_path`; it logged argv, every stdin line and every stdout line, then ran the real `claude` with the same argv.
- The SDK client used `ClaudeSDKClient` with `can_use_tool` set, `setting_sources=[]`, `model="haiku"`, and the prompt "run `touch probe.txt && echo hi` with Bash, then say done".
- `touch` is required: a first run with plain `echo hi` never produced a request, because read-only Bash commands are auto-allowed (and the user's own settings also allowed it).
- A second harness (plain Python, stdlib only, no SDK) spawned `claude` with the FocusDock flags and answered requests by hand, to model the Swift side.

### 1.2 Flags the SDK passes
Exact argv captured when `can_use_tool` is set (order as logged):

```
--output-format stream-json --verbose --system-prompt "" --max-turns 3 --model haiku
--permission-prompt-tool stdio --setting-sources= --input-format stream-json
```

- `--permission-prompt-tool stdio` is the switch that routes permission prompts to the host as `control_request` lines on stdout.
- The SDK was only run with a callback set; the direct harness below confirmed that omitting the flag disables host prompts.
- The SDK does not pass `-p`, `--include-partial-messages` or `--print`; stream-json input alone puts the CLI in headless mode for the SDK.
- The SDK runs `claude -v` once first as a version check.
- `--setting-sources=` (empty value) is emitted for `setting_sources=[]` and means no user, project or local settings or hooks are loaded; this makes behaviour deterministic but also drops the user's allow rules and hooks.
- `--system-prompt ""` is the SDK default when none is given; FocusDock should not copy it, it wants the default Claude Code prompt plus `--append-system-prompt`.

### 1.3 Direct CLI round trip (no SDK)
Command used, which is the FocusDock plan plus the SDK's flag:

```
claude -p --input-format stream-json --output-format stream-json --verbose \
  --include-partial-messages --permission-prompt-tool stdio \
  --model haiku --max-turns 3 --setting-sources=
```

| Case | `can_use_tool` request on stdout | Outcome |
|---|---|---|
| allow, initialize sent first | yes | tool ran, `result` subtype `success`, `is_error` false |
| deny with message | yes | tool result `is_error: true` carrying the message, model reported the denial, run ended normally |
| allow, no initialize request at all | yes | identical to the first case |
| allow, flag `--permission-prompt-tool stdio` omitted | no | tool auto-denied, `permission_denials` populated, no request ever emitted |

Conclusions:
- The `can_use_tool` `control_request` arrives on stdout with `-p` plus `--include-partial-messages`; a hand-written `control_response` on stdin is accepted.
- `--permission-prompt-tool stdio` is mandatory; without it `-p` mode silently denies anything that would prompt.
- The `initialize` request is optional for permission handling, so a minimal Swift client can send the user message straight away; send `initialize` anyway when you need hooks, agents or the command list (its response carries `commands`, `agents`, `models`, `account`, `pid`, `claude_code_version`, `current_permission_mode`, `capabilities` and more).
- The process stays alive after the `result` line while stdin is open (that is the multi-turn loop); closing stdin ends it with exit code 0.
- `--help` also lists `--permission-prompts host|none`; `host` means "SDK host or `--permission-prompt-tool` answers", `none` auto-denies.
  It was not needed here.

### 1.4 Captured JSON shapes
Session ids, uuids and paths are redacted.
Every line is one JSON object terminated by a newline.

User message (stdin; the SDK also sends `"session_id":"default"`, the direct harness omitted it and it worked):

```json
{"type":"user","message":{"role":"user","content":"Run the shell command `touch probe.txt && echo hi` using the Bash tool, then say done."},"parent_tool_use_id":null,"session_id":"default"}
```

Initialize (stdin) and its reply (stdout, `response` keys listed, values omitted):

```json
{"type":"control_request","request_id":"req_1_xxxxxxxx","request":{"subtype":"initialize","hooks":null}}
{"type":"control_response","response":{"subtype":"success","request_id":"req_1_xxxxxxxx","response":{"commands":[],"agents":[],"models":[],"account":{},"pid":0,"claude_code_version":"2.1.296","current_permission_mode":"default","capabilities":{}}}}
```

Permission request (stdout), identical in the SDK run and the direct run apart from ids:

```json
{"type":"control_request","request_id":"<uuid>","request":{
  "subtype":"can_use_tool",
  "tool_name":"Bash",
  "display_name":"Bash",
  "input":{"command":"touch probe.txt && echo hi","description":"Create probe.txt and echo hi"},
  "description":"Create probe.txt and echo hi",
  "permission_suggestions":[
    {"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"touch probe.txt && echo hi"}],"behavior":"allow","destination":"localSettings"},
    {"type":"addDirectories","directories":["<cwd>"],"destination":"session"},
    {"type":"setMode","mode":"acceptEdits","destination":"session"}],
  "blocked_path":"<cwd>/probe.txt",
  "tool_use_id":"toolu_..."}}
```

- `title`, `decision_reason` and `suppressAlwaysAllowRule` did not appear in this request; treat them as optional fields in `Codable` (they may appear for other tools or reasons).
- `permission_suggestions` offered three kinds here: `addRules`, `addDirectories`, `setMode`; FocusDock can render them as "Allow for session" style options and must discard them for paid and unknown hosts.
- `blocked_path` is present because the write target was outside the allowed directories.

Allow response (stdin), exactly what the SDK wrote and what the direct harness wrote:

```json
{"type":"control_response","response":{"subtype":"success","request_id":"<same uuid>","response":{"behavior":"allow","updatedInput":{"command":"touch probe.txt && echo hi","description":"Create probe.txt and echo hi"}}}}
```

- `updatedInput` must be the full input object (echo it back unchanged to approve as-is, or edit it for "Edit first").
- `updatedPermissions` is optional and would carry a chosen `permission_suggestions` entry for "Allow for session".

Deny response (stdin):

```json
{"type":"control_response","response":{"subtype":"success","request_id":"<same uuid>","response":{"behavior":"deny","message":"Denied by FocusDock test","interrupt":false}}}
```

Resulting tool result on the stream after a deny (stdout), plus the final `result` listing the denial:

```json
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"Denied by FocusDock test","is_error":true,"tool_use_id":"toolu_..."}]},"parent_tool_use_id":null,"session_id":"<uuid>","uuid":"<uuid>","tool_use_result":"Error: Denied by FocusDock test","tool_result_meta":[{"id":"toolu_...","non_execution_kind":"permission-rule","permission_decision":{"decision":"reject","source":"user_reject"}}]}
```

Other stdout lines seen around the request, useful for the Swift decoder:
- `{"type":"system","subtype":"init",...}` with keys `session_id`, `cwd`, `tools`, `mcp_servers`, `model`, `permissionMode` (`default`), `skills`, `slash_commands`, `agents`, `plugins`, `claude_code_version`, `apiKeySource`, `capabilities`.
- `{"type":"system","subtype":"session_state_changed","state":"requires_action"|"idle",...}` brackets a pending permission request, which is a cheap signal for "needs attention" badges.
- `{"type":"stream_event","event":{...}}` per partial token when `--include-partial-messages` is set (`message_start`, `content_block_start`, `content_block_delta`, `content_block_stop`, `message_delta`, `message_stop`).
- Also `system` subtypes `status`, `commands_changed`, `thinking_tokens`, `post_turn_summary`, `task_summary`, `hook_started` and `hook_response`, plus `rate_limit_event`.
- Final `{"type":"result","subtype":"success","is_error":false,"stop_reason":"end_turn","terminal_reason":"completed","num_turns":2,"total_cost_usd":0.0076,"permission_denials":[...],"duration_ms":...,"usage":{...},"modelUsage":{...},...}`; the decoder must tolerate many extra keys.

### 1.5 Recommended flags for FocusDock
```
claude -p --input-format stream-json --output-format stream-json --verbose \
  --include-partial-messages --permission-prompt-tool stdio \
  --session-id <uuid> [--resume <uuid>] --permission-mode default \
  --allowedTools <read-only list> --disallowedTools "Bash(ssh *)" ... \
  --mcp-config <file> --strict-mcp-config \
  --append-system-prompt <host facts and rules> --max-budget-usd <n>
```

- `--permission-prompt-tool stdio` is required; add it to the flag list in SHELL-SPEC section 9.2.
- Do not use `--setting-sources=` in production unless the product intends to ignore the user's own settings and hooks; the spike used it only to make the permission request deterministic.
  Decide this explicitly: loading user settings means the user's allow rules and hooks can pre-empt `can_use_tool`.
- Do not pass `--system-prompt ""`.
- Send the first user message without waiting for anything; read stdout line by line, decode by `type`, answer each `can_use_tool` by `request_id`.
- Keep stdin open for multi-turn; close it (or kill) to end the process.
- Answer every request, including unknown subtypes (reply with an error `control_response`), or the turn stalls.
- Golden-file tests: record these streams (redacted) from `d1-allow` and `d2-deny` style runs.

## 2. Part B - Windows poll latency (`shared-gpu-a (Windows)`)

All commands were read-only; no other user's process was touched, nothing was restarted.

### 2.1 Method
- One OpenSSH ControlMaster connection (`ControlMaster=auto`, `ControlPersist=60`), `BatchMode=yes`, `ConnectTimeout=5`; the remote default shell is `cmd`.
- Warm numbers are 10 runs per variant, wall clock measured on the Mac around the whole `ssh` call (median, p90 by nearest rank, min and max in ms).
- Cold is the first call after `ssh -O exit`, so it includes TCP, key exchange and authentication.
- The host runs Windows PowerShell 5.1 on Windows 11 and has `nvidia-smi`, `wmic`, `typeperf` on PATH.
- The scripts are sentinel-delimited (`@@cpu`, `@@mem`, `@@disk`, `@@gpu`) and sent as `powershell -NoProfile -NonInteractive -EncodedCommand <base64 UTF-16LE>`.
- Gotcha: the ControlPath must stay under the 104-byte unix socket limit; a long scratch directory made `ssh` fail with "ControlPath too long" before connecting, so the spike used a short path.

### 2.2 Headline result
The CIM plan in fleet-agent.md section 2 does not work on this host for a standard (non-elevated) ssh session.

- `Get-CimInstance` and `Get-WmiObject` both fail with "Access denied" after about 5 s per query; three queries cost about 16 s end to end, and the script exits non-zero.
- `wmic` fails the same way (about 15.6 s for three calls).
- `typeperf` fails too ("must be a member of the Performance Log Users group or elevated").
- The ssh logon token is medium integrity and not in those groups, so WMI namespaces and counter sessions are closed to it.
- This is a host permission issue, not a latency issue; do not assume CIM works on any Windows host; treat it as a capability to probe.

What does work without elevation:
- `nvidia-smi` for GPU utilisation and memory.
- .NET `Microsoft.VisualBasic.Devices.ComputerInfo` for physical memory total and available (about 80 ms over PowerShell startup).
- .NET `[IO.DriveInfo]::GetDrives()` for fixed-disk size and free space (about 25 ms).
- `GetSystemTimes` from `kernel32` via `Add-Type` for CPU load (two samples 100 ms apart; costs about 0.4 s for the compile plus the 100 ms sleep).
- `dir /-c C:\` piped to `find "bytes free"` from plain `cmd` for disk free (about 130 ms including the ssh round trip).
- `[Diagnostics.PerformanceCounter]` also works unelevated but is slow here (2 to 4 s, see below).

### 2.3 Latency table (ms)
| Variant | Median | p90 | Min | Max | Notes |
|---|---|---|---|---|---|
| Recommended: `nvidia-smi` in cmd, then one PowerShell for CPU, mem, disk (.NET and `GetSystemTimes`) | 1321 | 1350 | 1298 | 1366 | Cold (new master): 2858 |
| `nvidia-smi` alone from cmd | 192 | 199 | 172 | 202 | Floor for one ssh round trip plus the GPU query |
| PowerShell startup only (`'@@x'`) | 703 | 715 | 688 | 718 | Dominant fixed cost of any PowerShell poll |
| All in PowerShell, .NET plus `PerformanceCounter` plus `nvidia-smi` | 3119 | 3206 | 1437 | 5253 | Bimodal; slow, see attribution |
| All in PowerShell, CIM (spec plan) | 16193 | 16227 | 16170 | 16240 | Fails: access denied, about 5 s per query |
| `cmd` with three `wmic` calls | 15616 | 15637 | 15579 | 15707 | Fails: access denied |
| `cmd` `systeminfo` memory line | 5174 | 5177 | 5152 | 5177 | Works but far too slow |
| `cmd` `dir /-c C:\` free-space line | 131 | 149 | 127 | 149 | Cheap disk-free fallback without PowerShell |

Final recommended run, 10 warm: median 1321, p90 1350, cold 2858.
The budget in fleet-agent.md is warm under 1500, cold under 4000, hard kill at 6000; the recommended variant fits all three.

### 2.4 What dominates
Per-part attribution, measured by single-part scripts (warm, ms over or including ssh):

| Part | Cost |
|---|---|
| ssh round trip on a warm master (`cmd` echo or `dir`) | about 130 |
| `nvidia-smi` launched from `cmd` | about 60 on top of the round trip (190 total) |
| `powershell -NoProfile` startup | about 570 on top of the round trip (700 total) |
| `Add-Type` VisualBasic plus `ComputerInfo` | about 80 |
| `[IO.DriveInfo]` | about 25 |
| `GetSystemTimes` P/Invoke plus 100 ms sample | about 500 |
| `PerformanceCounter` (two samples) launched from PowerShell | 2000 to 4000 |
| `nvidia-smi` launched from PowerShell | about 2000 extra, and only the exit of the process, in-script time was under 100 ms |
| CIM or WMI query | about 5000 each, all failing |

- PowerShell startup is the biggest unavoidable cost, then the CPU sample; the CIM path is not just slow here, it is unusable.
- Two anomalies reproduced consistently: launching `nvidia-smi` from inside PowerShell, and using `PerformanceCounter`, each added 2 to 3 s of wall time even though the script's own stopwatch showed under 250 ms of work; the delay is at process teardown or outside the script body.
  Running `nvidia-smi` from `cmd` instead avoids it.
- Early in the session some of these variants measured much faster (a combined PowerShell script ran in about 0.95 s and `PerformanceCounter` alone in about 1.1 s), so the host has load-dependent or time-dependent behaviour; treat the slow-path numbers as the safe planning figure.
- The recommended script itself was stable (spread under 70 ms across 10 runs).
- Composing in `cmd` (`nvidia-smi ... & echo @@sys & powershell ...`) keeps it to one ssh exec and one round trip.

### 2.5 Recommended Windows poll
One `ssh` exec, cmd composition, PowerShell receiving only the part that needs .NET:

```
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader & echo @@sys & powershell -NoProfile -NonInteractive -EncodedCommand <base64>
```

PowerShell body before encoding (UTF-16LE then base64; the command is about 2 KB, well under the `cmd` 8191 limit):

```powershell
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out long i,out long k,out long u);' -Name K -Namespace W
$ci=New-Object Microsoft.VisualBasic.Devices.ComputerInfo
$i1=0L;$k1=0L;$u1=0L;[void][W.K]::GetSystemTimes([ref]$i1,[ref]$k1,[ref]$u1)
Start-Sleep -Milliseconds 100
$i2=0L;$k2=0L;$u2=0L;[void][W.K]::GetSystemTimes([ref]$i2,[ref]$k2,[ref]$u2)
$t=($k2-$k1)+($u2-$u1)
'@@cpu';"$($t) $($i2-$i1)"
'@@mem';"$([int64]($ci.TotalPhysicalMemory/1024)) $([int64]($ci.AvailablePhysicalMemory/1024))"
'@@disk';[IO.DriveInfo]::GetDrives()|?{$_.DriveType -eq 'Fixed'}|%{"$($_.Name) $($_.TotalSize) $($_.AvailableFreeSpace)"}
```

Observed output shape (values redacted):

```
<util> %, <used> MiB, <total> MiB
@@sys
@@cpu
<total_100ns> <idle_100ns>
@@mem
<total_kib> <avail_kib>
@@disk
C:\ <size_bytes> <free_bytes>
D:\ <size_bytes> <free_bytes>
```

Parsing notes:
- Lines end with CRLF; split on `\r?\n`.
- CPU percent is `100 * (total - idle) / total` from the two numbers; `total` already covers all logical processors.
- stderr carries a harmless `#< CLIXML` progress blob ("Preparing modules for first use"); ignore stderr when the exit code is 0, or add `$ProgressPreference='SilentlyContinue'` as the first statement.
- If `nvidia-smi` is missing the GPU line will be an error text, so treat a non-numeric GPU line as "GPU unknown" rather than host down.
- Own-process listing (the `Get-Process` filter in fleet-agent.md) was not measured; `Get-Process` needs no elevation for own processes but adds more PowerShell work, so budget it separately and poll it less often.

### 2.6 Impact on SHELL-SPEC and fleet-agent.md
- Windows polling: replace "Get-CimInstance Win32_*" with the .NET plus `GetSystemTimes` plus cmd-launched `nvidia-smi` recipe, and probe CIM once per host as an optional capability.
- Windows poll cadence: at least 15 s for visible hosts and 30 s for others, because one poll costs about 1.3 s warm and about 2.9 s cold; keep the 6 s hard kill.
- A failed CIM attempt wastes about 5 s per query, so never run CIM inside the budgeted poll unless the probe succeeded.
- Add the ControlPath length rule to the ssh mechanics (keep the prefix short; hashed `%C` is 40 characters).
- Linux hosts are not covered by this spike.

## 3. Reproduction notes
- SDK trace: shim as `cli_path`, `can_use_tool` callback returning `PermissionResultAllow()`, `setting_sources=[]`, a prompt that forces a non-read-only Bash command.
- Direct trace: spawn `claude` with the flags in section 1.3, write the user message, loop over stdout, answer `can_use_tool` with the shapes in section 1.4, close stdin after the `result` line.
- Windows: encode scripts with UTF-16LE base64, send over a ControlMaster connection with a short ControlPath, time the whole call on the Mac.
