#!/bin/bash
# codex-wrapper.sh — launch OpenAI Codex CLI with mux0 notify + experimental hooks.
# Written from scratch for mux0.

set -e

REAL_CODEX=""
if [ -n "$MUX0_REAL_CODEX" ] && [ -x "$MUX0_REAL_CODEX" ]; then
    REAL_CODEX="$MUX0_REAL_CODEX"
else
    for candidate in $(which -a codex 2>/dev/null); do
        resolved=$(readlink -f "$candidate" 2>/dev/null || echo "$candidate")
        case "$resolved" in
            *mux0*agent-hooks*codex-wrapper*) continue ;;
        esac
        REAL_CODEX="$candidate"
        break
    done
fi

if [ -z "$REAL_CODEX" ]; then
    echo "mux0 codex-wrapper: real 'codex' binary not found in PATH" >&2
    echo "  hint: install OpenAI Codex CLI, or set MUX0_REAL_CODEX" >&2
    exit 127
fi

# Passthrough when mux0 env is missing.
if [ -z "$MUX0_AGENT_HOOKS_DIR" ] || [ -z "$MUX0_HOOK_SOCK" ] || [ -z "$MUX0_TERMINAL_ID" ]; then
    exec "$REAL_CODEX" "$@"
fi

EMIT="$MUX0_AGENT_HOOKS_DIR/hook-emit.sh"
AGENT_HOOK="$MUX0_AGENT_HOOKS_DIR/agent-hook.sh"

# Create an overlay CODEX_HOME so we don't mutate the user's real config.
OVERLAY=$(mktemp -d -t mux0-codex.XXXXXX)

# Build overlay config.toml: our top-level keys FIRST, then user's original.
# Reason: TOML has no way to "close" a [section]; once inside one, subsequent
# keys are scoped to it. Appending `notify = [...]` after a user section like
# [notice.model_migrations] makes codex parse it as a sub-key of that section.
# Putting our keys before any user [section] keeps them at the top level.
USER_HOME="${CODEX_HOME:-$HOME/.codex}"
{
    echo "# --- mux0 hooks (prepended by codex-wrapper.sh; overlay only, user config untouched) ---"
    echo "notify = [\"$EMIT\", \"idle\", \"codex\"]"
    echo
    if [ -f "$USER_HOME/config.toml" ]; then
        cat "$USER_HOME/config.toml"
    fi
} > "$OVERLAY/config.toml"

# Symlink remaining files/dirs (sessions, caches) so codex finds persistent state.
if [ -d "$USER_HOME" ]; then
    for item in "$USER_HOME"/*; do
        [ -e "$item" ] || continue
        name=$(basename "$item")
        case "$name" in
            config.toml) continue ;;
            hooks.json)  continue ;;   # we override this below
        esac
        ln -sfn "$item" "$OVERLAY/$name"
    done
fi

# Write experimental hooks.json. If the user hasn't enabled features.codex_hooks,
# this file is silently ignored by Codex — no harm done.
#
# Schema: Codex uses the same nested shape as Claude Code. Each event maps to
# an array of matcher-groups; each group has a `hooks` array of {type, command}.
# The parser uses serde's deny_unknown_fields, so any stray key (or the flat
# {"command": "..."} shape) causes Codex to silently skip the entire file.
# Source: codex-rs/hooks/src/engine/config.rs.
cat > "$OVERLAY/hooks.json" <<EOF
{
  "hooks": {
    "SessionStart":     [{"hooks": [{"type": "command", "command": "$EMIT idle codex"}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "$AGENT_HOOK prompt codex"}]}],
    "PreToolUse":       [{"hooks": [{"type": "command", "command": "$AGENT_HOOK pretool codex"}]}],
    "PostToolUse":      [{"hooks": [{"type": "command", "command": "$AGENT_HOOK posttool codex"}]}],
    "Stop":             [{"hooks": [{"type": "command", "command": "$AGENT_HOOK stop codex"}]}]
  }
}
EOF

# Point Codex at the overlay.
export CODEX_HOME="$OVERLAY"

# Clean up on exit (normal, interrupt, or crash).
# Also mark the terminal idle on exit — otherwise the precmd hook has to fire
# before the icon updates, which can lag if the user closes the window.
cleanup() {
    rm -rf "$OVERLAY" 2>/dev/null || true
    "$EMIT" idle codex 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Emit idle BEFORE exec: shell preexec already marked us running when the user
# typed `codex`, but codex's own `notify` only fires on turn completion, and
# hooks.json requires features.codex_hooks. Without this, the UI sits on
# "running" from launch until the first turn completes — which is wrong,
# since codex is actually idle at its input prompt.
"$EMIT" idle codex 2>/dev/null || true

exec "$REAL_CODEX" "$@"
