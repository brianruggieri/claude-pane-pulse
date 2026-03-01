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

# Status priority levels (higher = more important)
# 🐛 Error          = 100
# ❌ Tests failed   = 90
# 🔨 Building       = 80
# 🧪 Testing        = 80
# 📦 Installing     = 80
# ⬆️ Pushing        = 75
# ⬇️ Pulling        = 75
# 🔀 Merging        = 75
# 💭 Thinking       = 70
# 🐳 Docker         = 70
# ✅ Tests passed   = 60
# 💾 Committed      = 60
# 💤 Idle           = 10

# Track current status
CURRENT_STATUS=""
CURRENT_PRIORITY=0
LAST_UPDATE=0

# extract_context: parse a line of Claude Code output and return "status|priority"
extract_context() {
    local line="$1"
    local context=""
    local priority=0

    # Error states (highest priority)
    if [[ "${line}" =~ (Error|Failed|Exception|Traceback|FAILED) ]]; then
        context="🐛 Error"
        priority=100

    # Test failures
    elif [[ "${line}" =~ ([0-9]+)[[:space:]]+(tests?|specs?)[[:space:]]+(failed|failing) ]]; then
        context="❌ Tests failed"
        priority=90

    # Active build/compile operations
    elif [[ "${line}" =~ (Building|Compiling|Bundling) ]]; then
        context="🔨 Building"
        priority=80

    # Active test runs
    elif [[ "${line}" =~ (npm|yarn|cargo|go|pytest|jest)[[:space:]].*test ]]; then
        context="🧪 Testing"
        priority=80

    # Package installs
    elif [[ "${line}" =~ (npm|yarn)[[:space:]]+(install|add|ci) ]]; then
        context="📦 Installing"
        priority=80

    # Git operations
    elif [[ "${line}" =~ git[[:space:]]+push ]]; then
        context="⬆️ Pushing"
        priority=75
    elif [[ "${line}" =~ git[[:space:]]+pull ]]; then
        context="⬇️ Pulling"
        priority=75
    elif [[ "${line}" =~ git[[:space:]]+merge ]]; then
        context="🔀 Merging"
        priority=75

    # Docker
    elif [[ "${line}" =~ docker[[:space:]]+(build|run|push) ]]; then
        context="🐳 Docker"
        priority=70

    # Claude thinking/planning
    elif [[ "${line}" =~ Planning|Analyzing ]]; then
        context="💭 Thinking"
        priority=70

    # Test completions
    elif [[ "${line}" =~ ([0-9]+)[[:space:]]+(tests?|specs?)[[:space:]]+passed ]]; then
        context="✅ Tests passed"
        priority=60

    # Git commit completion
    elif [[ "${line}" =~ git[[:space:]]+commit ]]; then
        context="💾 Committed"
        priority=60
    fi

    echo "${context}|${priority}"
}

# animate_status: append animated dots to active operation statuses
animate_status() {
    local status="$1"
    local frame="$2"

    # Only animate in-progress operations (not completions or errors)
    if [[ "${status}" =~ (Building|Testing|Installing|Pushing|Pulling|Merging|Docker|Thinking) ]]; then
        local dots=""
        case $((frame % 4)) in
            0) dots="" ;;
            1) dots="." ;;
            2) dots=".." ;;
            3) dots="..." ;;
        esac
        echo "${status}${dots}"
    else
        echo "${status}"
    fi
}

# monitor_claude_output: run Claude Code with real-time title updates
monitor_claude_output() {
    local base_title="$1"
    local pipe="${STATE_DIR}/pipe.$$"
    local frame=0

    # Create named pipe for output monitoring
    mkfifo "${pipe}" 2>/dev/null || true

    # Background process: read from pipe, update title
    (
        while IFS= read -r line; do
            echo "${line}"  # Pass through to terminal

            local result new_context new_priority current_time
            result=$(extract_context "${line}")
            new_context="${result%|*}"
            new_priority="${result#*|}"
            current_time=$(date +%s)

            if [[ -n "${new_context}" ]] && \
               { [[ "${new_priority}" -ge "${CURRENT_PRIORITY}" ]] || \
                 [[ $((current_time - LAST_UPDATE)) -gt 60 ]]; }; then
                CURRENT_STATUS="${new_context}"
                CURRENT_PRIORITY="${new_priority}"
                LAST_UPDATE="${current_time}"

                local animated_status
                animated_status=$(animate_status "${CURRENT_STATUS}" "${frame}")
                update_title_with_context "${base_title}" "${animated_status}"
                frame=$(( (frame + 1) % 4 ))
            fi

            # Reset to idle after 60s with no significant activity
            current_time=$(date +%s)
            if [[ $((current_time - LAST_UPDATE)) -gt 60 ]] && \
               [[ "${CURRENT_PRIORITY}" -gt 10 ]]; then
                CURRENT_STATUS="💤 Idle"
                CURRENT_PRIORITY=10
                update_title_with_context "${base_title}" "${CURRENT_STATUS}"
            fi
        done < "${pipe}"
    ) &

    local monitor_pid=$!
    echo "${monitor_pid}" > "${STATE_DIR}/monitor.$$.pid"

    # Run Claude Code with output routed through the monitor pipe
    local claude_cmd
    claude_cmd=$(get_claude_cmd)
    "${claude_cmd}" 2>&1 | tee "${pipe}"

    # Cleanup
    kill "${monitor_pid}" 2>/dev/null || true
    rm -f "${pipe}"
}

cleanup_monitor() {
    local monitor_pid_file="${STATE_DIR}/monitor.$$.pid"
    if [[ -f "${monitor_pid_file}" ]]; then
        local monitor_pid
        monitor_pid=$(cat "${monitor_pid_file}")
        kill "${monitor_pid}" 2>/dev/null || true
        rm -f "${monitor_pid_file}"
    fi
}

export -f extract_context
export -f animate_status
export -f monitor_claude_output
export -f cleanup_monitor
