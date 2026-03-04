#!/usr/bin/env bash
# lib/monitor.sh - Dynamic title monitoring with status priorities
# Prevent double-sourcing
[[ -n "${_CCP_MONITOR_SOURCED:-}" ]] && return
_CCP_MONITOR_SOURCED=1

# Source dependencies (safe: guarded against double-source)
_MONITOR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core.sh
source "${_MONITOR_SCRIPT_DIR}/core.sh"
# shellcheck source=lib/title.sh
source "${_MONITOR_SCRIPT_DIR}/title.sh"

# ── Status priority levels ────────────────────────────────────────────────────
# 🐛 Error          = 100
# ❌ Tests failed   = 90
# ⏸️ Awaiting approval = 88
# 🙋 Input needed   = 85
# 🔨 Building       = 80
# 🧪 Testing        = 80
# 📦 Installing     = 80
# ⬆️ Pushing        = 75
# ⬇️ Pulling        = 75
# 🔀 Merging        = 75
# 🐳 Docker         = 70
# 💭 Thinking       = 70  (structural: any ● line with trailing …)
# ✏️ Editing        = 65
# ✅ Tests passed   = 60
# 💾 Committed      = 60
# 🏁 Completed      = 60
# 🖥️ Running        = 55  (catch-all for unrecognised ● Bash() lines)
# 💤 Idle           = 10

# ── status_to_priority ────────────────────────────────────────────────────────
# Map a status string (as written by hook_runner.sh) to a priority integer.
status_to_priority() {
    local status="$1"
    if [[ "${status}" =~ "🐛 Error" ]]; then
        echo 100
    elif [[ "${status}" =~ "❌ Tests failed" ]]; then
        echo 90
    elif [[ "${status}" =~ "⏸️ Awaiting approval" ]]; then
        echo 88
    elif [[ "${status}" =~ "🙋 Input needed" ]]; then
        echo 85
    elif [[ "${status}" =~ (Building|Testing|Installing) ]]; then
        echo 80
    elif [[ "${status}" =~ (Pushing|Pulling|Merging) ]]; then
        echo 75
    elif [[ "${status}" =~ (Docker|Thinking|Delegating) ]]; then
        echo 70
    elif [[ "${status}" =~ "✏️ Editing" ]]; then
        echo 65
    elif [[ "${status}" =~ (Tests\ passed|Committed|Completed|Subagent\ finished) ]]; then
        echo 60
    elif [[ "${status}" =~ (Session\ started|Compacting|Subagent\ started|Teammate\ idle|Config\ changed|Worktree|Notification|Session\ ended) ]]; then
        echo 52
    elif [[ "${status}" =~ (Reading|Browsing|Running) ]]; then
        echo 55
    else
        echo 50
    fi
}

# ── animate_status ────────────────────────────────────────────────────────────
# Append a cycling spinner to active in-progress statuses.
# Used by tests; the hot path in title_updater inlines the same logic
# to avoid $() forks on every animation tick.
#
# Uses Claude Code's exact spinner characters in their correct ping-pong order.
# Source: reverse-engineered from raw terminal output; the original expression
# array is ["·","✻","✽","✶","✳","✢"] driven by a triangle-wave oscillator,
# producing a grow→shrink pulse rather than a one-way sweep.
#
# 10-frame ping-pong at ~0.15s/frame = 1.5s full cycle:
#   · ✻ ✽ ✶ ✳ ✢  ✳ ✶ ✽ ✻  (then back to ·)
#   0 1 2 3 4 5  6 7 8 9
animate_status() {
    local status="$1"
    local frame="$2"

    # Only animate operations still in progress (not completions or errors)
    if [[ "${status}" =~ (Building|Testing|Installing|Pushing|Pulling|Merging|Docker|Thinking|Editing|Running|Reading|Browsing|Delegating) || "${status}" =~ "✸" ]]; then
        local spinner=""
        case $((frame % 10)) in
            0) spinner="·" ;;   # U+00B7 MIDDLE DOT          — grow start
            1) spinner="✻" ;;   # U+273B TEARDROP-SPOKED ASTERISK
            2) spinner="✽" ;;   # U+273D HEAVY TEARDROP-SPOKED ASTERISK
            3) spinner="✶" ;;   # U+2736 SIX POINTED BLACK STAR
            4) spinner="✳" ;;   # U+2733 EIGHT-SPOKED ASTERISK
            5) spinner="✢" ;;   # U+2722 FOUR TEARDROP-SPOKED ASTERISK — peak
            6) spinner="✳" ;;   # U+2733                     — shrink
            7) spinner="✶" ;;   # U+2736
            8) spinner="✽" ;;   # U+273D
            9) spinner="✻" ;;   # U+273B
        esac
        echo "${status} ${spinner}"
    else
        echo "${status}"
    fi
}

title_updater() {
    local base_title="$1"

    (
        # keep the updater alive on non-zero checks/sleeps
        set +e

        local current_context=""
        local frame_counter=0
        local task_summary=""
        local clean_summary=""
        local prev_display_context=""
        local last_hook_check=$SECONDS
        local status_file="${CCP_STATUS_FILE:-}"
        local context_file="${CCP_CONTEXT_FILE:-}"

        local tick_interval="1"
        if [[ "${BASH_VERSINFO[0]:-3}" -ge 4 && -z "${TMUX:-}" ]]; then
            tick_interval="0.15"
        fi

        local title_prefix
        title_prefix=$(format_title_prefix "${CCP_PROJECT_NAME:-}" "${CCP_BRANCH_NAME:-}")

        # Assert base title once before Claude Code starts.
        update_title_with_context "${base_title}" ""

        while true; do
            sleep "${tick_interval}" || break

            [[ -n "${current_context}" ]] && frame_counter=$(( (frame_counter + 1) % 10 ))

            local current_time=$SECONDS
            if [[ $((current_time - last_hook_check)) -ge 1 ]]; then
                last_hook_check=$current_time

                local hook_status=""
                if [[ -n "${status_file}" && -f "${status_file}" ]]; then
                    hook_status=$(< "${status_file}") || hook_status=""
                fi

                if [[ -n "${hook_status}" ]]; then
                    if [[ "${hook_status}" != "${current_context}" ]]; then
                        current_context="${hook_status}"
                    fi
                else
                    current_context="💤 Idle"
                fi

                local new_summary=""
                if [[ -n "${context_file}" && -f "${context_file}" ]]; then
                    new_summary=$(< "${context_file}") || new_summary=""
                fi

                if [[ "${new_summary}" != "${task_summary}" ]]; then
                    task_summary="${new_summary}"
                    clean_summary="${task_summary}"
                    if [[ -n "${CCP_PROJECT_NAME:-}" && -n "${clean_summary}" ]]; then
                        clean_summary=$(printf '%s' "${clean_summary}" \
                            | sed "s/ (${CCP_PROJECT_NAME})[^,]*,\{0,1\}[[:space:]]*//g" \
                            | sed 's/^[[:space:]]*//' \
                            | sed 's/[[:space:]]*$//')
                    fi
                fi
            fi

            # Inline animation — no $() fork. Same ping-pong sequence as animate_status.
            local _spinner=""
            if [[ "${current_context}" =~ (Building|Testing|Installing|Pushing|Pulling|Merging|Docker|Thinking|Editing|Running|Reading|Browsing|Delegating) || "${current_context}" =~ "✸" ]]; then
                case $((frame_counter % 10)) in
                    0) _spinner="·"  ;;
                    1) _spinner="✻"  ;;
                    2) _spinner="✽"  ;;
                    3) _spinner="✶"  ;;
                    4) _spinner="✳"  ;;
                    5) _spinner="✢"  ;;
                    6) _spinner="✳"  ;;
                    7) _spinner="✶"  ;;
                    8) _spinner="✽"  ;;
                    9) _spinner="✻"  ;;
                esac
            fi

            local display_content=""
            if [[ -n "${clean_summary}" && -n "${current_context}" ]]; then
                display_content="${clean_summary} | ${current_context}"
            elif [[ -n "${clean_summary}" ]]; then
                display_content="${clean_summary}"
            elif [[ -n "${current_context}" ]]; then
                display_content="${current_context}"
            fi

            local _body=""
            if [[ -n "${title_prefix}" && -n "${display_content}" ]]; then
                _body="${title_prefix}${display_content}"
            elif [[ -n "${title_prefix}" ]]; then
                _body="${title_prefix%' | '}"
            else
                _body="${display_content}"
            fi

            local display_context=""
            if [[ -n "${_spinner}" && -n "${_body}" ]]; then
                display_context="${_spinner} ${_body}"
            else
                display_context="${_body}"
            fi

            if [[ "${display_context}" != "${prev_display_context}" ]]; then
                update_title_with_context "${base_title}" "${display_context}"
                prev_display_context="${display_context}"
            fi
        done
    ) &

    local monitor_pid=$!
    echo "${monitor_pid}" > "${STATE_DIR}/monitor.$$.pid"
}

cleanup_monitor() {
    local monitor_pid_file="${STATE_DIR}/monitor.$$.pid"
    if [[ -f "${monitor_pid_file}" ]]; then
        local monitor_pid
        monitor_pid=$(< "${monitor_pid_file}")
        kill "${monitor_pid}" 2>/dev/null || true
        wait "${monitor_pid}" 2>/dev/null || true
        rm -f "${monitor_pid_file}"
    fi
}

export -f status_to_priority
export -f animate_status
export -f title_updater
export -f cleanup_monitor
