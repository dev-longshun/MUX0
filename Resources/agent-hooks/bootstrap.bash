# bootstrap.bash — source this from ~/.bashrc to enable mux0 status hooks.
# Example: [ -f "$MUX0_AGENT_HOOKS_DIR/bootstrap.bash" ] && source "$MUX0_AGENT_HOOKS_DIR/bootstrap.bash"
[ -z "$MUX0_AGENT_HOOKS_DIR" ] && return 0
source "$MUX0_AGENT_HOOKS_DIR/agent-functions.bash" 2>/dev/null
