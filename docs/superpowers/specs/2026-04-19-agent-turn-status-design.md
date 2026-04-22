---
date: 2026-04-19
topic: Agent turn success/failed + session persistence + transcript summary + verbose tool detail
status: draft
---

# Agent Turn Status — Success/Failed, Session Persistence, Transcript Summary, Verbose Tool Detail

## Background

The previous spec (`2026-04-19-terminal-status-exit-code-design.md`) wired up `.success` / `.failed` for shell commands using `$?`. AI code agents (Claude Code, Codex, OpenCode) remain stuck at `running` / `idle` / `needsInput` because a "turn" has no exit code and their hook infrastructure is stateless per-invocation.

Prior art in this space has worked around the problem with fragile substring matching on notification text (e.g. a `classifyClaudeNotification`-style heuristic), without consuming Claude's `PostToolUse.tool_response.is_error` — the structured field that actually answers "did this turn have errors?".

This spec closes that gap by: (1) consuming `PostToolUse` structured output, (2) aggregating per-session `turnHadError`, (3) emitting the existing `finished` event at `Stop` with an exitCode sentinel (0 = clean, 1 = had errors), (4) attaching a transcript summary for tooltip context, and (5) surfacing the live tool name as a `running` subtitle.

## Goals

- `.success` / `.failed` icons light up for Claude Code and Codex agent turns, with exit-code sentinel encoding (0 = clean turn, 1 = turn had tool errors)
- OpenCode agent turns same, but via in-process plugin state (no session file)
- Per-turn aggregation: tool-level failures that the agent recovers from do NOT poison the outcome
- Tooltip shows agent name + optional transcript summary
- Running state optionally carries `toolDetail` ("Editing Models/Foo.swift") for real-time visibility
- Session state (per-session `turnHadError`, current tool, transcript path) persists in a local JSON file so stateless hook commands can accumulate
- Stop hook cleans up its own session entry; stale entries (>1h no touch) GC'd on next hook fire

## Non-Goals

- Sidebar row subtitles or tab breadcrumb text (tooltip-only UI changes)
- MCP tool descriptions (only built-in Claude/OpenCode tools covered in v1)
- Cross-terminal session sharing (1 terminal = 1 session always)
- Retroactive status for pre-existing sessions at mux0 startup
- Changing aggregation semantics to tool-level (turn-level is the product choice)
- Migrating to a universal `set_status <key> <value>` wire; we keep the typed enum

## Architecture

```
┌──────────────┐   hook stdin JSON   ┌────────────────┐
│ Claude Code  │ ──────────────────▶ │ agent-hook.sh  │── Unix socket ──┐
│  hooks.json  │   UserPromptSubmit, │  + agent-hook  │                 │
└──────────────┘   PreToolUse,       │    .py         │                 │
                   PostToolUse, Stop └────────────────┘                 │
                                            │                            │
                                            ▼                            │
                              ~/Library/Caches/mux0/                     │
                              agent-sessions.json                        │
                                                                         │
┌──────────────┐   same as Claude    ┌────────────────┐                  │
│ Codex        │ ──────────────────▶ │ agent-hook.sh  │── Unix socket ───┤
│  hooks.json  │                     │   (same)       │                  │
└──────────────┘                     └────────────────┘                  │
                                                                         ▼
┌──────────────┐   bus events        ┌────────────────┐         ┌──────────────────┐
│ OpenCode     │ ──────────────────▶ │ mux0-status.js │── sock ▶│ HookSocketListener│
│  plugin      │   tool.execute.     │ in-mem turn    │         └──────────────────┘
│              │   after, session.*  │  state         │                  │
└──────────────┘                     └────────────────┘                  ▼
                                                                 ┌──────────────────┐
                                                                 │ TerminalStatusStore│
                                                                 └──────────────────┘
```

Claude and Codex share one session file (keyed by their session_id) because their hook payload schema is identical. OpenCode stays in-process since its plugin has memory.

## Wire Format Changes

### `HookMessage` (Swift, additive)

Two new optional fields:

```swift
struct HookMessage: Decodable, Equatable {
    let terminalId: UUID
    let event: Event                  // unchanged
    let agent: Agent                  // unchanged
    let at: TimeInterval
    let exitCode: Int32?              // Task 1 of prior spec
    let toolDetail: String?           // NEW — running state only
    let summary: String?              // NEW — finished state only
}
```

`toolDetail` appears on `.running` messages when PreToolUse / tool.execute.before fires with a tool name + inputs. `summary` appears on `.finished` messages when a Stop hook can read the Claude transcript or OpenCode has accumulated assistant text.

Neither field is required by the decoder; missing → `nil`.

### Agent exitCode sentinel

For agents, `exitCode` is a sentinel, not a real process exit code:
- `0` → clean turn (no tool reported `is_error`)
- `1` → turn had at least one tool error

Semantics differ from shell (`exitCode` = real `$?`) but the wire field is reused. The Swift side distinguishes shell-vs-agent display via the `agent` enum, not by reading the exitCode value.

### Wire examples

```json
// Claude PreToolUse → running with tool detail
{"terminalId":"…","event":"running","agent":"claude","at":1713500000.1,"toolDetail":"Edit Models/Workspace.swift"}

// Claude Stop → clean turn
{"terminalId":"…","event":"finished","agent":"claude","at":1713500015.3,"exitCode":0,"summary":"Refactored WorkspaceStore to use async migration."}

// Claude Stop → turn had errors
{"terminalId":"…","event":"finished","agent":"claude","at":1713500020.1,"exitCode":1,"summary":"Attempted 3 edits; 2 succeeded, 1 failed (permission)."}

// Shell (unchanged)
{"terminalId":"…","event":"finished","agent":"shell","at":1713500030.0,"exitCode":0}
```

## Swift State Model Changes

### `TerminalStatus` (additive)

Extend associated values with defaulted parameters so existing call sites are unchanged:

```swift
enum TerminalStatus: Equatable {
    case neverRan
    case running(startedAt: Date, detail: String? = nil)
    case idle(since: Date)
    case needsInput(since: Date)
    case success(exitCode: Int32, duration: TimeInterval, finishedAt: Date,
                 agent: HookMessage.Agent = .shell, summary: String? = nil)
    case failed(exitCode: Int32, duration: TimeInterval, finishedAt: Date,
                agent: HookMessage.Agent = .shell, summary: String? = nil)
}
```

**Equatable:** Swift's synthesized `Equatable` includes all associated values, so `detail`, `agent`, `summary` participate in equality. This matches the "state identity" semantic — two `.success(…)` values with different summaries are not equal. Tests that previously expected `.success(exitCode: 0, duration: 5, finishedAt: t)` need no update because of default-arg semantics at the construction site; assertion-side only needs adjustment when tests construct a `.success` with an agent other than `.shell`.

**Aggregate priority:** unchanged. Agents don't get special priority — same `.success` / `.failed` priority as shell, regardless of source.

### `TerminalStatusStore.setFinished` (additive)

```swift
func setFinished(terminalId: UUID, exitCode: Int32, at finishedAt: Date,
                 agent: HookMessage.Agent = .shell, summary: String? = nil)
```

Duration derivation unchanged. The new `agent` and `summary` parameters pass straight through to the enum case.

### `TerminalStatusStore` (new method for running detail)

`setRunning` currently takes `(terminalId, at)`. Extend with optional detail:

```swift
func setRunning(terminalId: UUID, at startedAt: Date, detail: String? = nil)
```

A subsequent `setRunning` with a new `detail` overwrites the previous one (latest tool wins during a turn). No separate `setRunningDetail` method — keep a single code path into `.running`.

### `HookMessage.Agent` display

Add a display-friendly accessor:

```swift
extension HookMessage.Agent {
    var displayName: String {
        switch self {
        case .shell:    return "Shell"
        case .claude:   return "Claude"
        case .opencode: return "OpenCode"
        case .codex:    return "Codex"
        }
    }
}
```

### `TerminalStatusIconView.tooltipText`

Augment to use agent + summary + detail:

```swift
static func tooltipText(for status: TerminalStatus) -> String? {
    switch status {
    case .neverRan: return nil
    case .running(let startedAt, let detail):
        let elapsed = max(0, Date().timeIntervalSince(startedAt))
        let first = "Running for \(formatDuration(elapsed))"
        return detail.map { "\(first)\n\($0)" } ?? first
    case .idle(let since):
        return "Idle for \(formatDuration(max(0, Date().timeIntervalSince(since))))"
    case .needsInput(let since):
        return "Needs input (\(formatDuration(max(0, Date().timeIntervalSince(since)))) ago)"
    case .success(let exit, let duration, _, let agent, let summary):
        let prefix = agent == .shell
            ? "Succeeded in \(formatDuration(duration)) · exit \(exit)"
            : "\(agent.displayName): turn finished · \(formatDuration(duration))"
        return summary.map { "\(prefix)\n\($0)" } ?? prefix
    case .failed(let exit, let duration, _, let agent, let summary):
        let prefix = agent == .shell
            ? "Failed after \(formatDuration(duration)) · exit \(exit)"
            : "\(agent.displayName): turn had tool errors · \(formatDuration(duration))"
        return summary.map { "\(prefix)\n\($0)" } ?? prefix
    }
}
```

Icon visual (dot shape, color, spin/pulse animations) is **unchanged**. Success is green whether agent or shell; failed is red whether agent or shell.

## Session File

### Location

`~/Library/Caches/mux0/agent-sessions.json` (Caches, not Application Support — sessions are short-lived; losing the file to OS cleanup is acceptable since next hook fire rebuilds its entry).

### Schema

```json
{
  "version": 1,
  "sessions": {
    "<agent-session-id>": {
      "agent": "claude",
      "terminalId": "<mux0 terminal UUID from env MUX0_TERMINAL_ID>",
      "turnStartedAt": 1713500000.0,
      "turnHadError": false,
      "currentToolName": "Edit",
      "currentToolDetail": "Edit Models/Foo.swift",
      "transcriptPath": "/Users/.../.claude/sessions/abc/transcript.jsonl",
      "lastTouched": 1713500010.5
    }
  }
}
```

`<agent-session-id>` is the agent's own session identifier (`session_id` field in Claude/Codex hook payload). If the payload has no session_id, fall back to `MUX0_TERMINAL_ID` — agents outside the normal lifecycle (e.g. custom scripts calling hook-emit directly) get one pseudo-session per terminal.

### Concurrency

`flock(LOCK_EX)` on the file during read-modify-write. Contention negligible (hooks are milliseconds apart, not concurrent).

### GC

Every `agent-hook.py` invocation sweeps: entries with `lastTouched < now - 3600` are dropped before writing back. `Stop` handling also explicitly `pop()`s its own entry.

No Swift-side GC (Q2 resolved: skip — python sweep is sufficient).

## Agent Signal Source Table

| Agent | Event | Fields read | Action |
|-------|-------|-------------|--------|
| Claude | `UserPromptSubmit` | `session_id`, `transcript_path` | Session entry: reset `turnHadError=false`, stash transcript path. Emit `running`. |
| Claude | `PreToolUse` | `session_id`, `tool_name`, `tool_input` | Update `currentToolName` / `currentToolDetail`. Emit `running` with `toolDetail`. |
| Claude | `PostToolUse` | `session_id`, `tool_response.is_error` | If error → `turnHadError=true` (sticky). No socket emit. |
| Claude | `Stop` | `session_id` + cached transcript path | Compute summary from transcript. Emit `finished` with `exitCode=0` or `1` and `summary`. Delete session entry. |
| Codex | same as Claude (hook schema identical) | same | same |
| OpenCode | `tool.execute.before` | plugin callback args | Update in-memory `turn.tool`. Emit `running` with `toolDetail`. |
| OpenCode | `tool.execute.after` | `args.result.status` / `args.error` | If error → in-memory `turn.hadError=true`. No socket emit. |
| OpenCode | `session.idle` / `session.status{type=idle}` / `session.error` | — | Emit `finished` with `exitCode=0` or `1`. Reset in-memory `turn`. Summary stays `nil` in v1. |

### Claude `tool_response.is_error` contract

True when the tool threw or explicitly returned `is_error: true`. User-rejected tool calls (via permission prompt) fire `Notification` not `PostToolUse`, so they don't pollute `turnHadError`. Confirmed against Claude Code v2 hook docs.

### Codex `features.codex_hooks` dependency

PostToolUse/Stop/etc. only fire if the user has `features.codex_hooks = true` in `~/.codex/config.toml`. Without that flag, Codex remains at the current behavior (only `notify` emits idle — no turn status). Documented as a known limitation; no fallback.

### OpenCode summary (v1 deferred)

OpenCode's plugin has no direct analog to Claude's `transcript_path`. Accumulating assistant text from `message.appended` events is possible but undocumented. v1 ships with `summary: nil` for OpenCode; a future spec can add it.

## `agent-hook.sh` + `agent-hook.py`

**Separation:** a tiny bash entry (`agent-hook.sh`) exports env vars and execs `agent-hook.py`. The bash half is stable; all logic is Python so it can be unit-tested and read clearly.

### `agent-hook.sh`

```bash
#!/bin/bash
# agent-hook.sh — thin bash entry for agent-hook.py. Delegates all logic to Python.
# Usage: agent-hook.sh <subcommand> <agent>
#   subcommand: prompt | pretool | posttool | stop
#   agent:      claude | codex

set -e

[ -z "$MUX0_HOOK_SOCK" ] && exit 0
[ -z "$MUX0_TERMINAL_ID" ] && exit 0

subcmd="${1:-stop}"
agent="${2:-claude}"
script_dir="$(dirname "${BASH_SOURCE[0]}")"

export _MUX0_SUBCMD="$subcmd"
export _MUX0_AGENT="$agent"
export _MUX0_SESSION_FILE="${HOME}/Library/Caches/mux0/agent-sessions.json"

# Forward stdin JSON payload to Python via env var (easier than passing stdin
# through exec; payload is small).
export _MUX0_PAYLOAD
_MUX0_PAYLOAD=$(cat)

exec python3 "$script_dir/agent-hook.py"
```

### `agent-hook.py` (canonical structure)

```python
#!/usr/bin/env python3
# agent-hook.py — agent lifecycle dispatch for Claude Code / Codex hooks.
# Invoked by agent-hook.sh. All state in env vars + stdin already read.

import json, os, re, sys, time, fcntl, socket, pathlib

# --- Config ---
SUBCMD          = os.environ.get("_MUX0_SUBCMD", "stop")
AGENT           = os.environ.get("_MUX0_AGENT", "claude")
PAYLOAD_RAW     = os.environ.get("_MUX0_PAYLOAD", "")
SESSION_FILE    = pathlib.Path(os.environ["_MUX0_SESSION_FILE"])
TERMINAL_ID     = os.environ["MUX0_TERMINAL_ID"]
SOCK_PATH       = os.environ["MUX0_HOOK_SOCK"]
SESSION_TTL_SEC = 3600
SUMMARY_MAXLEN  = 200

def parse_payload() -> dict:
    try:
        return json.loads(PAYLOAD_RAW) if PAYLOAD_RAW.strip() else {}
    except json.JSONDecodeError:
        return {}

def describe_tool(tool: str, inp: dict) -> str:
    if not isinstance(inp, dict):
        return tool
    if tool in ("Edit", "Write", "Read"):
        p = short_path(inp.get("file_path", ""))
        return f"{tool} {p}" if p else tool
    if tool == "Bash":
        cmd = (inp.get("command") or "").split("\n")[0][:60]
        return f"Bash: {cmd}" if cmd else "Bash"
    if tool == "Grep":
        return f"Grep {inp.get('pattern', '')!r}"
    if tool == "Glob":
        return f"Glob {inp.get('pattern', '')}"
    if tool == "Task":
        return f"Subagent: {inp.get('subagent_type', 'general-purpose')}"
    return tool

def short_path(p: str) -> str:
    parts = [s for s in p.split("/") if s]
    return "/".join(parts[-3:]) if len(parts) > 3 else p

def read_transcript_summary(path: str) -> str:
    if not path:
        return ""
    try:
        with open(path) as f:
            lines = f.readlines()
    except (FileNotFoundError, IsADirectoryError, PermissionError):
        return ""
    for line in reversed(lines):
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if msg.get("role") != "assistant":
            continue
        content = msg.get("content", "")
        if isinstance(content, list):
            text = ""
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    text = block.get("text", "")
                    break
            content = text
        if not isinstance(content, str):
            continue
        content = re.sub(r"<thinking>.*?</thinking>", "", content, flags=re.S)
        content = " ".join(content.split())
        if content:
            return content[:SUMMARY_MAXLEN]
    return ""

def load_sessions() -> dict:
    if not SESSION_FILE.exists():
        return {"version": 1, "sessions": {}}
    try:
        with open(SESSION_FILE) as f:
            fcntl.flock(f, fcntl.LOCK_SH)
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return {"version": 1, "sessions": {}}

def write_sessions(data: dict) -> None:
    SESSION_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(SESSION_FILE, "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        json.dump(data, f)

def gc_stale(sessions: dict, now: float) -> dict:
    cutoff = now - SESSION_TTL_SEC
    return {
        "version": 1,
        "sessions": {
            sid: s for sid, s in sessions.get("sessions", {}).items()
            if s.get("lastTouched", 0) > cutoff
        },
    }

def emit_to_socket(msg: dict) -> None:
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.5)
        s.connect(SOCK_PATH)
        s.sendall((json.dumps(msg) + "\n").encode())
        s.close()
    except Exception:
        pass  # silent — same pattern as hook-emit.sh

def main():
    payload = parse_payload()
    session_id = payload.get("session_id") or payload.get("sessionId") or TERMINAL_ID
    now = time.time()

    sessions_doc = load_sessions()
    entries = sessions_doc.setdefault("sessions", {})
    entry = entries.setdefault(session_id, {
        "agent": AGENT,
        "terminalId": TERMINAL_ID,
        "turnStartedAt": 0,
        "turnHadError": False,
        "currentToolName": None,
        "currentToolDetail": None,
        "transcriptPath": None,
        "lastTouched": 0,
    })
    entry["agent"] = AGENT
    entry["terminalId"] = TERMINAL_ID
    entry["lastTouched"] = now

    emit = None
    if SUBCMD == "prompt":
        entry["turnStartedAt"] = now
        entry["turnHadError"] = False
        entry["currentToolName"] = None
        entry["currentToolDetail"] = None
        transcript = payload.get("transcript_path")
        if transcript:
            entry["transcriptPath"] = transcript
        emit = {"event": "running", "at": now}
    elif SUBCMD == "pretool":
        tool = payload.get("tool_name", "")
        tool_input = payload.get("tool_input", {})
        detail = describe_tool(tool, tool_input) if tool else None
        entry["currentToolName"] = tool or None
        entry["currentToolDetail"] = detail
        emit = {"event": "running", "at": now}
        if detail:
            emit["toolDetail"] = detail
    elif SUBCMD == "posttool":
        resp = payload.get("tool_response", {})
        if isinstance(resp, dict) and resp.get("is_error"):
            entry["turnHadError"] = True
    elif SUBCMD == "stop":
        exit_code = 1 if entry.get("turnHadError") else 0
        summary = read_transcript_summary(entry.get("transcriptPath") or "")
        emit = {"event": "finished", "at": now, "exitCode": exit_code}
        if summary:
            emit["summary"] = summary
        entries.pop(session_id, None)

    sessions_doc = gc_stale(sessions_doc, now)
    write_sessions(sessions_doc)

    if emit:
        emit.update({"terminalId": TERMINAL_ID, "agent": AGENT})
        emit_to_socket(emit)

if __name__ == "__main__":
    main()
```

## `claude-wrapper.sh` Changes

The injected `hooks.json` swaps `hook-emit.sh` for `agent-hook.sh` on the four events that need session state. `SessionStart`/`SessionEnd`/`Notification` keep the simpler `hook-emit.sh` path.

```json
{
  "hooks": {
    "SessionStart":     [{"matcher":"","hooks":[{"type":"command","command":"$EMIT idle claude"}]}],
    "UserPromptSubmit": [{"matcher":"","hooks":[{"type":"command","command":"$AGENT_HOOK prompt claude"}]}],
    "PreToolUse":       [{"matcher":"","hooks":[{"type":"command","command":"$AGENT_HOOK pretool claude"}]}],
    "PostToolUse":      [{"matcher":"","hooks":[{"type":"command","command":"$AGENT_HOOK posttool claude"}]}],
    "Stop":             [{"matcher":"","hooks":[{"type":"command","command":"$AGENT_HOOK stop claude"}]}],
    "Notification":     [{"matcher":"","hooks":[{"type":"command","command":"$EMIT needsInput claude"}]}],
    "SessionEnd":       [{"matcher":"","hooks":[{"type":"command","command":"$EMIT idle claude"}]}]
  }
}
```

`$EMIT` = `$MUX0_AGENT_HOOKS_DIR/hook-emit.sh`.
`$AGENT_HOOK` = `$MUX0_AGENT_HOOKS_DIR/agent-hook.sh`.

## `codex-wrapper.sh` Changes

Mirror of Claude. Keep `notify = [...hook-emit.sh, idle, codex]` as the last-resort tick for users without `codex_hooks=true`.

## `opencode-plugin/mux0-status.js` Changes

Add in-memory `turn = { hadError: false, tool: null, startedAt: null }`. Emit `running` + `toolDetail` from `tool.execute.before`; set `hadError=true` from `tool.execute.after` when the result indicates error; emit `finished` + `exitCode` on `session.idle` / `session.status{type:idle}` / `session.error`; reset `turn`.

Full source follows the pattern shown in §3.6 of the brainstorming transcript.

## UI Changes

**Only `TerminalStatusIconView.tooltipText`.** The icon renderer itself is untouched — existing `.success` / `.failed` branches already produce green/red dots, regardless of `agent` associated value.

No sidebar row subtitle, no tab breadcrumb, no new label components.

## Testing

### Swift unit tests

- `HookMessageTests`:
  - Decode `running` with `toolDetail`
  - Decode `finished` with `agent=claude` + `summary`
  - Decode a shell-shape message that lacks the new fields (must still decode)
- `TerminalStatusStoreTests`:
  - `setRunning` with `detail` stores as `.running(startedAt:, detail:)`
  - `setFinished` with `agent=.claude` + `summary` stores as `.success(…, agent: .claude, summary: "…")`
  - `setFinished` without `agent` argument still defaults to `.shell` (backward compat)
- `TerminalStatusIconViewTests` (new file):
  - 4×2 matrix: (shell success / shell failed / agent success / agent failed) × (with summary / without)
  - Running with detail vs running without

### Python unit tests (`Resources/agent-hooks/tests/test_agent_hook.py`)

- `describe_tool` cases for Edit / Write / Read / Bash / Grep / Glob / Task / unknown
- `short_path` truncation
- `read_transcript_summary` happy path + empty + malformed JSON + no assistant + thinking stripping + missing file
- `gc_stale` drops entries older than cutoff, keeps recent
- end-to-end `main()` flow with a fake payload and a fake session file: prompt → pretool → posttool (is_error=true) → stop → assert socket msg has `exitCode=1`, assert session entry popped

Run with `python3 -m pytest Resources/agent-hooks/tests/`.

### Shell smoke test (`Resources/agent-hooks/tests/smoke.sh`)

End-to-end invocation using a Unix-socket echo server (Python `socat`-equivalent): run `agent-hook.sh` four times (prompt/pretool/posttool/stop) with handcrafted JSON payloads; assert the socket received 3 messages (prompt + pretool + stop; posttool doesn't emit); assert session file is empty at the end.

### Manual integration (deferred to verification phase)

Matrix for user: zsh + claude, zsh + codex (flag on), zsh + codex (flag off), zsh + opencode. Each runs: simple success turn, turn with tool error, Ctrl-C mid-turn. Confirm icon colors, tooltips, and `~/Library/Caches/mux0/agent-sessions.json` content at each step.

## Edge Cases

| Case | Behavior |
|------|----------|
| Agent process SIGKILL'd mid-turn | Session entry stays. GC removes it after 1h. Icon frozen on last state until next action. |
| Malformed hook JSON | Python returns empty dict; dispatch runs with defaults; no emit if subcommand produces nothing. No crash. |
| Transcript file missing | `read_transcript_summary` returns `""`; payload omits `summary`; tooltip falls back to prefix-only form. |
| Socket write fails | Silent (existing pattern in `hook-emit.sh`). |
| Session file corrupt | `load_sessions` returns default empty doc; next write replaces with valid structure. |
| Same terminal, new Claude invocation | New session_id → new entry, old one GC'd or explicitly popped by its own Stop. |
| Multiple hooks fire concurrently | `flock(LOCK_EX)` serializes writes; reads take `LOCK_SH`. |
| mux0 app not running when hook fires | Socket connect fails → silent drop → session file still updates → next app start sees real-time events from next hook fire. |

## Backwards Compatibility

- `HookMessage` new fields are optional → existing shell messages decode unchanged
- `TerminalStatus` new associated values default to `.shell` / `nil` → no existing call site breaks
- Old `hook-emit.sh` paths (Notification, SessionStart, SessionEnd) untouched
- Users who don't upgrade the wrapper keep the old running/idle behavior

## File Map

**New:**
- `Resources/agent-hooks/agent-hook.sh` (bash entry)
- `Resources/agent-hooks/agent-hook.py` (python logic)
- `Resources/agent-hooks/tests/__init__.py`
- `Resources/agent-hooks/tests/test_agent_hook.py`
- `Resources/agent-hooks/tests/smoke.sh`
- `mux0Tests/TerminalStatusIconViewTests.swift`

**Modified:**
- `mux0/Models/HookMessage.swift` (+ `toolDetail`, `summary`, `Agent.displayName`)
- `mux0/Models/TerminalStatus.swift` (extend `.running` / `.success` / `.failed` associated values)
- `mux0/Models/TerminalStatusStore.swift` (extend `setRunning` / `setFinished` params)
- `mux0/Theme/TerminalStatusIconView.swift` (tooltip only — render unchanged)
- `mux0/ContentView.swift` (route `toolDetail` into setRunning; `summary`+`agent` into setFinished)
- `mux0Tests/HookMessageTests.swift`
- `mux0Tests/TerminalStatusStoreTests.swift`
- `mux0Tests/TerminalStatusTests.swift` (update Equatable expectations where needed)
- `Resources/agent-hooks/claude-wrapper.sh` (hooks.json routes new events to agent-hook.sh)
- `Resources/agent-hooks/codex-wrapper.sh` (same)
- `Resources/agent-hooks/opencode-plugin/mux0-status.js` (in-memory turn state + new emit fields)
- `docs/agent-hooks.md` (document new wire fields, session file, per-agent flow)

**Not touched:** `HookSocketListener.swift` (decoder handles optional fields natively), icon render path, sidebar/tab views.

## Implementation Order (for writing-plans)

1. Swift: extend `HookMessage` + tests (decoder accepts new fields)
2. Swift: extend `TerminalStatus` + `TerminalStatusStore` + tests (setRunning detail, setFinished agent+summary)
3. Swift: extend `TerminalStatusIconView.tooltipText` + new test file
4. Swift: route `toolDetail` + `agent` + `summary` in `ContentView.swift`
5. Python: `agent-hook.py` + unit tests
6. Shell: `agent-hook.sh` entry + smoke test
7. Wrappers: `claude-wrapper.sh` + `codex-wrapper.sh` updated hooks.json
8. Plugin: `mux0-status.js` in-memory turn state
9. Docs: `agent-hooks.md`
10. User-run manual verification matrix (not a code task)

Each step has its own unit tests and can land as its own commit.

## Completion Criteria

- Swift test suite: all existing 103 tests + new tests pass
- Python pytest: all tests green
- Smoke test: exits 0
- Manual matrix: all rows produce expected icon + tooltip behavior
- `docs/agent-hooks.md` describes the new fields and session file
- `./scripts/check-doc-drift.sh` clean

## Out of Scope for Later

- Sidebar row subtitle showing `currentToolDetail` live (would need a new view + environment hookup)
- MCP tool description coverage (currently only Claude/OpenCode built-in tools)
- OpenCode summary (needs accumulation logic from `message.appended`)
- Notification tooltip enhancement (Claude's Notification hook carries an attention reason; could surface it as "Claude: waiting for your review of …")
- Tab breadcrumb or a floating HUD showing agent activity across multiple terminals
