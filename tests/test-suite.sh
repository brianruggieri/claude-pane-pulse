#!/usr/bin/env bash
# tests/test-suite.sh - Claude Pane Pulse test suite

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="${PROJECT_DIR}/lib"

# Source libraries first (core.sh sets STATE_DIR to the real ~/.config path),
# then override with a temp dir so tests never touch ~/.config
source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/title.sh"
source "${LIB_DIR}/session.sh"
source "${LIB_DIR}/monitor.sh"

STATE_DIR=$(mktemp -d)
SESSION_FILE="${STATE_DIR}/sessions.json"
export STATE_DIR SESSION_FILE
echo '[]' > "${SESSION_FILE}"

# ── Test framework ────────────────────────────────────────────────────────────

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
    local name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}✓${NC} ${name}"
}

fail() {
    local name="$1"
    local msg="${2:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}✗${NC} ${name}"
    if [[ -n "${msg}" ]]; then
        echo "      ${msg}"
    fi
}

assert_equals() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "${expected}" == "${actual}" ]]; then
        pass "${name}"
    else
        fail "${name}" "expected: '${expected}', got: '${actual}'"
    fi
}

assert_contains() {
    local name="$1"
    local needle="$2"
    local haystack="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        pass "${name}"
    else
        fail "${name}" "expected to contain: '${needle}', got: '${haystack}'"
    fi
}

assert_empty() {
    local name="$1"
    local value="$2"
    if [[ -z "${value}" ]]; then
        pass "${name}"
    else
        fail "${name}" "expected empty, got: '${value}'"
    fi
}

# ── Tests: extract_context ────────────────────────────────────────────────────

echo ""
echo "extract_context()"

run_extract() {
    extract_context "$1" | cut -d'|' -f1
}

run_priority() {
    extract_context "$1" | cut -d'|' -f2
}

assert_contains "detects Error keyword"            "🐛 Error"       "$(run_extract "Error: file not found")"
assert_contains "detects Failed keyword"           "🐛 Error"       "$(run_extract "FAILED: build failed")"
assert_contains "detects Building"                 "🔨 Building"    "$(run_extract "Building project...")"
assert_contains "detects Compiling"                "🔨 Building"    "$(run_extract "Compiling main.rs")"
assert_contains "detects npm install"              "📦 Installing"  "$(run_extract "npm install --save-dev")"
assert_contains "detects yarn add"                 "📦 Installing"  "$(run_extract "yarn add react")"
assert_contains "detects git push"                 "⬆️ Pushing"     "$(run_extract "git push origin main")"
assert_contains "detects git pull"                 "⬇️ Pulling"     "$(run_extract "git pull --rebase")"
assert_contains "detects git merge"                "🔀 Merging"     "$(run_extract "git merge feature-branch")"
assert_contains "detects docker build"             "🐳 Docker"      "$(run_extract "docker build -t myapp .")"
assert_contains "detects tests passed"             "✅ Tests passed" "$(run_extract "5 tests passed")"
assert_contains "detects tests failed"             "❌ Tests failed" "$(run_extract "3 tests failed")"
assert_contains "detects git commit"               "💾 Committed"   "$(run_extract "git commit -m 'fix: stuff'")"
assert_empty    "ignores unmatched line"                             "$(run_extract "hello world")"

# Priority ordering
assert_equals   "Error has priority 100"     "100"  "$(run_priority "Error: crash")"
assert_equals   "Tests failed has priority 90" "90" "$(run_priority "3 tests failed")"
assert_equals   "Building has priority 80"   "80"   "$(run_priority "Building project")"
assert_equals   "Pushing has priority 75"    "75"   "$(run_priority "git push origin")"

# ── Tests: animate_status ─────────────────────────────────────────────────────

echo ""
echo "animate_status()"

assert_equals "frame 0 = no dots"    "🔨 Building"    "$(animate_status "🔨 Building" 0)"
assert_equals "frame 1 = one dot"    "🔨 Building."   "$(animate_status "🔨 Building" 1)"
assert_equals "frame 2 = two dots"   "🔨 Building.."  "$(animate_status "🔨 Building" 2)"
assert_equals "frame 3 = three dots" "🔨 Building..." "$(animate_status "🔨 Building" 3)"
assert_equals "frame 4 wraps to 0"   "🔨 Building"    "$(animate_status "🔨 Building" 4)"
assert_equals "error not animated"   "🐛 Error"       "$(animate_status "🐛 Error" 1)"
assert_equals "passed not animated"  "✅ Tests passed" "$(animate_status "✅ Tests passed" 2)"
assert_equals "idle not animated"    "💤 Idle"        "$(animate_status "💤 Idle" 1)"

# ── Tests: set_title ──────────────────────────────────────────────────────────

echo ""
echo "set_title()"

# Capture escape sequences
title_output=$(set_title "test title" 2>/dev/null | cat -v)
assert_contains "emits ESC]0; sequence" "^[]0;test title^G" "${title_output}"

# ── Tests: session management ─────────────────────────────────────────────────

echo ""
echo "session management"

# Re-init with clean state
echo '[]' > "${SESSION_FILE}"

save_session "Test Session" "/tmp/test"
session_count=$(jq 'length' "${SESSION_FILE}")
assert_equals "save_session adds entry" "1" "${session_count}"

saved_title=$(jq -r '.[0].title' "${SESSION_FILE}")
assert_equals "save_session stores title" "Test Session" "${saved_title}"

saved_dir=$(jq -r '.[0].directory' "${SESSION_FILE}")
assert_equals "save_session stores directory" "/tmp/test" "${saved_dir}"

found=$(find_session "Test")
assert_equals "find_session returns directory" "/tmp/test" "${found}"

not_found=$(find_session "Nonexistent" 2>/dev/null || true)
assert_empty "find_session returns empty for no match" "${not_found}"

cleanup_session
session_count_after=$(jq 'length' "${SESSION_FILE}")
assert_equals "cleanup_session removes current pid" "0" "${session_count_after}"

# find_session_title
echo '[]' > "${SESSION_FILE}"
save_session "Auth Feature" "/tmp/auth"
found_title=$(find_session_title "Auth")
assert_equals "find_session_title returns title" "Auth Feature" "${found_title}"

not_found_title=$(find_session_title "Nonexistent" 2>/dev/null || true)
assert_empty "find_session_title returns empty for no match" "${not_found_title}"

cleanup_session

# PID-liveness filtering: dead PIDs must not appear in list/find output
echo '[]' > "${SESSION_FILE}"
# Inject a fake session with an impossible PID (999999999 is never a valid pid)
echo '[{"title":"Dead Session","directory":"/tmp/dead","started":"2026-01-01T00:00:00Z","pid":999999999}]' \
    > "${SESSION_FILE}"
save_session "Live Session" "/tmp/live"

list_output=$(list_sessions 2>/dev/null)
assert_contains "list_sessions shows live sessions"    "Live Session"  "${list_output}"
# dead session should not appear
dead_in_list=0
if echo "${list_output}" | grep -q "Dead Session"; then dead_in_list=1; fi
assert_equals "list_sessions hides dead sessions" "0" "${dead_in_list}"

dead_dir=$(find_session "Dead" 2>/dev/null || true)
assert_empty "find_session ignores dead sessions" "${dead_dir}"

dead_title=$(find_session_title "Dead" 2>/dev/null || true)
assert_empty "find_session_title ignores dead sessions" "${dead_title}"

cleanup_session

# ── Summary ───────────────────────────────────────────────────────────────────

rm -rf "${STATE_DIR}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "${TESTS_FAILED}" -eq 0 ]]; then
    echo -e "${GREEN}All ${TESTS_PASSED} tests passed${NC}"
    exit 0
else
    echo -e "${RED}${TESTS_FAILED} of ${TESTS_RUN} tests FAILED${NC}"
    exit 1
fi
