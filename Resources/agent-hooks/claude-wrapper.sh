#!/bin/bash
# claude-wrapper.sh — launch Claude Code with mux0 lifecycle hooks injected.
# Written for mux0 from scratch; do not redistribute without verifying license compat.
# Reads MUX0_AGENT_HOOKS_DIR, MUX0_HOOK_SOCK, MUX0_TERMINAL_ID from env.

set -e

# DEBUG: sentinel to confirm wrapper actually gets invoked.
{
    echo "[$(date +%s)] [claude-wrapper] invoked: args=$*  MUX0_AGENT_HOOKS_DIR=${MUX0_AGENT_HOOKS_DIR:+set}  MUX0_HOOK_SOCK=${MUX0_HOOK_SOCK:+set}  MUX0_TERMINAL_ID=${MUX0_TERMINAL_ID:+set}"
} >> "$HOME/Library/Caches/mux0/hook-emit.log" 2>/dev/null || true

# Find the real claude binary: skip any shell function / wrapper and the mux0 wrapper itself.
# Strategy: try MUX0_REAL_CLAUDE env override first; else walk PATH.
REAL_CLAUDE=""
if [ -n "$MUX0_REAL_CLAUDE" ] && [ -x "$MUX0_REAL_CLAUDE" ]; then
    REAL_CLAUDE="$MUX0_REAL_CLAUDE"
else
    for candidate in $(which -a claude 2>/dev/null); do
        # Resolve symlinks and skip our own wrapper path
        resolved=$(readlink -f "$candidate" 2>/dev/null || echo "$candidate")
        case "$resolved" in
            *mux0*agent-hooks*claude-wrapper*) continue ;;
        esac
        REAL_CLAUDE="$candidate"
        break
    done
fi

if [ -z "$REAL_CLAUDE" ]; then
    echo "mux0 claude-wrapper: real 'claude' binary not found in PATH" >&2
    echo "  hint: install Claude Code, or set MUX0_REAL_CLAUDE to its path" >&2
    exit 127
fi

# If mux0 env is missing (e.g. user ran this wrapper outside mux0), passthrough.
if [ -z "$MUX0_AGENT_HOOKS_DIR" ] || [ -z "$MUX0_HOOK_SOCK" ] || [ -z "$MUX0_TERMINAL_ID" ]; then
    exec "$REAL_CLAUDE" "$@"
fi

EMIT="$MUX0_AGENT_HOOKS_DIR/hook-emit.sh"
AGENT_HOOK="$MUX0_AGENT_HOOKS_DIR/agent-hook.sh"

# Build Claude Code --settings JSON.
# Schema (Claude Code v2): each event → array of hook-groups; each group has
# an empty matcher and a nested hooks array with {type, command} entries.
# Flat {"command": "..."} silently fails to parse — the nested shape is required.
#
# Four events (UserPromptSubmit / PreToolUse / PostToolUse / Stop) route to
# agent-hook.sh for stateful turn tracking (reads hook payload JSON from
# stdin, maintains per-session error flag, emits finished + summary at Stop).
# SessionStart / SessionEnd / Notification stay on hook-emit.sh — they just
# send a bare state event, no stdin parsing needed.
SETTINGS_JSON=$(cat <<EOF
{
  "hooks": {
    "SessionStart":     [{"matcher": "", "hooks": [{"type": "command", "command": "$EMIT idle claude"}]}],
    "UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": "$AGENT_HOOK prompt claude"}]}],
    "PreToolUse":       [{"matcher": "", "hooks": [{"type": "command", "command": "$AGENT_HOOK pretool claude"}]}],
    "PostToolUse":      [{"matcher": "", "hooks": [{"type": "command", "command": "$AGENT_HOOK posttool claude"}]}],
    "Stop":             [{"matcher": "", "hooks": [{"type": "command", "command": "$AGENT_HOOK stop claude"}]}],
    "Notification":     [{"matcher": "", "hooks": [{"type": "command", "command": "$EMIT needsInput claude"}]}],
    "SessionEnd":       [{"matcher": "", "hooks": [{"type": "command", "command": "$EMIT idle claude"}]}]
  }
}
EOF
)

# DEBUG: log the full claude invocation we're about to exec.
{
    echo "[$(date +%s)] [claude-wrapper] execing: $REAL_CLAUDE --settings <json> $*"
    echo "[$(date +%s)] [claude-wrapper] SETTINGS_JSON=$SETTINGS_JSON"
} >> "$HOME/Library/Caches/mux0/hook-emit.log" 2>/dev/null || true

# --settings merges with user's own settings.json (don't disable those with
# --setting-sources — would break user's model/tool config). If the user has
# their own hooks for the same events, both fire; that's fine.
exec "$REAL_CLAUDE" --settings "$SETTINGS_JSON" "$@"
