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
    if [[ "${status}" =~ (Error|Push\ failed|Pull\ failed) ]]; then
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
    elif [[ "${status}" =~ (Reading|Browsing|Running|Sending|Working) ]]; then
        echo 55
    elif [[ "${status}" =~ "📡 Monitoring" ]]; then
        echo 20
    else
        echo 50
    fi
}

title_updater() {
    local base_title="$1"

    (
        # keep the updater alive on non-zero checks/sleeps
        set +e

        local current_context=""
        local task_summary=""
        local clean_summary=""
        local prev_display_context=""
        local last_hook_check=$SECONDS
        local status_file="${CCP_STATUS_FILE:-}"
        local context_file="${CCP_CONTEXT_FILE:-}"
        local branch_file="${CCP_BRANCH_FILE:-}"
        local agents_file="${CCP_AGENTS_FILE:-}"
        local debug_log="${CCP_DEBUG_LOG:-}"
        local debug_jsonl="${CCP_DEBUG_JSONL:-}"

        # Monitor-local debug helper
        _mon_dbg() {
            [[ -n "${debug_log}" && "${debug_jsonl}" == "true" ]] || return 0
            local _ts _json _event="$1"
            shift
            _ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null || echo "")
            _json=$(jq -cn \
                --arg ts "${_ts}" \
                --arg src "monitor" \
                --arg pid "${CCP_SESSION_PID:-$$}" \
                --arg event "${_event}" \
                '{ts:$ts, src:$src, pid:$pid, event:$event}' 2>/dev/null) || return 0
            while [[ $# -gt 0 ]]; do
                local _k="${1%%=*}" _v="${1#*=}"
                _json=$(printf '%s' "${_json}" | jq -c --arg k "${_k}" --arg v "${_v}" '. + {($k): $v}' 2>/dev/null) || true
                shift
            done
            printf '%s\n' "${_json}" >> "${debug_log}" 2>/dev/null || true
        }

        _mon_dbg "monitor_start" "base_title=${base_title}"

        # Title validation — flags anomalies in the composed title string.
        # Only active when debug JSONL is enabled.
        _validate_title() {
            [[ -n "${debug_log}" && "${debug_jsonl}" == "true" ]] || return 0
            local _title="$1"
            local _issues=""

            # Empty title
            if [[ -z "${_title}" || "${_title}" =~ ^[[:space:]]*$ ]]; then
                _issues="empty_title"
            fi

            # JSON fragments (hook wrote raw JSON to status file)
            if [[ "${_title}" == *'{"'* || "${_title}" == *'"tool_name"'* || "${_title}" == *'"tool_input"'* ]]; then
                _issues="${_issues:+${_issues},}json_fragment"
            fi

            # Control characters (except common Unicode/emoji)
            if printf '%s' "${_title}" | grep -qP '[\x00-\x08\x0b\x0c\x0e-\x1f]' 2>/dev/null; then
                _issues="${_issues:+${_issues},}control_chars"
            fi

            # Raw escape sequences bled through
            if [[ "${_title}" == *$'\033'* ]]; then
                _issues="${_issues:+${_issues},}escape_sequence"
            fi

            # Newlines
            if [[ "${_title}" == *$'\n'* ]]; then
                _issues="${_issues:+${_issues},}newline"
            fi

            # Duplicate pipe separators (e.g. "proj | | status")
            if [[ "${_title}" =~ \|[[:space:]]*\| ]]; then
                _issues="${_issues:+${_issues},}double_pipe"
            fi

            # Trailing/leading pipe
            if [[ "${_title}" =~ ^[[:space:]]*\| ]] || [[ "${_title}" =~ \|[[:space:]]*$ ]]; then
                _issues="${_issues:+${_issues},}dangling_pipe"
            fi

            # Excessive length (>200 chars is likely a data leak)
            if [[ ${#_title} -gt 200 ]]; then
                _issues="${_issues:+${_issues},}too_long(${#_title})"
            fi

            # Project name duplicated in what should be the summary/status area
            if [[ -n "${CCP_PROJECT_NAME:-}" ]]; then
                local _after_prefix
                _after_prefix="${_title#*) | }"
                if [[ "${_after_prefix}" != "${_title}" ]]; then
                    # Count occurrences of project name after the prefix
                    local _count
                    _count=$(printf '%s' "${_after_prefix}" | grep -o "${CCP_PROJECT_NAME}" 2>/dev/null | wc -l | tr -d ' ')
                    if [[ "${_count}" -gt 0 ]]; then
                        _issues="${_issues:+${_issues},}project_name_in_content"
                    fi
                fi
            fi

            if [[ -n "${_issues}" ]]; then
                _mon_dbg "title_anomaly" "issues=${_issues}" "title_len=${#_title}" "title_preview=$(printf '%s' "${_title}" | head -c 100)"
            fi
        }

        # Idle phrase cycling — advances to next phrase each time Claude goes idle
        local _idle_idx=0
        local _prev_active=false
        local _idle_phrases=(
            "💤 Idle"
            "☕ Recharging"
            "🧘 Centering"
            "🎯 Ready"
            "🫡 Standing by"
            "💡 Listening"
            "🌿 At rest"
            "👀 Watching"
            "🌊 Drifting"
            "✨ Floating"
        )

        local title_prefix
        title_prefix=$(format_title_prefix "${CCP_PROJECT_NAME:-}" "${CCP_BRANCH_NAME:-}")
        local current_branch="${CCP_BRANCH_NAME:-}"

        # Assert base title once before Claude Code starts.
        update_title_with_context "${base_title}" ""

        while true; do
            sleep 1 || break

            local current_time=$SECONDS
            if [[ $((current_time - last_hook_check)) -ge 1 ]]; then
                last_hook_check=$current_time

                local hook_status=""
                if [[ -n "${status_file}" && -f "${status_file}" ]]; then
                    hook_status=$(< "${status_file}") || hook_status=""
                fi

                if [[ -n "${hook_status}" ]]; then
                    if [[ "${hook_status}" != "${current_context}" ]]; then
                        _mon_dbg "status_change" "old=${current_context}" "new=${hook_status}"
                        # Validate status is from known set
                        case "${hook_status}" in
                            *Editing*|*Reading*|*Browsing*|*Delegating*|*Testing*|\
                            *Building*|*Installing*|*Pushing*|*Pulling*|*Merging*|\
                            *Docker*|*Running*|*Thinking*|*Error*|*Push\ failed*|*Pull\ failed*|*Tests\ passed*|\
                            *Tests\ failed*|*Committed*|*Completed*|*Idle*|\
                            *Awaiting\ approval*|*Input\ needed*|*Notification*|\
                            *Session\ started*|*Session\ ended*|*Compacting*|\
                            *Subagent*|*Teammate*|*Config\ changed*|*Worktree*|\
                            *Welcome\ back*|*Monitoring*)
                                ;; # known status — ok
                            *)
                                _mon_dbg "unknown_status" "status=${hook_status}" "len=${#hook_status}"
                                ;;
                        esac
                        current_context="${hook_status}"
                    fi
                    _prev_active=true
                else
                    # Check for running background agents before going idle.
                    # SubagentStart increments agents_file; SubagentStop decrements it.
                    # When count > 0 Claude is idle but agents are still working.
                    local _bg_count=0
                    if [[ -n "${agents_file}" && -f "${agents_file}" ]]; then
                        _bg_count=$(< "${agents_file}") || _bg_count=0
                        _bg_count=$(( _bg_count + 0 ))  # coerce to int; empty/corrupt → 0
                    fi

                    if [[ "${_bg_count}" -gt 0 ]]; then
                        # Stay in pseudo-active state — don't advance idle index or
                        # flip _prev_active so the transition fires correctly later.
                        if [[ "${current_context}" != "📡 Monitoring" ]]; then
                            _mon_dbg "monitoring_start" "agent_count=${_bg_count}"
                        fi
                        current_context="📡 Monitoring"
                    else
                        # Normal idle transition
                        if [[ "${_prev_active}" = true ]]; then
                            _idle_idx=$(( (_idle_idx + 1) % ${#_idle_phrases[@]} ))
                            _prev_active=false
                            _mon_dbg "idle_transition" "prev_status=${current_context}" "idle_phrase=${_idle_phrases[${_idle_idx}]}"
                        fi
                        current_context="${_idle_phrases[${_idle_idx}]}"
                    fi
                fi

                local new_summary=""
                if [[ -n "${context_file}" && -f "${context_file}" ]]; then
                    new_summary=$(< "${context_file}") || new_summary=""
                fi

                if [[ "${new_summary}" != "${task_summary}" ]]; then
                    _mon_dbg "context_change" "old=${task_summary}" "new=${new_summary}"
                    task_summary="${new_summary}"
                    clean_summary="${task_summary}"
                    if [[ -n "${CCP_PROJECT_NAME:-}" && -n "${clean_summary}" ]]; then
                        clean_summary=$(printf '%s' "${clean_summary}" \
                            | sed "s/ (${CCP_PROJECT_NAME})[^,]*,\{0,1\}[[:space:]]*//g" \
                            | sed 's/^[[:space:]]*//' \
                            | sed 's/[[:space:]]*$//')
                    fi
                fi

                # Check for branch changes written by hook_runner.sh
                if [[ -n "${branch_file}" && -f "${branch_file}" ]]; then
                    local new_branch=""
                    new_branch=$(< "${branch_file}") || new_branch=""
                    if [[ -n "${new_branch}" && "${new_branch}" != "${current_branch}" ]]; then
                        _mon_dbg "branch_update" "old=${current_branch}" "new=${new_branch}"
                        current_branch="${new_branch}"
                        title_prefix=$(format_title_prefix "${CCP_PROJECT_NAME:-}" "${current_branch}")
                    fi
                fi
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

            local display_context="${_body}"

            if [[ "${display_context}" != "${prev_display_context}" ]]; then
                _validate_title "${display_context}"
                _mon_dbg "title_update" "title=${display_context}"
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
export -f title_updater
export -f cleanup_monitor
