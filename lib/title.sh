#!/usr/bin/env bash
# lib/title.sh - Terminal title management

# Prevent double-sourcing
[[ -n "${_CCP_TITLE_SOURCED:-}" ]] && return
_CCP_TITLE_SOURCED=1

# Set terminal title — per-pane icon name (OSC 1) on iTerm2/modern terminals,
# window title (OSC 2) on Terminal.app which ignores OSC 1.
set_title() {
    local title="$1"

    if [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
        printf '\033]1;\007'
        printf '\033]2;%s\007' "${title}"
    else
        printf '\033]1;%s\007' "${title}"
        printf '\033]2;\007'
    fi

    if [[ -n "${TMUX:-}" ]]; then
        # shellcheck disable=SC1003
        printf '\033Ptmux;\033\033]1;%s\007\033\\' "${title}"
        printf '\033Ptmux;\033\033]2;\007\033\\'
        tmux set-window-option -q automatic-rename off 2>/dev/null || true
        tmux rename-window "${title}" 2>/dev/null || true
    fi

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

    if [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
        # Terminal.app only renders the window title (OSC 2)
        printf '\033]1;\007'
        printf '\033]2;%s\007' "${display}"
    else
        # iTerm2, Kitty, WezTerm, etc.: OSC 1 drives the per-pane title bar
        printf '\033]1;%s\007' "${display}"
        printf '\033]2;\007'   # clear window title — don't touch the app title bar
    fi

    if [[ -n "${TMUX:-}" ]]; then
        # shellcheck disable=SC1003
        printf '\033Ptmux;\033\033]1;%s\007\033\\' "${display}"
        printf '\033Ptmux;\033\033]2;\007\033\\'
        tmux set-window-option -q automatic-rename off 2>/dev/null || true
        tmux rename-window "${display}" 2>/dev/null || true
    fi

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
            if ! [[ "${width}" =~ ^[0-9]+$ ]] || [[ "${width}" -le 0 ]]; then
                width=80
            fi
        fi
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
