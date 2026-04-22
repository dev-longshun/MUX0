# agent-functions.fish — override agent CLI names to point at our wrappers.
# Called by bootstrap.fish.
test -z "$MUX0_AGENT_HOOKS_DIR"; and return 0

function claude
    command "$MUX0_AGENT_HOOKS_DIR/claude-wrapper.sh" $argv
end

function opencode
    command "$MUX0_AGENT_HOOKS_DIR/opencode-wrapper.sh" $argv
end

function codex
    command "$MUX0_AGENT_HOOKS_DIR/codex-wrapper.sh" $argv
end
