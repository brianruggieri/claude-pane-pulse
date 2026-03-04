#!/usr/bin/env bash
# lib/title.sh - Terminal title management

# Prevent double-sourcing
[[ -n "${_CCP_TITLE_SOURCED:-}" ]] && return
_CCP_TITLE_SOURCED=1

# detect_terminal_backend: probe the environment and set CCP_TERMINAL_BACKEND.
# Called once at source time.  Tests can override CCP_TERMINAL_BACKEND directly.
#
# Backend → write strategy:
#   iterm2 / wezterm / osc1  → OSC 1 (per-pane icon name) + clear OSC 2
#   apple-terminal / ghostty / osc2 → OSC 2 (window title) + clear OSC 1
#   kitty                    → kitty @ set-window-title (falls back to OSC 1)
#
# tmux passthrough is layered on top by _ccp_write_title() regardless of backend:
# when $TMUX is set, DCS passthrough sequences + tmux rename-window are always emitted.
detect_terminal_backend() {
    if [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
        CCP_TERMINAL_BACKEND="iterm2"
    elif [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
        CCP_TERMINAL_BACKEND="apple-terminal"
    elif [[ "${TERM_PROGRAM:-}" == "WezTerm" ]]; then
        CCP_TERMINAL_BACKEND="wezterm"
    elif [[ "${TERM_PROGRAM:-}" == "ghostty" ]]; then
        CCP_TERMINAL_BACKEND="ghostty"
    elif [[ -n "${KITTY_PID:-}" || "${TERM_PROGRAM:-}" == "kitty" ]]; then
        CCP_TERMINAL_BACKEND="kitty"
    else
        # Default: OSC 1 — works in iTerm2 (unset TERM_PROGRAM) and most modern terminals
        CCP_TERMINAL_BACKEND="osc1"
    fi
    export CCP_TERMINAL_BACKEND
}

# _ccp_write_title: private dispatch — write title to the detected terminal backend.
# Always adds tmux DCS passthrough + rename-window when $TMUX is set.
_ccp_write_title() {
    local title="$1"

    case "${CCP_TERMINAL_BACKEND:-osc1}" in
        iterm2|wezterm|osc1)
            printf '\033]1;%s\007' "${title}"
            printf '\033]2;\007'
            ;;
        apple-terminal|ghostty|osc2)
            printf '\033]1;\007'
            printf '\033]2;%s\007' "${title}"
            ;;
        kitty)
            if command -v kitty &>/dev/null 2>&1; then
                kitty @ set-window-title "${title}" 2>/dev/null || true
            else
                printf '\033]1;%s\007' "${title}"
                printf '\033]2;\007'
            fi
            ;;
        *)
            printf '\033]1;%s\007' "${title}"
            printf '\033]2;\007'
            ;;
    esac

    # tmux: add DCS passthrough + rename-window so the title propagates to the
    # outer terminal even when the backend already handled it above.
    if [[ -n "${TMUX:-}" ]]; then
        # shellcheck disable=SC1003
        printf '\033Ptmux;\033\033]1;%s\007\033\\' "${title}"
        printf '\033Ptmux;\033\033]2;\007\033\\'
        tmux set-window-option -q automatic-rename off 2>/dev/null || true
        tmux rename-window "${title}" 2>/dev/null || true
    fi
}

# set_title: set the terminal title to a static string.
set_title() {
    local title="$1"
    _ccp_write_title "${title}"

    if [[ -n "${CCP_TITLE_LOG:-}" ]]; then
        mkdir -p -- "$(dirname -- "${CCP_TITLE_LOG}")" 2>/dev/null || true
        echo "${title}" >> "${CCP_TITLE_LOG}" 2>/dev/null || true
    fi
}

# update_title_with_context: update the per-pane title with dynamic status.
#
# CORE PRINCIPLE: ccp only touches terminal titles — it never writes to
# stdout/stderr or modifies Claude's output in any way.
#
# When context is provided it becomes the full display string (the base_title
# is embedded in the prefix that title_updater builds before calling here).
# When context is empty the base_title is shown directly.
update_title_with_context() {
    local base_title="$1"
    local context="${2:-}"

    local display
    if [[ -n "${context}" ]]; then
        display="${context}"
    else
        display="${base_title}"
    fi

    _ccp_write_title "${display}"

    if [[ -n "${CCP_TITLE_LOG:-}" ]]; then
        mkdir -p -- "$(dirname -- "${CCP_TITLE_LOG}")" 2>/dev/null || true
        if [[ -n "${context}" ]]; then
            printf '%s | %s\n' "${base_title}" "${context}" >> "${CCP_TITLE_LOG}" 2>/dev/null || true
        else
            printf '%s\n' "${base_title}" >> "${CCP_TITLE_LOG}" 2>/dev/null || true
        fi
    fi
}

# Detect backend at source time (tests can override CCP_TERMINAL_BACKEND after sourcing)
detect_terminal_backend

export -f detect_terminal_backend
export -f _ccp_write_title
export -f set_title
export -f update_title_with_context
