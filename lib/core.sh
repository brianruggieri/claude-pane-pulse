#!/usr/bin/env bash
# lib/core.sh - Core utility functions for claude-pane-pulse

# Prevent double-sourcing
[[ -n "${_CCP_CORE_SOURCED:-}" ]] && return
_CCP_CORE_SOURCED=1

# shellcheck disable=SC2034
VERSION="1.0.0"
# shellcheck disable=SC2034
SCRIPT_NAME="ccp"
STATE_DIR="${STATE_DIR:-${HOME}/.config/claude-pane-pulse}"
SESSION_FILE="${SESSION_FILE:-${STATE_DIR}/sessions.json}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Initialize state directory
init_state_dir() {
    mkdir -p "${STATE_DIR}"
    if [[ ! -f "${SESSION_FILE}" ]]; then
        echo '[]' > "${SESSION_FILE}"
    fi
}

# Check dependencies
check_dependencies() {
    local missing_deps=()

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    # Accept either 'claude' or 'claude-code', or CCP_CLAUDE_CMD override (used in tests)
    if [[ -z "$(get_claude_cmd)" ]]; then
        missing_deps+=("claude / claude-code")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${YELLOW}Missing dependencies:${NC}" >&2
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep" >&2
        done

        if [[ " ${missing_deps[*]} " =~ " jq " ]]; then
            echo -e "\n${BLUE}Install jq:${NC} brew install jq" >&2
        fi

        if [[ " ${missing_deps[*]} " =~ " claude / claude-code " ]]; then
            echo -e "\n${BLUE}Install Claude Code:${NC} https://claude.ai/code" >&2
        fi

        return 1
    fi

    return 0
}

# get_claude_cmd: return the available claude command.
# CCP_CLAUDE_CMD env var overrides for testing (e.g. pointing at mock-claude.sh).
# The override is only accepted if the command/path is actually executable.
get_claude_cmd() {
    if [[ -n "${CCP_CLAUDE_CMD:-}" ]]; then
        if [[ "${CCP_CLAUDE_CMD}" == *"/"* ]]; then
            # Looks like a path — require it to be executable
            if [[ -x "${CCP_CLAUDE_CMD}" ]]; then
                echo "${CCP_CLAUDE_CMD}"
                return
            fi
        else
            # Plain command name — require it to resolve via PATH
            if command -v "${CCP_CLAUDE_CMD}" &> /dev/null; then
                echo "${CCP_CLAUDE_CMD}"
                return
            fi
        fi
        # CCP_CLAUDE_CMD set but not executable; fall through to normal detection
    fi
    if command -v claude &> /dev/null; then
        echo "claude"
    elif command -v claude-code &> /dev/null; then
        echo "claude-code"
    else
        echo ""
    fi
}

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*" >&2
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

export -f init_state_dir
export -f check_dependencies
export -f get_claude_cmd
export -f log_info
export -f log_success
export -f log_warning
export -f log_error
