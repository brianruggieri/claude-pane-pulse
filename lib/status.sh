#!/usr/bin/env bash
# lib/status.sh - Shared status utilities for claude-pane-pulse

# Prevent double-sourcing
[[ -n "${_CCP_STATUS_SOURCED:-}" ]] && return
_CCP_STATUS_SOURCED=1

# spinner_frame: return the spinner character for a given frame.
spinner_frame() {
    local frame="$1"
    case $((frame % 10)) in
        0) echo "·" ;;   # U+00B7 MIDDLE DOT          — grow start
        1) echo "✻" ;;   # U+273B TEARDROP-SPOKED ASTERISK
        2) echo "✽" ;;   # U+273D HEAVY TEARDROP-SPOKED ASTERISK
        3) echo "✶" ;;   # U+2736 SIX POINTED BLACK STAR
        4) echo "✳" ;;   # U+2733 EIGHT-SPOKED ASTERISK
        5) echo "✢" ;;   # U+2722 FOUR TEARDROP-SPOKED ASTERISK — peak
        6) echo "✳" ;;   # U+2733                     — shrink
        7) echo "✶" ;;   # U+2736
        8) echo "✽" ;;   # U+273D
        9) echo "✻" ;;   # U+273B
    esac
}

# is_active_status: true if the status should be animated.
is_active_status() {
    local status="$1"
    [[ "${status}" =~ (Building|Testing|Installing|Pushing|Pulling|Merging|Docker|Thinking|Editing|Running|Reading|Browsing|Delegating) || "${status}" =~ "✸" ]]
}

# animate_status: append a cycling spinner to active in-progress statuses.
animate_status() {
    local status="$1"
    local frame="$2"

    if is_active_status "${status}"; then
        echo "${status} $(spinner_frame "${frame}")"
    else
        echo "${status}"
    fi
}

# status_to_priority: map status string to priority.
status_to_priority() {
    local status="$1"
    if [[ "${status}" =~ (🐛|Error) ]]; then
        echo 100
    elif [[ "${status}" =~ (❌|Tests\ failed) ]]; then
        echo 90
    elif [[ "${status}" =~ (🔨|Building|🧪|Testing|📦|Installing) ]]; then
        echo 80
    elif [[ "${status}" =~ (⬆️|Pushing|⬇️|Pulling|🔀|Merging) ]]; then
        echo 75
    elif [[ "${status}" =~ (🐳|Docker|💭|Thinking|🤖|Delegating) ]]; then
        echo 70
    elif [[ "${status}" =~ (✏️|Editing) ]]; then
        echo 65
    elif [[ "${status}" =~ (✅|Tests\ passed|💾|Committed) ]]; then
        echo 60
    elif [[ "${status}" =~ (📖|Reading|🌐|Browsing|🖥️|Running) ]]; then
        echo 55
    elif [[ "${status}" =~ (💤|Idle) ]]; then
        echo 10
    else
        echo 50
    fi
}

_ccp_is_test_command() {
    local cmd="$1"
    [[ "${cmd}" =~ (jest|vitest|pytest|mocha|rspec|go[[:space:]]test|cargo[[:space:]]test|phpunit|bun[[:space:]]test|npm[[:space:]]test|yarn[[:space:]]test|pnpm[[:space:]]test) ]]
}

_ccp_is_build_command() {
    local cmd="$1"
    [[ "${cmd}" =~ (webpack|esbuild|tsc[[:space:]]|vite.*build|cargo[[:space:]]build|make[[:space:]]|cmake|gradle|mvn[[:space:]]package|npm[[:space:]]run.*build|yarn.*build|pnpm.*build|bun.*build) ]]
}

_ccp_is_install_command() {
    local cmd="$1"
    [[ "${cmd}" =~ (npm[[:space:]]+(install|add|ci)|yarn[[:space:]]+(install|add)|pnpm[[:space:]]+(install|add|i)|bun[[:space:]]+(install|add)|pip[[:space:]]install|cargo[[:space:]]add) ]]
}

# tool_status: classify tool usage into a status string.
# Args: $1=tool name, $2=command string (for Bash)
tool_status() {
    local tool="$1"
    local command_str="$2"

    case "${tool}" in
        Edit|Write|MultiEdit|NotebookEdit)
            echo "✏️ Editing"
            ;;
        Read|Glob|Grep)
            echo "📖 Reading"
            ;;
        WebFetch|WebSearch)
            echo "🌐 Browsing"
            ;;
        Task|Agent)
            echo "🤖 Delegating"
            ;;
        Bash)
            if _ccp_is_test_command "${command_str}"; then
                echo "🧪 Testing"
            elif _ccp_is_build_command "${command_str}"; then
                echo "🔨 Building"
            elif _ccp_is_install_command "${command_str}"; then
                echo "📦 Installing"
            elif [[ "${command_str}" =~ git[[:space:]]+push ]]; then
                echo "⬆️ Pushing"
            elif [[ "${command_str}" =~ git[[:space:]]+pull ]]; then
                echo "⬇️ Pulling"
            elif [[ "${command_str}" =~ git[[:space:]]+merge ]]; then
                echo "🔀 Merging"
            elif [[ "${command_str}" =~ docker ]]; then
                echo "🐳 Docker"
            else
                echo "🖥️ Running"
            fi
            ;;
        *)
            if [[ -n "${tool}" ]]; then
                echo "🔧 ${tool}"
            fi
            ;;
    esac
}

export -f spinner_frame
export -f is_active_status
export -f animate_status
export -f status_to_priority
export -f tool_status
