#!/usr/bin/env bash
# lib/title.sh - Terminal title management

# Prevent double-sourcing
[[ -n "${_CCP_TITLE_SOURCED:-}" ]] && return
_CCP_TITLE_SOURCED=1

# Set terminal title (works on iTerm2, Terminal.app, tmux, and others)
set_title() {
    local title="$1"

    # Standard xterm/VT100 escape sequence - works in most terminals
    printf '\033]0;%s\007' "${title}"

    # tmux: pass the escape through the tmux passthrough sequence
    if [[ -n "${TMUX:-}" ]]; then
        printf '\033Ptmux;\033\033]0;%s\007\033\\' "${title}"
        tmux set-window-option -q automatic-rename off 2>/dev/null || true
        tmux rename-window "${title}" 2>/dev/null || true
    fi
}

# update_title_with_context: combine base title with a status context string
update_title_with_context() {
    local base_title="$1"
    local context="${2:-}"

    if [[ -n "${context}" ]]; then
        set_title "${base_title} | ${context}"
    else
        set_title "${base_title}"
    fi
}

export -f set_title
export -f update_title_with_context
