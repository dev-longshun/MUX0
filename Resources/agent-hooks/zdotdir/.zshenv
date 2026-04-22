# mux0 shim .zshenv — installed via ZDOTDIR hijack in GhosttyBridge.
# Three jobs:
#   1. Restore ZDOTDIR to user's original so zsh's subsequent .zprofile / .zshrc
#      / .zlogin lookups resolve to the user's real config dir (not our bundle).
#   2. Source the user's real .zshenv (which was short-circuited by the hijack).
#   3. Schedule bootstrap.zsh to run once at first prompt, AFTER .zshrc, so we
#      append to user's preexec/precmd arrays rather than being overwritten.

# ---- 1. Restore ZDOTDIR ----
if [ -n "${MUX0_ORIG_ZDOTDIR+X}" ]; then
    # User had a ZDOTDIR before; put it back.
    export ZDOTDIR="$MUX0_ORIG_ZDOTDIR"
    unset MUX0_ORIG_ZDOTDIR
else
    # User had no ZDOTDIR; unset ours so zsh falls back to $HOME.
    unset ZDOTDIR
fi

# ---- 2. Source user's real .zshenv ----
# (zsh won't re-read .zshenv after we change ZDOTDIR, so do it explicitly.)
_mux0_user_zshenv="${ZDOTDIR:-$HOME}/.zshenv"
if [ -r "$_mux0_user_zshenv" ]; then
    source "$_mux0_user_zshenv"
fi
unset _mux0_user_zshenv

# ---- 3. Defer bootstrap to first prompt (interactive only) ----
if [[ -o interactive ]] && [ -n "$MUX0_AGENT_HOOKS_DIR" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null

    _mux0_bootstrap_first_prompt() {
        # Guard against re-firing. bootstrap.zsh has its own idempotency too,
        # but this also unregisters the hook so we don't incur its cost each prompt.
        if [ -f "$MUX0_AGENT_HOOKS_DIR/bootstrap.zsh" ]; then
            source "$MUX0_AGENT_HOOKS_DIR/bootstrap.zsh"
        fi
        add-zsh-hook -d precmd _mux0_bootstrap_first_prompt 2>/dev/null
        unfunction _mux0_bootstrap_first_prompt 2>/dev/null
    }

    # Only register if add-zsh-hook is available (i.e., zsh functions system loaded).
    if (( $+functions[add-zsh-hook] )); then
        add-zsh-hook precmd _mux0_bootstrap_first_prompt
    fi
fi
