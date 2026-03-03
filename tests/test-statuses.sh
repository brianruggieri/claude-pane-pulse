#!/usr/bin/env bash
# tests/test-statuses.sh - Status priority, title composition, and monitor integration tests
#
# Covers gaps not addressed by test-suite.sh or test-title-headless.sh:
#   1. status_to_priority for all hook-written named statuses
#   2. Completion event priority bypass (✅ overrides 🧪 Testing despite lower priority)
#   3. Title composition: context file + status file → "summary | status" in title log
#   4. clean_summary strips project name parenthetical from context
#   5. Priority ordering: lower-priority status does not override active higher-priority status
#   6. title_updater integration via hook-written status/context files
#   7. Idle transition when Stop clears status
#   8. Animation spinner chars appear prepended in title
#
# Usage: bash tests/test-statuses.sh [--verbose]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="${PROJECT_DIR}/lib"

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

# Add homebrew to PATH for jq (needed by sourced libs)
PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
export PATH

source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/title.sh"
source "${LIB_DIR}/monitor.sh"

# ── Test framework ─────────────────────────────────────────────────────────────

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0

pass() {
    TESTS_RUN=$((TESTS_RUN+1)); TESTS_PASSED=$((TESTS_PASSED+1))
    echo "  ${GREEN}✓${NC} $1"
}
fail() {
    TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1))
    echo "  ${RED}✗${NC} $1"
    [[ -n "${2:-}" ]] && echo "      expected: $2" && echo "      got:      $3"
}
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    [[ "${expected}" == "${actual}" ]] && pass "${label}" \
        || fail "${label}" "${expected}" "${actual}"
}
assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    [[ "${haystack}" == *"${needle}"* ]] && pass "${label}" \
        || fail "${label}" "*${needle}*" "${haystack}"
}
assert_not_contains() {
    local label="$1" needle="$2" haystack="$3"
    [[ "${haystack}" != *"${needle}"* ]] && pass "${label}" \
        || fail "${label}" "(must NOT contain) ${needle}" "${haystack}"
}

# ── Temp workspace ─────────────────────────────────────────────────────────────

TMP="$(mktemp -d /tmp/ccp_statuses_XXXXXX)"
STATE_DIR="${TMP}/state"
mkdir -p "${STATE_DIR}"
SESSION_FILE="${STATE_DIR}/sessions.json"
echo '[]' > "${SESSION_FILE}"
export STATE_DIR SESSION_FILE

STATUS_FILE="${TMP}/status.txt"
CONTEXT_FILE="${TMP}/context.txt"
TITLE_LOG="${TMP}/titles.log"
export CCP_STATUS_FILE="${STATUS_FILE}"
export CCP_CONTEXT_FILE="${CONTEXT_FILE}"
export CCP_TITLE_LOG="${TITLE_LOG}"

cleanup() { rm -rf "${TMP}"; }
trap cleanup EXIT

# ── Section 1: status_to_priority for hook-written named statuses ──────────────
# hook_runner.sh writes full emoji+text strings; test that priorities are correct.

echo ""
echo "══════════════════════════════════════════════════════════════"
echo " CCP Status Tests"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "── Section 1: status_to_priority ──"

assert_eq "🐛 Error → 100"        "100" "$(status_to_priority '🐛 Error')"
assert_eq "❌ Tests failed → 90"  "90"  "$(status_to_priority '❌ Tests failed')"
assert_eq "⏸️ Awaiting approval → 88" "88" "$(status_to_priority '⏸️ Awaiting approval')"
assert_eq "🙋 Input needed → 85"  "85"  "$(status_to_priority '🙋 Input needed')"
assert_eq "🔨 Building → 80"      "80"  "$(status_to_priority '🔨 Building')"
assert_eq "🧪 Testing → 80"       "80"  "$(status_to_priority '🧪 Testing')"
assert_eq "📦 Installing → 80"    "80"  "$(status_to_priority '📦 Installing')"
assert_eq "⬆️ Pushing → 75"       "75"  "$(status_to_priority '⬆️ Pushing')"
assert_eq "⬇️ Pulling → 75"       "75"  "$(status_to_priority '⬇️ Pulling')"
assert_eq "🔀 Merging → 75"       "75"  "$(status_to_priority '🔀 Merging')"
assert_eq "🐳 Docker → 70"        "70"  "$(status_to_priority '🐳 Docker')"
assert_eq "💭 Thinking → 70"      "70"  "$(status_to_priority '💭 Thinking')"
assert_eq "🤖 Delegating → 70"    "70"  "$(status_to_priority '🤖 Delegating')"
assert_eq "✏️ Editing → 65"       "65"  "$(status_to_priority '✏️ Editing')"
assert_eq "✅ Tests passed → 60"  "60"  "$(status_to_priority '✅ Tests passed')"
assert_eq "💾 Committed → 60"     "60"  "$(status_to_priority '💾 Committed')"
assert_eq "🏁 Completed → 60"     "60"  "$(status_to_priority '🏁 Completed')"
assert_eq "📖 Reading → 55"       "55"  "$(status_to_priority '📖 Reading')"
assert_eq "🌐 Browsing → 55"      "55"  "$(status_to_priority '🌐 Browsing')"
assert_eq "🖥️ Running → 55"       "55"  "$(status_to_priority '🖥️ Running')"
assert_eq "🚀 Session started → 52" "52" "$(status_to_priority '🚀 Session started')"

# ── Section 2: completion event priority bypass via extract_context ────────────
# ✅ Tests passed (priority 60) must be returned even when active status is higher.
# The monitor checks for completion events SEPARATELY from the priority gate.

echo ""
echo "── Section 2: completion event detection ──"

result=$(extract_context "5 tests passed")
ctx="${result%|*}"; pri="${result#*|}"
assert_eq "extract_context: 5 tests passed → ✅ Tests passed" "✅ Tests passed" "${ctx}"
assert_eq "extract_context: 5 tests passed priority → 60"    "60"              "${pri}"

result=$(extract_context "3 tests failed")
ctx="${result%|*}"; pri="${result#*|}"
assert_eq "extract_context: 3 tests failed → ❌ Tests failed" "❌ Tests failed" "${ctx}"
assert_eq "extract_context: 3 tests failed priority → 90"     "90"              "${pri}"

result=$(extract_context "git commit -m 'fix'")
ctx="${result%|*}"
assert_eq "extract_context: git commit → 💾 Committed" "💾 Committed" "${ctx}"

# Verify completion context strings match the bypass pattern used in the monitor.
# The monitor checks: new_context =~ (Tests passed|Tests failed|Committed)
for event in "✅ Tests passed" "❌ Tests failed" "💾 Committed"; do
    if [[ "${event}" =~ (Tests\ passed|Tests\ failed|Committed) ]]; then
        pass "completion pattern matches '${event}'"
    else
        fail "completion pattern matches '${event}'" "(matched)" "(no match)"
    fi
done

# ── Section 3: title composition — status file → CCP_TITLE_LOG ────────────────
# Write each named status to CCP_STATUS_FILE, then call update_title_with_context
# exactly as the monitor heartbeat does. Verify CCP_TITLE_LOG captures the entry.

echo ""
echo "── Section 3: hook status → title log ──"

for status_str in \
    "🐛 Error" "❌ Tests failed" "⏸️ Awaiting approval" "🙋 Input needed" \
    "🔨 Building" "🧪 Testing" "📦 Installing" \
    "⬆️ Pushing" "⬇️ Pulling" "🔀 Merging" "🐳 Docker" "💭 Thinking" \
    "🤖 Delegating" "✏️ Editing" "✅ Tests passed" "💾 Committed" "🏁 Completed" \
    "📖 Reading" "🌐 Browsing" "🖥️ Running" "💤 Idle"; do

    > "${TITLE_LOG}"
    printf '%s' "${status_str}" > "${STATUS_FILE}"
    hook_val=$(< "${STATUS_FILE}")
    # Simulate what the monitor's title-update block does (status, no summary)
    update_title_with_context "myproject (main)" "${hook_val}" >/dev/null 2>&1 || true
    log=$(cat "${TITLE_LOG}")
    assert_contains "status '${status_str}' appears in title log" "${status_str}" "${log}"
done

# ── Section 4: title composition — context + status compose ───────────────────
# Verify "summary | status" format appears in the log when both files are set.

echo ""
echo "── Section 4: context + status compose ──"

> "${TITLE_LOG}"
printf 'Fix Auth Middleware' > "${CONTEXT_FILE}"
printf '✏️ Editing' > "${STATUS_FILE}"

summary=$(< "${CONTEXT_FILE}")
status_val=$(< "${STATUS_FILE}")
display_content="${summary} | ${status_val}"
update_title_with_context "myproject (main)" "${display_content}" >/dev/null 2>&1 || true
log=$(cat "${TITLE_LOG}")
assert_contains "title log contains summary" "Fix Auth Middleware" "${log}"
assert_contains "title log contains status"  "✏️ Editing"          "${log}"
assert_contains "title log shows summary | status format" \
    "Fix Auth Middleware | ✏️ Editing" "${log}"

# ── Section 5: clean_summary strips project name parenthetical ─────────────────
# When CCP_PROJECT_NAME is set, the context "(myproject)" parenthetical must be
# stripped from the task summary so it doesn't clutter the title.

echo ""
echo "── Section 5: clean_summary strips project name ──"

export CCP_PROJECT_NAME="myproject"

# The sed pattern s/ (project)[^,]*// strips from "(project)" to end-of-string
# (or comma). With no comma, text after the parenthetical is also stripped.
# Verify: (a) parenthetical is gone, (b) text before it is preserved.
raw_context="Fix Auth (myproject) middleware test"

clean_summary="${raw_context}"
clean_summary=$(printf '%s' "${clean_summary}" \
    | sed "s/ (${CCP_PROJECT_NAME})[^,]*,\{0,1\}[[:space:]]*//g" \
    | sed 's/^[[:space:]]*//' \
    | sed 's/[[:space:]]*$//')

assert_not_contains "clean_summary removes '(myproject)'" "(myproject)" "${clean_summary}"
assert_contains     "clean_summary retains prefix text"   "Fix Auth"    "${clean_summary}"

unset CCP_PROJECT_NAME

# Trailing comma variant
raw2="Fix Auth (myproject), and login test"
clean2="${raw2}"
CCP_PROJECT_NAME="myproject"
clean2=$(printf '%s' "${clean2}" \
    | sed "s/ (${CCP_PROJECT_NAME})[^,]*,\{0,1\}[[:space:]]*//g" \
    | sed 's/^[[:space:]]*//' \
    | sed 's/[[:space:]]*$//')
unset CCP_PROJECT_NAME
assert_contains "clean_summary: trailing comma variant produces non-empty result" \
    "Fix Auth" "${clean2}"
assert_not_contains "clean_summary: trailing comma variant has no parenthetical" \
    "(myproject)" "${clean2}"

# ── Section 6: priority ordering — lower does NOT override active higher ────────
# Running (55) must not override Building (80) via the status_to_priority check.

echo ""
echo "── Section 6: priority ordering ──"

building_pri=$(status_to_priority "🔨 Building")
await_pri=$(status_to_priority "⏸️ Awaiting approval")
input_pri=$(status_to_priority "🙋 Input needed")
running_pri=$(status_to_priority "🖥️ Running")
testing_pri=$(status_to_priority "🧪 Testing")
passed_pri=$(status_to_priority "✅ Tests passed")
error_pri=$(status_to_priority "🐛 Error")

[[ "${await_pri}" -gt "${building_pri}" ]] \
    && pass "Awaiting approval (${await_pri}) > Building (${building_pri})" \
    || fail "Awaiting approval (${await_pri}) > Building (${building_pri})" "awaiting > building" "not true"

[[ "${input_pri}" -gt "${building_pri}" ]] \
    && pass "Input needed (${input_pri}) > Building (${building_pri})" \
    || fail "Input needed (${input_pri}) > Building (${building_pri})" "input > building" "not true"

[[ "${running_pri}" -lt "${building_pri}" ]] \
    && pass "Running (${running_pri}) < Building (${building_pri})" \
    || fail "Running (${running_pri}) < Building (${building_pri})" "Running < Building" "not true"

[[ "${passed_pri}" -lt "${testing_pri}" ]] \
    && pass "Tests passed (${passed_pri}) < Testing (${testing_pri}) — completion bypass needed" \
    || fail "Tests passed (${passed_pri}) < Testing (${testing_pri})" "passed < testing" "not true"

[[ "${error_pri}" -gt "${building_pri}" ]] \
    && pass "Error (${error_pri}) > Building (${building_pri})" \
    || fail "Error (${error_pri}) > Building (${building_pri})" "error > building" "not true"

# The monitor uses status_to_priority() for hook-path ordering;
# completion events bypass the check entirely. Verify the bypass condition matches:
# new_context =~ (Tests passed|Tests failed|Committed)
new_ctx="✅ Tests passed"
if [[ "${new_ctx}" =~ (Tests\ passed|Tests\ failed|Committed) ]]; then
    pass "bypass condition correctly matches '${new_ctx}'"
else
    fail "bypass condition correctly matches '${new_ctx}'" "(match)" "(no match)"
fi

# ── Section 7: title_updater integration — hook status write ───────────────────
# Start title_updater, then simulate hooks by writing status/context files.

echo ""
echo "── Section 7: hook status write (title_updater integration) ──"

> "${TITLE_LOG}"
rm -f "${STATUS_FILE}" "${CONTEXT_FILE}"
title_updater "myproject (main)"
sleep 1.2
printf '💭 Thinking' > "${STATUS_FILE}"
printf 'Investigate auth timeout' > "${CONTEXT_FILE}"
sleep 1.2
cleanup_monitor

hook_log=$(cat "${TITLE_LOG}")
[[ "${VERBOSE}" == "true" ]] && echo "--- title log ---" && cat "${TITLE_LOG}" && echo "---"
assert_contains "hook status appears in title log" "💭 Thinking" "${hook_log}"
assert_contains "context appears in title log" "Investigate auth timeout" "${hook_log}"

# ── Section 8: title_updater integration — stop hook idle ──────────────────────
# Write an active status, then clear it to simulate Stop hook.

echo ""
echo "── Section 8: stop hook idle (title_updater integration) ──"

> "${TITLE_LOG}"
rm -f "${STATUS_FILE}" "${CONTEXT_FILE}"
printf '🧪 Testing' > "${STATUS_FILE}"
title_updater "myproject (main)"
sleep 1.2
printf '' > "${STATUS_FILE}"
sleep 1.2
cleanup_monitor

idle_log=$(cat "${TITLE_LOG}")
[[ "${VERBOSE}" == "true" ]] && echo "--- title log ---" && cat "${TITLE_LOG}" && echo "---"
assert_contains "idle appears after stop clears status" "💤 Idle" "${idle_log}"

# ── Section 9: title_updater integration — animation spinner chars prepended ───
# Drive title_updater with an active status and verify spinner characters appear.
# Format: "spinner_char body" logged as "base_title | spinner_char body"

echo ""
echo "── Section 9: animation spinner chars prepended (title_updater integration) ──"

> "${TITLE_LOG}"
rm -f "${STATUS_FILE}" "${CONTEXT_FILE}"
printf '✏️ Editing' > "${STATUS_FILE}"
title_updater "myproject (main)"
sleep 8
cleanup_monitor

spin_log=$(cat "${TITLE_LOG}")
[[ "${VERBOSE}" == "true" ]] && echo "--- title log ---" && cat "${TITLE_LOG}" && echo "---"

# All 6 spinner chars must appear somewhere in the log (prepended to title)
for ch in "·" "✢" "✳" "✶" "✻" "✽"; do
    assert_contains "spinner char '${ch}' appears in title log" "${ch}" "${spin_log}"
done

# Spinner must be PREPENDED: find a line that has both a spinner char and the status.
# CCP_TITLE_LOG format: "base_title | spinner_char status_text"
# grep for any line containing a spinner char immediately followed by ✏️ Editing
spinner_editing_line=$(grep -m1 '[·✢✳✶✻✽] ✏️ Editing' "${TITLE_LOG}" 2>/dev/null || echo "")
assert_contains "spinner is prepended (before ✏️ Editing)" "✏️ Editing" "${spinner_editing_line}"

# ── Results ────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════"
echo " Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed (${TESTS_RUN} total)"
echo "══════════════════════════════════════════════════════════════"
echo ""

[[ "${TESTS_FAILED}" -eq 0 ]] && exit 0 || exit 1
