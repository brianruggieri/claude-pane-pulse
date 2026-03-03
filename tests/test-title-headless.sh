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
# Mirrors the current monitor_claude_output heartbeat path exactly:
# prepended spinner, % 6 frame counter, $(< file), last_hook_check gate.

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
    set +e
    source "${LIB_DIR}/monitor.sh"
    current_priority=0
    current_context=""
    frame_counter=0
    task_summary=""
    clean_summary=""
    prev_display_context=""
    last_hook_check=$SECONDS
    s_file="${CCP_STATUS_FILE:-}"
    c_file="${CCP_CONTEXT_FILE:-}"
    update_title_with_context "myproject (main)" "" >/dev/null 2>&1 || true
    for _ in 1 2; do   # two heartbeat cycles
        IFS= read -r -t 1 line < "${PIPE}" || true
        [[ -n "${current_context}" ]] && frame_counter=$(( (frame_counter + 1) % 6 ))
        current_time=$SECONDS
        if [[ $((current_time - last_hook_check)) -ge 1 ]]; then
            last_hook_check=$current_time
            hook_status=""
            [[ -n "${s_file}" && -f "${s_file}" ]] && hook_status=$(< "${s_file}") || hook_status=""
            if [[ -n "${hook_status}" && "${hook_status}" != "${current_context}" ]]; then
                current_context="${hook_status}"
                current_priority=$(status_to_priority "${hook_status}")
            fi
            new_sum=""
            [[ -n "${c_file}" && -f "${c_file}" ]] && new_sum=$(< "${c_file}") || new_sum=""
            if [[ -n "${new_sum}" && "${new_sum}" != "${task_summary}" ]]; then
                task_summary="${new_sum}"
                clean_summary="${task_summary}"
            fi
        fi
        _spinner=""
        if [[ "${current_context}" =~ (Building|Testing|Installing|Pushing|Pulling|Merging|Docker|Thinking|Editing|Running|Reading|Browsing|Delegating) ]]; then
            case $((frame_counter % 6)) in
                0) _spinner="·" ;; 1) _spinner="✢" ;; 2) _spinner="✳" ;;
                3) _spinner="✶" ;; 4) _spinner="✻" ;; 5) _spinner="✽" ;;
            esac
        fi
        display_content=""
        if [[ -n "${clean_summary}" && -n "${current_context}" ]]; then
            display_content="${clean_summary} | ${current_context}"
        elif [[ -n "${current_context}" ]]; then
            display_content="${current_context}"
        fi
        display_context=""
        if [[ -n "${_spinner}" && -n "${display_content}" ]]; then
            display_context="${_spinner} ${display_content}"
        else
            display_context="${display_content}"
        fi
        if [[ "${display_context}" != "${prev_display_context}" ]]; then
            update_title_with_context "myproject (main)" "${display_context}" >/dev/null 2>&1 || true
            prev_display_context="${display_context}"
        fi
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
    set +e
    source "${LIB_DIR}/monitor.sh"
    current_priority=0
    current_context=""
    frame_counter=0
    task_summary=""
    clean_summary=""
    prev_display_context=""
    last_hook_check=$SECONDS
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
        [[ -n "${current_context}" ]] && frame_counter=$(( (frame_counter + 1) % 6 ))
        current_time=$SECONDS
        if [[ $((current_time - last_hook_check)) -ge 1 ]]; then
            last_hook_check=$current_time
            hook_status=""
            [[ -n "${s_file}" && -f "${s_file}" ]] && hook_status=$(< "${s_file}") || hook_status=""
            if [[ -n "${hook_status}" && "${hook_status}" != "${current_context}" ]]; then
                current_context="${hook_status}"
                current_priority=$(status_to_priority "${hook_status}")
            fi
            new_sum=""
            [[ -n "${c_file}" && -f "${c_file}" ]] && new_sum=$(< "${c_file}") || new_sum=""
            if [[ -n "${new_sum}" && "${new_sum}" != "${task_summary}" ]]; then
                task_summary="${new_sum}"
                clean_summary="${task_summary}"
            fi
        fi
        _spinner=""
        if [[ "${current_context}" =~ (Building|Testing|Installing|Pushing|Pulling|Merging|Docker|Thinking|Editing|Running|Reading|Browsing|Delegating) ]]; then
            case $((frame_counter % 6)) in
                0) _spinner="·" ;; 1) _spinner="✢" ;; 2) _spinner="✳" ;;
                3) _spinner="✶" ;; 4) _spinner="✻" ;; 5) _spinner="✽" ;;
            esac
        fi
        display_content=""
        if [[ -n "${clean_summary}" && -n "${current_context}" ]]; then
            display_content="${clean_summary} | ${current_context}"
        elif [[ -n "${current_context}" ]]; then
            display_content="${current_context}"
        fi
        display_context=""
        if [[ -n "${_spinner}" && -n "${display_content}" ]]; then
            display_context="${_spinner} ${display_content}"
        else
            display_context="${display_content}"
        fi
        if [[ "${display_context}" != "${prev_display_context}" ]]; then
            update_title_with_context "myproject (main)" "${display_context}" >/dev/null 2>&1 || true
            prev_display_context="${display_context}"
        fi
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
    set +e
    source "${LIB_DIR}/monitor.sh"
    current_priority=80
    current_context="🧪 Testing"
    s_file="${CCP_STATUS_FILE:-}"
    hook_status=""
    [[ -n "${s_file}" && -f "${s_file}" ]] && hook_status=$(< "${s_file}") || hook_status=""
    if [[ -z "${hook_status}" && "${current_priority}" -gt 10 ]]; then
        current_priority=10
        current_context="💤 Idle"
    fi
    update_title_with_context "myproject (main)" "${current_context}" >/dev/null 2>&1 || true
) 2>/dev/null

stop_log=$(cat "${TITLE_LOG}")
assert_contains "stop hook triggers idle in title" "💤 Idle" "${stop_log}"

# ── Section 5: format_title_prefix — size-aware truncation ─────────────────────

echo ""
echo "format_title_prefix — size-aware truncation"

# Short names fit at 80 cols without truncation
pfx=$(format_title_prefix "myproject" "main" 80)
assert_equals "short names: no truncation at 80 cols" "myproject (main) | " "${pfx}"

# No branch: project-only prefix
pfx=$(format_title_prefix "myproject" "" 80)
assert_equals "no branch: project-only prefix" "myproject | " "${pfx}"

# No project: empty prefix
pfx=$(format_title_prefix "" "main" 80)
assert_equals "no project: empty prefix" "" "${pfx}"

# Wide pane (120 cols): long names fit without truncation
# budget=84, branch_max=46, proj_max=38
# "very-long-project-name" (22) < 38 and "feature/my-long-feature-branch" (30) < 46
pfx=$(format_title_prefix "very-long-project-name" "feature/my-long-feature-branch" 120)
assert_contains "wide pane (120): full project shown"   "very-long-project-name"        "${pfx}"
assert_contains "wide pane (120): full branch shown"    "feature/my-long-feature-branch" "${pfx}"

# Narrow pane (60 cols): both truncated; branch retains more original chars
# budget=24, branch_max=13 (55%), proj_max=11 (45%)
# Truncation uses max-1 chars + ellipsis, so:
# "some-long-project" (17 > 11) → first 10 chars kept + "…": "some-long-"
# "some-long-branch-name" (21 > 13) → first 12 chars kept + "…": "some-long-br"
pfx=$(format_title_prefix "some-long-project" "some-long-branch-name" 60)
assert_contains     "narrow pane (60): project prefix preserved"    "some-long-"         "${pfx}"
assert_contains     "narrow pane (60): branch retains more chars"   "some-long-br"       "${pfx}"
assert_not_contains "narrow pane (60): full project name absent"    "some-long-project"  "${pfx}"
assert_not_contains "narrow pane (60): full branch name absent"     "some-long-branch-name" "${pfx}"

# Space donation: project short → branch gets extra space
# budget=44, branch_max=24, proj_max=20
# "go" (2) < 20 → donate 18 to branch_max (→42); "a-very-long-branch-name-indeed" (30) < 42 → no trim
pfx=$(format_title_prefix "go" "a-very-long-branch-name-indeed" 80)
assert_contains "donation to branch: long branch fully shown"  "a-very-long-branch-name-indeed" "${pfx}"
assert_contains "donation to branch: short project intact"     "go ("                           "${pfx}"

# Space donation: branch short → project gets extra space
# budget=44, branch_max=24, proj_max=20
# "go" (2) < 24 → donate 22 to proj_max (→42); "a-very-long-project-name-indeed" (31) < 42 → no trim
pfx=$(format_title_prefix "a-very-long-project-name-indeed" "go" 80)
assert_contains "donation to project: long project fully shown" "a-very-long-project-name-indeed" "${pfx}"
assert_contains "donation to project: short branch intact"      " (go) | "                       "${pfx}"

# Tiny pane (20 cols, minimum): no-branch path truncates project
# width clamped to 20, budget=max(4, 20-33)=4; "myproj" (6) > 4 → trim to 3+…
pfx=$(format_title_prefix "myproj" "" 20)
assert_contains     "tiny pane: project trimmed with ellipsis" "…"      "${pfx}"
assert_not_contains "tiny pane: full name absent"              "myproj " "${pfx}"

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
