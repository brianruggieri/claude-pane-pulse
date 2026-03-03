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

# Force OSC1 backend for deterministic escape-sequence assertions in this section.
CCP_TERMINAL_BACKEND="osc1"

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

unset CCP_TERMINAL_BACKEND

# ── Section 2: title_updater — no doubling on startup ─────────────────────────

echo ""
echo "title_updater — startup title (no context yet)"

> "${TITLE_LOG}"
STATUS_FILE="${STATE_DIR}/status.$$.txt"
CONTEXT_FILE="${STATE_DIR}/context.$$.txt"
export CCP_STATUS_FILE="${STATUS_FILE}"
export CCP_CONTEXT_FILE="${CONTEXT_FILE}"
rm -f "${STATUS_FILE}" "${CONTEXT_FILE}"

title_updater "myproject (main)"
sleep 1.2
cleanup_monitor

startup_log=$(cat "${TITLE_LOG}")
assert_not_contains "no doubling on startup" \
    "myproject (main) | myproject" "${startup_log}"
first_line=$(head -1 "${TITLE_LOG}")
assert_equals "first title is clean base_title" "myproject (main)" "${first_line}"

# ── Section 3: title_updater — hook data flows to title ───────────────────────

echo ""
echo "title_updater — hook status appears in title"

> "${TITLE_LOG}"
rm -f "${STATUS_FILE}" "${CONTEXT_FILE}"
title_updater "myproject (main)"
sleep 0.3
printf '✏️ Editing' > "${STATUS_FILE}"
printf 'fix the null check in parser' > "${CONTEXT_FILE}"
sleep 1.5
cleanup_monitor

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
title_updater "myproject (main)"
sleep 1.2
printf '' > "${STATUS_FILE}"
sleep 1.2
cleanup_monitor

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
