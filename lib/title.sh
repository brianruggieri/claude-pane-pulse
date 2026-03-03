#!/usr/bin/env bash
# lib/title.sh - Terminal title management

# Prevent double-sourcing
[[ -n "${_CCP_TITLE_SOURCED:-}" ]] && return
_CCP_TITLE_SOURCED=1

detect_terminal_backend() {
    local backend="osc2"

    if [[ -n "${TMUX:-}" ]]; then
        local tmux_major=0 tmux_minor=0 tmux_version
        tmux_version=$(tmux -V 2>/dev/null | awk '{print $2}')
        if [[ "${tmux_version}" =~ ^([0-9]+)\.([0-9]+) ]]; then
            tmux_major="${BASH_REMATCH[1]}"
            tmux_minor="${BASH_REMATCH[2]}"
        fi
        if [[ "${tmux_major}" -gt 2 || ( "${tmux_major}" -eq 2 && "${tmux_minor}" -ge 9 ) ]]; then
            backend="tmux-pane"
        else
            backend="tmux-window"
        fi
    elif [[ "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then
        backend="iterm2"
    elif [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
        backend="apple-terminal"
    elif [[ "${TERM_PROGRAM:-}" == "kitty" || -n "${KITTY_PID:-}" ]]; then
        if command -v kitty >/dev/null 2>&1; then
            backend="kitty"
        else
            backend="osc1"
        fi
    elif [[ "${TERM_PROGRAM:-}" == "WezTerm" ]]; then
        backend="wezterm"
    elif [[ "${TERM_PROGRAM:-}" == "ghostty" ]]; then
        backend="ghostty"
    fi

    CCP_TERMINAL_BACKEND="${backend}"
    export CCP_TERMINAL_BACKEND
}

_ccp_write_title() {
    local title="$1"

    case "${CCP_TERMINAL_BACKEND:-osc2}" in
        iterm2|wezterm|osc1)
            printf '\033]1;%s\007' "${title}"
            printf '\033]2;\007'
            ;;
        apple-terminal|ghostty|osc2)
            printf '\033]1;\007'
            printf '\033]2;%s\007' "${title}"
            ;;
        kitty)
            if command -v kitty >/dev/null 2>&1; then
                kitty @ set-window-title "${title}" 2>/dev/null || true
            else
                printf '\033]1;%s\007' "${title}"
                printf '\033]2;\007'
            fi
            ;;
        tmux-pane)
            tmux set-window-option -q automatic-rename off 2>/dev/null || true
            if [[ -n "${TMUX_PANE:-}" ]]; then
                tmux select-pane -T "${title}" -t "${TMUX_PANE}" 2>/dev/null || true
            else
                tmux rename-window "${title}" 2>/dev/null || true
            fi
            # shellcheck disable=SC1003
            printf '\033Ptmux;\033\033]1;%s\007\033\\' "${title}"
            # shellcheck disable=SC1003
            printf '\033Ptmux;\033\033]2;\007\033\\'
            ;;
        tmux-window)
            tmux set-window-option -q automatic-rename off 2>/dev/null || true
            tmux rename-window "${title}" 2>/dev/null || true
            # shellcheck disable=SC1003
            printf '\033Ptmux;\033\033]1;%s\007\033\\' "${title}"
            # shellcheck disable=SC1003
            printf '\033Ptmux;\033\033]2;\007\033\\'
            ;;
        *)
            printf '\033]1;\007'
            printf '\033]2;%s\007' "${title}"
            ;;
    esac
}

set_title() {
    local title="$1"
    _ccp_write_title "${title}"

    # CCP_TITLE_LOG: append each title to a log file (used by e2e tests).
    # Use || true so a bad/unwritable path never terminates ccp under set -e.
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
# OSC escape sequences:
#   \033]1; = icon name  → per-pane title bar in iTerm2 split-pane view
#   \033]2; = window title → app-level macOS title bar (shared across all panes)
#
# We write the full dynamic content to OSC 1 so each pane shows its own
# independent status.  We clear OSC 2 so ccp doesn't pollute the app-level
# title bar (each pane owns only its own pane title, not the whole window).
#
# Terminal.app exception: it ignores OSC 1 and only renders OSC 2, so we
# fall back to writing the window title there.
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

# format_title_prefix: build "project (branch) | " with size-aware truncation.
# Branch name gets slight priority (more chars) over project name.
#
# Usage: format_title_prefix project branch [pane_width]
#   pane_width defaults to $COLUMNS, then tput cols, then 80.
format_title_prefix() {
    local proj="${1:-}"
    local branch="${2:-}"
    local width="${3:-}"

    # Detect terminal width when not explicitly provided
    if [[ -z "${width}" ]]; then
        width="${COLUMNS:-0}"
        if ! [[ "${width}" =~ ^[0-9]+$ ]] || [[ "${width}" -le 0 ]]; then
            width=$(tput cols 2>/dev/null || echo "")
        fi
    fi

    # Normalize: coerce non-numeric or non-positive values to the fallback
    if ! [[ "${width}" =~ ^[0-9]+$ ]] || [[ "${width}" -le 0 ]]; then
        width=80
    fi

    # Ensure a sensible minimum width
    [[ "${width}" -lt 20 ]] && width=20

    [[ -z "${proj}" ]] && echo "" && return

    if [[ -z "${branch}" ]]; then
        # No branch: reserve 30 chars for status/context, 3 for " | "
        local budget=$(( width - 33 ))
        [[ "${budget}" -lt 4 ]] && budget=4
        [[ "${#proj}" -gt "${budget}" ]] && proj="${proj:0:$(( budget - 1 ))}…"
        echo "${proj} | "
        return
    fi

    # With branch: " () | " overhead = 6; reserve 30 for status/context
    local budget=$(( width - 36 ))
    [[ "${budget}" -lt 8 ]] && budget=8

    # Branch gets 55% of budget (slight priority), project gets 45%
    # The + 50 implements rounding (integer arithmetic: (n*55 + 50) / 100 ≈ round(n*0.55))
    local branch_max=$(( (budget * 55 + 50) / 100 ))
    local proj_max=$(( budget - branch_max ))
    [[ "${branch_max}" -lt 4 ]] && branch_max=4
    [[ "${proj_max}" -lt 4 ]] && proj_max=4

    # Donate unused quota from a short name to the other
    if [[ "${#proj}" -lt "${proj_max}" && "${#branch}" -gt "${branch_max}" ]]; then
        branch_max=$(( branch_max + proj_max - ${#proj} ))
    elif [[ "${#branch}" -lt "${branch_max}" && "${#proj}" -gt "${proj_max}" ]]; then
        proj_max=$(( proj_max + branch_max - ${#branch} ))
    fi

    [[ "${#proj}" -gt "${proj_max}" ]] && proj="${proj:0:$(( proj_max - 1 ))}…"
    [[ "${#branch}" -gt "${branch_max}" ]] && branch="${branch:0:$(( branch_max - 1 ))}…"

    echo "${proj} (${branch}) | "
}

export -f set_title
export -f update_title_with_context
export -f format_title_prefix
export -f detect_terminal_backend

detect_terminal_backend
