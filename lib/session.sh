#!/usr/bin/env bash
# lib/session.sh - Session tracking and management

# Prevent double-sourcing
[[ -n "${_CCP_SESSION_SOURCED:-}" ]] && return
_CCP_SESSION_SOURCED=1

# Source core functions (safe: guarded against double-source)
_SESSION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core.sh
source "${_SESSION_SCRIPT_DIR}/core.sh"

save_session() {
    local title="$1"
    local directory="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local session
    session=$(jq -n \
        --arg title "${title}" \
        --arg directory "${directory}" \
        --arg started "${timestamp}" \
        --argjson pid $$ \
        '{title: $title, directory: $directory, started: $started, pid: $pid}')

    local sessions
    sessions=$(cat "${SESSION_FILE}")
    echo "${sessions}" | jq --argjson new "${session}" '. += [$new]' > "${SESSION_FILE}.tmp"
    mv "${SESSION_FILE}.tmp" "${SESSION_FILE}"
}

# prune_dead_sessions: remove entries whose process is no longer running.
# Rewrites SESSION_FILE in-place so all subsequent reads see only live sessions.
prune_dead_sessions() {
    [[ ! -f "${SESSION_FILE}" ]] && return

    local sessions keep
    sessions=$(cat "${SESSION_FILE}")
    keep="[]"
    while IFS= read -r entry; do
        local pid
        pid=$(echo "${entry}" | jq -r '.pid')
        if kill -0 "${pid}" 2>/dev/null; then
            keep=$(echo "${keep}" | jq --argjson e "${entry}" '. += [$e]')
        fi
    done < <(echo "${sessions}" | jq -c '.[]')

    echo "${keep}" > "${SESSION_FILE}"
}

list_sessions() {
    if [[ ! -f "${SESSION_FILE}" ]]; then
        echo "No sessions found."
        return
    fi

    prune_dead_sessions

    local sessions count
    sessions=$(cat "${SESSION_FILE}")
    count=$(echo "${sessions}" | jq 'length')

    if [[ "${count}" -eq 0 ]]; then
        echo "No active sessions."
        return
    fi

    echo -e "${BLUE}Active Sessions:${NC}\n"
    echo "${sessions}" | jq -r '.[] | "  • \(.title)\n    Dir: \(.directory)\n    Started: \(.started)\n"'
}

find_session() {
    local search="$1"
    local sessions result

    prune_dead_sessions

    sessions=$(cat "${SESSION_FILE}")
    result=$(echo "${sessions}" | jq -r --arg search "${search}" '
        .[] | select(.title | contains($search)) | .directory
    ' | head -n 1)

    echo "${result}"
}

# find_session_title: return the stored title for the first session matching search
find_session_title() {
    local search="$1"
    local sessions result

    prune_dead_sessions

    sessions=$(cat "${SESSION_FILE}")
    result=$(echo "${sessions}" | jq -r --arg search "${search}" '
        .[] | select(.title | contains($search)) | .title
    ' | head -n 1)

    echo "${result}"
}

cleanup_session() {
    if [[ ! -f "${SESSION_FILE}" ]]; then
        return
    fi
    local sessions
    sessions=$(cat "${SESSION_FILE}")
    echo "${sessions}" | jq --arg pid "$$" \
        'map(select(.pid != ($pid | tonumber)))' > "${SESSION_FILE}.tmp"
    mv "${SESSION_FILE}.tmp" "${SESSION_FILE}"
}

export -f save_session
export -f prune_dead_sessions
export -f list_sessions
export -f find_session
export -f find_session_title
export -f cleanup_session
