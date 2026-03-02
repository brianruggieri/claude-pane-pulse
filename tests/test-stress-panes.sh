#!/usr/bin/env bash
# tests/test-stress-panes.sh
# Simulates 6 concurrent ccp pane sessions with mocked hook events.
# Uses CCP_TITLE_LOG to capture title progression per pane.
# No Claude Code or real terminal needed.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "${SCRIPT_DIR}/../lib" && pwd)"

source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/title.sh"
source "${LIB_DIR}/monitor.sh"

ROOT_TMP=$(mktemp -d)
trap 'rm -rf "${ROOT_TMP}"' EXIT

BOLD=$'\033[1m'
DIM=$'\033[2m'

# ── Pane definitions ──────────────────────────────────────────────────────────

PANE_TITLES=(
    "my-api (main)"
    "frontend (feat/login)"
    "infrastructure (hotfix/443)"
    "ml-pipeline (experiment/v3)"
    "docs-site (master)"
    "shared-utils (refactor/core)"
)

PANE_PROMPTS=(
    "fix the auth token refresh bug"
    "build the new login form component"
    "patch the k8s ingress for ssl termination"
    "tune hyperparameters for the transformer model"
    "update api reference for v2 endpoints"
    "extract shared validation helpers"
)

# Events are written to per-pane event files.
# Format: one "sleep_secs status" per line (incremental, not absolute).
write_events() {
    local pane_id="$1"
    local dir="${ROOT_TMP}/pane${pane_id}"
    local f="${dir}/events.txt"
    mkdir -p "${dir}"
    case "${pane_id}" in
        0) cat > "${f}" << 'EOF'
0.2 READ
0.4 EDIT
0.4 EDIT
0.5 TEST
0.5 STOP
EOF
        ;;
        1) cat > "${f}" << 'EOF'
0.2 READ
0.3 INSTALL
0.4 EDIT
0.4 BROWSE
0.5 STOP
EOF
        ;;
        2) cat > "${f}" << 'EOF'
0.2 READ
0.4 EDIT
0.4 RUN
0.5 PUSH
0.4 STOP
EOF
        ;;
        3) cat > "${f}" << 'EOF'
0.2 READ
0.3 BUILD
0.5 BUILD
0.4 TEST
0.4 STOP
EOF
        ;;
        4) cat > "${f}" << 'EOF'
0.2 READ
0.4 EDIT
0.4 BROWSE
0.4 EDIT
0.5 STOP
EOF
        ;;
        5) cat > "${f}" << 'EOF'
0.2 READ
0.3 EDIT
0.3 EDIT
0.4 MERGE
0.3 COMMIT
0.3 STOP
EOF
        ;;
    esac
}

status_emoji() {
    case "$1" in
        READ)    printf '📖 Reading' ;;
        EDIT)    printf '✏️ Editing' ;;
        TEST)    printf '🧪 Testing' ;;
        INSTALL) printf '📦 Installing' ;;
        BROWSE)  printf '🌐 Browsing' ;;
        RUN)     printf '🖥️ Running' ;;
        PUSH)    printf '⬆️ Pushing' ;;
        PULL)    printf '⬇️ Pulling' ;;
        MERGE)   printf '🔀 Merging' ;;
        BUILD)   printf '🔨 Building' ;;
        COMMIT)  printf '💾 Committed' ;;
        DOCKER)  printf '🐳 Docker' ;;
        *)       printf '%s' "$1" ;;
    esac
}

export -f status_emoji
export -f update_title_with_context
export -f animate_status
export -f status_to_priority

run_pane() {
    local pane_id="$1"
    local base_title="$2"
    local prompt="$3"

    local pane_dir="${ROOT_TMP}/pane${pane_id}"
    local status_file="${pane_dir}/status.txt"
    local context_file="${pane_dir}/context.txt"
    local title_log="${pane_dir}/titles.log"
    local events_file="${pane_dir}/events.txt"

    export CCP_STATUS_FILE="${status_file}"
    export CCP_CONTEXT_FILE="${context_file}"
    export CCP_TITLE_LOG="${title_log}"
    rm -f "${status_file}" "${context_file}" "${title_log}"

    # UserPromptSubmit: write prompt to context file
    printf '%s' "${prompt}" > "${context_file}"

    # Fire hook events in background (incremental sleeps)
    (
        while read -r delay code; do
            sleep "${delay}"
            if [[ "${code}" == "STOP" ]]; then
                printf '' > "${status_file}"
            else
                status_emoji "${code}" > "${status_file}"
            fi
        done < "${events_file}"
    ) &
    local event_pid=$!

    # Title update loop for 3.5 seconds (events complete ~<2s)
    local current_context=""
    local current_priority=0
    local task_summary=""
    local frame=0
    local end_time
    end_time=$(( $(date +%s) + 4 ))

    update_title_with_context "${base_title}" "" > /dev/null 2>&1 || true

    while [[ $(date +%s) -lt ${end_time} ]]; do
        sleep 0.2

        if [[ -f "${status_file}" ]]; then
            local hook_status
            hook_status=$(cat "${status_file}" 2>/dev/null || true)
            if [[ -n "${hook_status}" && "${hook_status}" != "${current_context}" ]]; then
                current_context="${hook_status}"
                current_priority=$(status_to_priority "${hook_status}")
            elif [[ -z "${hook_status}" && "${current_priority}" -gt 10 ]]; then
                current_priority=10
                current_context="💤 Idle"
            fi
        fi

        if [[ -f "${context_file}" ]]; then
            local new_sum
            new_sum=$(cat "${context_file}" 2>/dev/null || true)
            [[ -n "${new_sum}" ]] && task_summary="${new_sum}"
        fi

        local animated
        animated=$(animate_status "${current_context}" "${frame}")
        local display=""
        if [[ -n "${task_summary}" && -n "${animated}" ]]; then
            display="${task_summary} | ${animated}"
        elif [[ -n "${task_summary}" ]]; then
            display="${task_summary}"
        elif [[ -n "${animated}" ]]; then
            display="${animated}"
        fi

        update_title_with_context "${base_title}" "${display}" > /dev/null 2>&1 || true
        frame=$(( (frame + 1) % 4 ))
    done

    kill "${event_pid}" 2>/dev/null || true
    wait "${event_pid}" 2>/dev/null || true
}
export -f run_pane

# ── Write event files ─────────────────────────────────────────────────────────

for i in 0 1 2 3 4 5; do write_events "${i}"; done

# ── Launch all panes in parallel ──────────────────────────────────────────────

echo ""
echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "${BOLD}  CCP Multi-Pane Stress Test — 6 concurrent sessions${NC}"
echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Launching 6 pane simulations in parallel (~4s)..."
echo ""

PANE_PIDS=()
for i in 0 1 2 3 4 5; do
    ( run_pane "${i}" "${PANE_TITLES[$i]}" "${PANE_PROMPTS[$i]}" ) &
    PANE_PIDS+=($!)
done

# Progress dots while running
for _ in $(seq 1 20); do printf '.'; sleep 0.2; done
echo ""

for pid in "${PANE_PIDS[@]}"; do wait "${pid}" 2>/dev/null || true; done

# ── Results ───────────────────────────────────────────────────────────────────

PASS=0; FAIL=0

check() {
    local label="$1" expect="$2" actual="$3"
    if [[ "${actual}" == *"${expect}"* ]]; then
        PASS=$(( PASS + 1 )); printf '  %s✓%s %s\n' "${GREEN}" "${NC}" "${label}"
    else
        FAIL=$(( FAIL + 1 )); printf '  %s✗%s %s\n  %s    expected: %s%s\n' "${RED}" "${NC}" "${label}" "${DIM}" "${expect}" "${NC}"
    fi
}
check_absent() {
    local label="$1" bad="$2" actual="$3"
    if [[ "${actual}" != *"${bad}"* ]]; then
        PASS=$(( PASS + 1 )); printf '  %s✓%s %s\n' "${GREEN}" "${NC}" "${label}"
    else
        FAIL=$(( FAIL + 1 )); printf '  %s✗%s %s\n  %s    should NOT contain: %s%s\n' "${RED}" "${NC}" "${label}" "${DIM}" "${bad}" "${NC}"
    fi
}

echo ""
for i in 0 1 2 3 4 5; do
    base="${PANE_TITLES[$i]}"
    prompt="${PANE_PROMPTS[$i]}"
    log_file="${ROOT_TMP}/pane${i}/titles.log"
    log_content=""
    [[ -f "${log_file}" ]] && log_content=$(cat "${log_file}")

    echo "  ${BOLD}Pane $((i+1)):${NC} ${BLUE}${base}${NC}"
    echo "  ${DIM}\"${prompt}\"${NC}"
    if [[ -f "${log_file}" ]]; then
        echo "  ${DIM}title progression (unique):${NC}"
        awk '!seen[$0]++' "${log_file}" | tail -8 | while IFS= read -r line; do
            printf '    → %s\n' "${line}"
        done
    fi

    check_absent "no doubled base_title"    "${base} | ${base}"  "${log_content}"
    check        "prompt in title"          "${prompt}"          "${log_content}"
    check        "separator present"        " | "               "${log_content}"
    check        "ends idle"               "💤 Idle"            "${log_content}"
    echo ""
done

echo "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ "${FAIL}" -eq 0 ]]; then
    echo "${GREEN}${BOLD}All ${PASS} checks passed across 6 panes${NC}"
    exit 0
else
    echo "${RED}${BOLD}${FAIL} checks failed out of $((PASS+FAIL))${NC}"
    exit 1
fi
