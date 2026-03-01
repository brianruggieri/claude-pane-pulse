#!/usr/bin/env bash
# lib/title.sh - Terminal title and tmux pane border management

# Prevent double-sourcing
[[ -n "${_CCP_TITLE_SOURCED:-}" ]] && return
_CCP_TITLE_SOURCED=1

# set_title: update the terminal/tmux window title
set_title() {
    local title="$1"

    # Standard xterm/VT100 escape sequence - works in most terminals
    printf '\033]0;%s\007' "${title}"

    # tmux: pass the escape through the tmux passthrough sequence
    if [[ -n "${TMUX:-}" ]]; then
        # shellcheck disable=SC1003
        printf '\033Ptmux;\033\033]0;%s\007\033\\' "${title}"
        tmux set-window-option -q automatic-rename off 2>/dev/null || true
        tmux rename-window "${title}" 2>/dev/null || true
    fi

    # CCP_TITLE_LOG: append each title to a log file (used by e2e tests)
    if [[ -n "${CCP_TITLE_LOG:-}" ]]; then
        echo "${title}" >> "${CCP_TITLE_LOG}"
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

# ---------------------------------------------------------------------------
# tmux pane border coloring (no-op when not in tmux)
#
# Border color semantics:
#   Error / Tests failed  → red      (something went wrong, needs attention)
#   Waiting               → yellow   (blocked, needs user input)
#   Tests passed / Done   → green    (work completed successfully)
#   Active ops / idle     → default  (clear any previous color)
# ---------------------------------------------------------------------------

# update_pane_border: set pane border color based on the current context string
update_pane_border() {
    [[ -z "${TMUX:-}" ]] && return
    local context="${1:-}"

    if [[ "${context}" =~ (Error|Tests\ failed) ]]; then
        _ccp_set_border "red"
    elif [[ "${context}" =~ Waiting ]]; then
        _ccp_set_border "yellow"
    elif [[ "${context}" =~ (Tests\ passed|Committed) ]]; then
        _ccp_set_border "green"
    else
        # Active operations, idle, or no context: restore to default
        _ccp_restore_border
    fi
}

# restore_pane_border: restore original border style (called on session exit)
restore_pane_border() {
    [[ -z "${TMUX:-}" ]] && return
    _ccp_restore_border
}

# _ccp_set_border: save the original border style once, then apply a color.
# Uses STATE_DIR/border_orig.$$.txt as a cross-subshell communication file.
_ccp_set_border() {
    local color="$1"
    local save_file="${STATE_DIR}/border_orig.$$.txt"
    if [[ ! -f "${save_file}" ]]; then
        local orig
        orig=$(tmux show-options -pqv pane-active-border-style 2>/dev/null || echo "")
        printf '%s' "${orig}" > "${save_file}"
    fi
    tmux select-pane -P "pane-active-border-style=fg=${color}" 2>/dev/null || true
}

# _ccp_restore_border: restore the saved border style and clean up the save file.
# Safe to call multiple times (idempotent: no-op if save file doesn't exist).
_ccp_restore_border() {
    local save_file="${STATE_DIR}/border_orig.$$.txt"
    [[ ! -f "${save_file}" ]] && return
    local orig
    orig=$(cat "${save_file}" 2>/dev/null || echo "")
    if [[ -n "${orig}" ]]; then
        tmux select-pane -P "pane-active-border-style=${orig}" 2>/dev/null || true
    else
        tmux select-pane -P "pane-active-border-style=default" 2>/dev/null || true
    fi
    rm -f "${save_file}"
}

export -f set_title
export -f update_title_with_context
export -f update_pane_border
export -f restore_pane_border
export -f _ccp_set_border
export -f _ccp_restore_border
