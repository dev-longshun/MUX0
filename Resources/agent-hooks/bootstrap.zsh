# bootstrap.zsh — source this from ~/.zshrc to enable mux0 status hooks.
# Example: [ -f "$MUX0_AGENT_HOOKS_DIR/bootstrap.zsh" ] && source "$MUX0_AGENT_HOOKS_DIR/bootstrap.zsh"
[ -z "$MUX0_AGENT_HOOKS_DIR" ] && return 0
source "$MUX0_AGENT_HOOKS_DIR/agent-functions.zsh" 2>/dev/null
