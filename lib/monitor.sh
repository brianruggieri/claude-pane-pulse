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

    # Background process: read from the FIFO, strip ANSI codes, update title.
    # Uses read -t 1 so we heartbeat the title every second even when output
    # is quiet. This prevents Claude Code's TUI from permanently overriding
    # the pane title we set. read exit status semantics:
    #   0      = line read successfully
    #   >128   = 1-second timeout (no data) — heartbeat tick
    #   1      = EOF (write end of pipe closed, claude has exited)
    (
        local current_priority=0 last_update frame_counter=0 current_context=""
        last_update=$(date +%s)
        local esc
        esc=$(printf '\033')

        # Assert base title once before Claude Code starts its TUI
        update_title_with_context "${base_title}" ""

        while true; do
            local line read_status
            IFS= read -r -t 1 line
            read_status=$?

            if [[ ${read_status} -eq 0 ]]; then
                # Got a line — strip ANSI and extract status context
                line=$(printf '%s' "${line}" | sed "s/${esc}\[[0-9;]*[a-zA-Z]//g" | tr -d '\r')
                if [[ -n "${line}" ]]; then
                    local result new_context new_priority current_time
                    result=$(extract_context "${line}")
                    new_context="${result%|*}"
                    new_priority="${result#*|}"
                    current_time=$(date +%s)

                    if [[ -n "${new_context}" ]] && \
                       { [[ "${new_priority}" -ge "${current_priority}" ]] || \
                         [[ $((current_time - last_update)) -gt 60 ]]; }; then
                        current_priority="${new_priority}"
                        current_context="${new_context}"
                        last_update="${current_time}"
                    fi
                fi
            elif [[ ${read_status} -gt 128 ]]; then
                # 1-second timeout — heartbeat tick
                local current_time
                current_time=$(date +%s)

                # Reset to idle after 60s of no significant activity
                if [[ $((current_time - last_update)) -gt 60 ]] && \
                   [[ "${current_priority}" -gt 10 ]]; then
                    current_priority=10
                    current_context="💤 Idle"
                    last_update="${current_time}"
                fi
            else
                # EOF: write end of pipe closed (claude has exited)
                break
            fi

            # Re-assert title on every iteration (new data OR heartbeat tick)
            local animated_status
            animated_status=$(animate_status "${current_context}" "${frame_counter}")
            update_title_with_context "${base_title}" "${animated_status}"
            [[ -n "${current_context}" ]] && frame_counter=$(( (frame_counter + 1) % 4 ))
        done
    ) < "${pipe}" &

    local monitor_pid=$!
    echo "${monitor_pid}" > "${STATE_DIR}/monitor.$$.pid"

    # Run Claude Code in a PTY using Python's pty module.
    # Piping claude's stdout makes it detect a non-TTY and error with
    # "Input must be provided via stdin or --print". Python's pty.spawn
    # allocates a real PTY so claude runs interactively while simultaneously
    # writing output to our FIFO for title monitoring.
    # (macOS 'script -F' was tried but consistently fails with "Permission
    # denied" when called from inside a bash function on macOS Sonoma.)
    local claude_cmd python_cmd
    claude_cmd=$(get_claude_cmd)
    python_cmd=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")

    if [[ -n "${python_cmd}" ]]; then
        "${python_cmd}" "${_MONITOR_SCRIPT_DIR}/pty_wrapper.py" "${pipe}" "${claude_cmd}"
    else
        # Fallback: run claude directly without dynamic title monitoring
        log_warning "python3 not found; dynamic title monitoring disabled"
        "${claude_cmd}"
    fi

    # Cleanup: kill the monitor, then wait to suppress bash's "Terminated" message
    kill "${monitor_pid}" 2>/dev/null || true
    wait "${monitor_pid}" 2>/dev/null || true
    rm -f "${pipe}"
}

cleanup_monitor() {
    local monitor_pid_file="${STATE_DIR}/monitor.$$.pid"
    if [[ -f "${monitor_pid_file}" ]]; then
        local monitor_pid
        monitor_pid=$(cat "${monitor_pid_file}")
        kill "${monitor_pid}" 2>/dev/null || true
        wait "${monitor_pid}" 2>/dev/null || true
        rm -f "${monitor_pid_file}"
    fi
}

export -f extract_context
export -f animate_status
export -f monitor_claude_output
export -f cleanup_monitor
