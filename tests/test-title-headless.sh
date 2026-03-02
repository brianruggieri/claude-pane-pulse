#!/usr/bin/env bash
# tests/test-title-headless.sh
# Headless integration test for title update behavior.
# Uses CCP_TITLE_LOG to capture what titles would appear in the terminal.
# No real terminal, no Claude Code needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="${PROJECT_DIR}/lib"

source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/title.sh"
source "${LIB_DIR}/session.sh"
source "${LIB_DIR}/monitor.sh"
source "${LIB_DIR}/hooks.sh"

# ── Test infrastructure ────────────────────────────────────────────────────────

STATE_DIR=$(mktemp -d)
SESSION_FILE="${STATE_DIR}/sessions.json"
export STATE_DIR SESSION_FILE
echo '[]' > "${SESSION_FILE}"

TITLE_LOG="${STATE_DIR}/titles.log"
export CCP_TITLE_LOG="${TITLE_LOG}"

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0

pass() { TESTS_RUN=$((TESTS_RUN+1)); TESTS_PASSED=$((TESTS_PASSED+1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); echo -e "  ${RED}✗${NC} $1"; [[ -n "${2:-}" ]] && echo "    $2"; }

assert_equals() {
    local name="$1" expected="$2" actual="$3"
    [[ "${expected}" == "${actual}" ]] && pass "${name}" || fail "${name}" "expected: '${expected}', got: '${actual}'"
}
assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    [[ "${haystack}" == *"${needle}"* ]] && pass "${name}" || fail "${name}" "expected to contain: '${needle}', in: '${haystack}'"
}
assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    [[ "${haystack}" != *"${needle}"* ]] && pass "${name}" || fail "${name}" "should NOT contain: '${needle}', in: '${haystack}'"
}

# ── Section 1: update_title_with_context output ───────────────────────────────

echo ""
echo "update_title_with_context — title bar output"

# When context is empty, window title (ESC]2;) should be blank, NOT base_title.
# This prevents iTerm2 from showing "base — base — Python · ccp — size".
raw_empty=$(update_title_with_context "myproject (main)" "" 2>/dev/null | cat -v)
assert_contains     "icon/tab title set to base_title"    "^[]1;myproject (main)^G"  "${raw_empty}"
assert_not_contains "window title must NOT repeat base"   "^[]2;myproject"           "${raw_empty}"
assert_contains     "window title is empty (^[]2;^G)"     "^[]2;^G"                  "${raw_empty}"

# When context is set, OSC 1 gets the context (full display string), OSC 2 is cleared.
raw_ctx=$(update_title_with_context "myproject (main)" "✏️ Editing..." 2>/dev/null | cat -v)
assert_contains     "icon/tab OSC1 contains context"      "^[]1;"                        "${raw_ctx}"
assert_not_contains "icon/tab OSC1 does not repeat base"  "^[]1;myproject (main)^G"      "${raw_ctx}"
assert_contains     "window title OSC2 is cleared"        "^[]2;^G"                      "${raw_ctx}"

# CCP_TITLE_LOG format
> "${TITLE_LOG}"
update_title_with_context "proj (feat)" "" > /dev/null 2>/dev/null || true
update_title_with_context "proj (feat)" "🧪 Testing..." > /dev/null 2>/dev/null || true
log_content=$(cat "${TITLE_LOG}")
assert_contains "log: idle entry is just base_title"      "proj (feat)"              "${log_content}"
assert_not_contains "log: idle has no pipe separator"     "proj (feat) | proj"       "${log_content}"
assert_contains "log: active entry shows separator"       "proj (feat) | 🧪 Testing..." "${log_content}"

# ── Section 2: monitor loop — no doubling on startup ──────────────────────────

echo ""
echo "monitor loop — startup title (no context yet)"

> "${TITLE_LOG}"
STATUS_FILE="${STATE_DIR}/status.$$.txt"
CONTEXT_FILE="${STATE_DIR}/context.$$.txt"
export CCP_STATUS_FILE="${STATUS_FILE}"
export CCP_CONTEXT_FILE="${CONTEXT_FILE}"
rm -f "${STATUS_FILE}" "${CONTEXT_FILE}"

PIPE="${STATE_DIR}/pipe.$$"
mkfifo "${PIPE}"

# Run the monitor subshell for 2 seconds, feeding it silence (no PTY output)
(
    while true; do sleep 0.1; done
) > "${PIPE}" &
FEED_PID=$!

(
    source "${LIB_DIR}/monitor.sh"
    # Inline the monitor subshell directly from monitor_claude_output
    local_priority=0
    local_context=""
    last_update=$(date +%s)
    frame=0
    last_hook=0
    s_file="${CCP_STATUS_FILE:-}"
    c_file="${CCP_CONTEXT_FILE:-}"
    esc=$(printf '\033')
    update_title_with_context "myproject (main)" "" >/dev/null 2>&1 || true
    for _ in 1 2; do   # two heartbeat cycles
        IFS= read -r -t 1 line < "${PIPE}" || true
        current_time=$(date +%s)
        if [[ -n "${s_file}" && -f "${s_file}" ]]; then
            hook_status=$(cat "${s_file}" 2>/dev/null || true)
            if [[ -n "${hook_status}" && "${hook_status}" != "${local_context}" ]]; then
                local_context="${hook_status}"
                local_priority=$(status_to_priority "${hook_status}")
                last_hook=${current_time}
            fi
        fi
        if [[ -n "${c_file}" && -f "${c_file}" ]]; then
            new_sum=$(cat "${c_file}" 2>/dev/null || true)
        fi
        animated=$(animate_status "${local_context}" "${frame}")
        display=""
        [[ -n "${animated}" ]] && display="${animated}"
        update_title_with_context "myproject (main)" "${display}" >/dev/null 2>&1 || true
        frame=$(( (frame + 1) % 4 ))
    done
) 2>/dev/null

kill "${FEED_PID}" 2>/dev/null || true
wait "${FEED_PID}" 2>/dev/null || true
rm -f "${PIPE}"

startup_log=$(cat "${TITLE_LOG}")
assert_not_contains "no doubling on startup" \
    "myproject (main) | myproject" "${startup_log}"
first_line=$(head -1 "${TITLE_LOG}")
assert_equals "first title is clean base_title" "myproject (main)" "${first_line}"

# ── Section 3: monitor loop — hook data flows to title ────────────────────────

echo ""
echo "monitor loop — hook status appears in title"

> "${TITLE_LOG}"
rm -f "${STATUS_FILE}" "${CONTEXT_FILE}"
PIPE2="${STATE_DIR}/pipe2.$$"
mkfifo "${PIPE2}"

(while true; do sleep 0.1; done) > "${PIPE2}" &
FEED2_PID=$!

(
    source "${LIB_DIR}/monitor.sh"
    local_priority=0
    local_context=""
    last_update=$(date +%s)
    frame=0
    s_file="${CCP_STATUS_FILE:-}"
    c_file="${CCP_CONTEXT_FILE:-}"

    # Simulate hook firing mid-session
    sleep 0.3
    printf '✏️ Editing' > "${s_file}"
    printf 'fix the null check in parser' > "${c_file}"
    sleep 0.2

    update_title_with_context "myproject (main)" "" >/dev/null 2>&1 || true
    for _ in 1 2 3 4; do
        IFS= read -r -t 1 line < "${PIPE2}" || true
        current_time=$(date +%s)
        task_sum=""
        if [[ -n "${s_file}" && -f "${s_file}" ]]; then
            hook_status=$(cat "${s_file}" 2>/dev/null || true)
            if [[ -n "${hook_status}" && "${hook_status}" != "${local_context}" ]]; then
                local_context="${hook_status}"
                local_priority=$(status_to_priority "${hook_status}")
            fi
        fi
        if [[ -n "${c_file}" && -f "${c_file}" ]]; then
            task_sum=$(cat "${c_file}" 2>/dev/null || true)
        fi
        animated=$(animate_status "${local_context}" "${frame}")
        display=""
        if [[ -n "${task_sum}" && -n "${animated}" ]]; then
            display="${task_sum} | ${animated}"
        elif [[ -n "${animated}" ]]; then
            display="${animated}"
        fi
        update_title_with_context "myproject (main)" "${display}" >/dev/null 2>&1 || true
        frame=$(( (frame + 1) % 4 ))
    done
) 2>/dev/null

kill "${FEED2_PID}" 2>/dev/null || true
wait "${FEED2_PID}" 2>/dev/null || true
rm -f "${PIPE2}"

hook_log=$(cat "${TITLE_LOG}")
assert_contains "hook status appears in title log" "✏️ Editing"  "${hook_log}"
assert_contains "prompt context appears in title"  "fix the null check in parser" "${hook_log}"
assert_contains "full format: prompt | status"     "fix the null check in parser | ✏️ Editing" "${hook_log}"
assert_not_contains "no doubling in hook titles"   "myproject (main) | myproject" "${hook_log}"

# ── Section 4: stop hook clears status (idle) ─────────────────────────────────

echo ""
echo "stop hook → idle title"

> "${TITLE_LOG}"
printf '🧪 Testing' > "${STATUS_FILE}"
# Simulate stop hook emptying the file
printf '' > "${STATUS_FILE}"

(
    source "${LIB_DIR}/monitor.sh"
    local_priority=80
    local_context="🧪 Testing"
    s_file="${CCP_STATUS_FILE:-}"
    current_time=$(date +%s)
    if [[ -n "${s_file}" && -f "${s_file}" ]]; then
        hook_status=$(cat "${s_file}" 2>/dev/null || true)
        if [[ -z "${hook_status}" && "${local_priority}" -gt 10 ]]; then
            local_priority=10
            local_context="💤 Idle"
        fi
    fi
    update_title_with_context "myproject (main)" "${local_context}" >/dev/null 2>&1 || true
) 2>/dev/null

stop_log=$(cat "${TITLE_LOG}")
assert_contains "stop hook triggers idle in title" "💤 Idle" "${stop_log}"

# ── Cleanup ────────────────────────────────────────────────────────────────────

rm -rf "${STATE_DIR}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "${TESTS_FAILED}" -eq 0 ]]; then
    echo -e "${GREEN}All ${TESTS_PASSED} headless title tests passed${NC}"
    exit 0
else
    echo -e "${RED}${TESTS_FAILED} of ${TESTS_RUN} tests FAILED${NC}"
    exit 1
fi
