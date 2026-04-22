# bootstrap.fish — source this from ~/.config/fish/config.fish to enable mux0 status hooks.
# Example:
#   if set -q MUX0_AGENT_HOOKS_DIR
#       source "$MUX0_AGENT_HOOKS_DIR/bootstrap.fish"
#   end
test -z "$MUX0_AGENT_HOOKS_DIR"; and return 0
test -f "$MUX0_AGENT_HOOKS_DIR/agent-functions.fish"; and source "$MUX0_AGENT_HOOKS_DIR/agent-functions.fish"
