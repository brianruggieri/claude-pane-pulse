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
source "${LIB_DIR}/hooks.sh"

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

# ● structural patterns (Claude Code tool-call / status lines)
assert_contains "● Bash git push → Pushing"    "⬆️ Pushing"   "$(run_extract "● Bash(git push origin main)")"
assert_contains "● Bash git pull → Pulling"    "⬇️ Pulling"   "$(run_extract "● Bash(git pull --rebase)")"
assert_contains "● Bash npm install → Install" "📦 Installing" "$(run_extract "● Bash(npm install)")"
assert_contains "● Bash jest → Testing"        "🧪 Testing"   "$(run_extract "● Bash(npx jest --coverage)")"
assert_contains "● Bash webpack → Building"    "🔨 Building"  "$(run_extract "● Bash(webpack --mode production)")"
assert_contains "● Edit → Editing"             "✏️ Editing"   "$(run_extract "● Edit(lib/monitor.sh)")"
assert_contains "● Write → Editing"            "✏️ Editing"   "$(run_extract "● Write(README.md)")"
assert_contains "● Bash generic → Running"     "🖥️ Running"   "$(run_extract "● Bash(ls -la)")"

# Priority ordering
assert_equals   "Error has priority 100"       "100"  "$(run_priority "Error: crash")"
assert_equals   "Tests failed has priority 90" "90"   "$(run_priority "3 tests failed")"
assert_equals   "Building has priority 80"     "80"   "$(run_priority "Building project")"
assert_equals   "Pushing has priority 75"      "75"   "$(run_priority "git push origin")"
assert_equals   "Editing has priority 65"      "65"   "$(run_priority "● Edit(foo.sh)")"
assert_equals   "Running has priority 55"      "55"   "$(run_priority "● Bash(ls)")"

# ── Tests: animate_status ─────────────────────────────────────────────────────

echo ""
echo "animate_status()"

# Ping-pong sequence: · ✻ ✽ ✶ ✳ ✢  ✳ ✶ ✽ ✻  (then back to ·)
assert_equals "frame 0  = · (grow start)"   "🔨 Building ·" "$(animate_status "🔨 Building" 0)"
assert_equals "frame 1  = ✻"               "🔨 Building ✻" "$(animate_status "🔨 Building" 1)"
assert_equals "frame 2  = ✽"               "🔨 Building ✽" "$(animate_status "🔨 Building" 2)"
assert_equals "frame 3  = ✶"               "🔨 Building ✶" "$(animate_status "🔨 Building" 3)"
assert_equals "frame 4  = ✳"               "🔨 Building ✳" "$(animate_status "🔨 Building" 4)"
assert_equals "frame 5  = ✢ (peak)"        "🔨 Building ✢" "$(animate_status "🔨 Building" 5)"
assert_equals "frame 6  = ✳ (shrink)"      "🔨 Building ✳" "$(animate_status "🔨 Building" 6)"
assert_equals "frame 7  = ✶"               "🔨 Building ✶" "$(animate_status "🔨 Building" 7)"
assert_equals "frame 8  = ✽"               "🔨 Building ✽" "$(animate_status "🔨 Building" 8)"
assert_equals "frame 9  = ✻"               "🔨 Building ✻" "$(animate_status "🔨 Building" 9)"
assert_equals "frame 10 wraps to ·"        "🔨 Building ·" "$(animate_status "🔨 Building" 10)"
assert_equals "error not animated"         "🐛 Error"       "$(animate_status "🐛 Error" 1)"
assert_equals "passed not animated"        "✅ Tests passed" "$(animate_status "✅ Tests passed" 2)"
assert_equals "idle not animated"          "💤 Idle"        "$(animate_status "💤 Idle" 1)"

# ── Tests: set_title ──────────────────────────────────────────────────────────

echo ""
echo "set_title()"

# Capture escape sequences
title_output=$(set_title "test title" 2>/dev/null | cat -v)
# On iTerm2/modern terminals (TERM_PROGRAM unset in tests = iTerm2 path):
# title goes in OSC 1 (per-pane icon name); OSC 2 (window/app title) is cleared.
assert_contains "emits ESC]1; per-pane icon title" "^[]1;test title^G" "${title_output}"
assert_contains "emits ESC]2; cleared (empty)"     "^[]2;^G"           "${title_output}"

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

# ── Tests: status_to_priority ─────────────────────────────────────────────────

echo ""
echo "status_to_priority()"

assert_equals "Error → 100"         "100" "$(status_to_priority "🐛 Error")"
assert_equals "Tests failed → 90"   "90"  "$(status_to_priority "❌ Tests failed")"
assert_equals "Building → 80"       "80"  "$(status_to_priority "🔨 Building")"
assert_equals "Testing → 80"        "80"  "$(status_to_priority "🧪 Testing")"
assert_equals "Installing → 80"     "80"  "$(status_to_priority "📦 Installing")"
assert_equals "Pushing → 75"        "75"  "$(status_to_priority "⬆️ Pushing")"
assert_equals "Pulling → 75"        "75"  "$(status_to_priority "⬇️ Pulling")"
assert_equals "Merging → 75"        "75"  "$(status_to_priority "🔀 Merging")"
assert_equals "Docker → 70"         "70"  "$(status_to_priority "🐳 Docker")"
assert_equals "Delegating → 70"     "70"  "$(status_to_priority "🤖 Delegating")"
assert_equals "Editing → 65"        "65"  "$(status_to_priority "✏️ Editing")"
assert_equals "Tests passed → 60"   "60"  "$(status_to_priority "✅ Tests passed")"
assert_equals "Running → 55"        "55"  "$(status_to_priority "🖥️ Running")"
assert_equals "Reading → 55"        "55"  "$(status_to_priority "📖 Reading")"
assert_equals "Browsing → 55"       "55"  "$(status_to_priority "🌐 Browsing")"
assert_equals "unknown → 50"        "50"  "$(status_to_priority "🔧 SomeTool")"

# ── Tests: hook_runner.sh ─────────────────────────────────────────────────────

echo ""
echo "hook_runner.sh"

TMP_STATUS="${STATE_DIR}/test-status.txt"
TMP_CONTEXT="${STATE_DIR}/test-context.txt"
rm -f "${TMP_STATUS}" "${TMP_CONTEXT}"

# pre-tool: file editing tools
result=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"foo.sh"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Edit → ✏️ Editing"    "✏️ Editing"   "${result}"

result=$(echo '{"tool_name":"Write","tool_input":{"file_path":"out.txt"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Write → ✏️ Editing"   "✏️ Editing"   "${result}"

result=$(echo '{"tool_name":"Read","tool_input":{"file_path":"foo.sh"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Read → 📖 Reading"    "📖 Reading"   "${result}"

result=$(echo '{"tool_name":"WebFetch","tool_input":{"url":"https://example.com"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "WebFetch → 🌐 Browsing"  "🌐 Browsing"  "${result}"

result=$(echo '{"tool_name":"Task","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Task → 🤖 Delegating"  "🤖 Delegating"  "${result}"

# pre-tool: Bash sub-matching
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash npm test → 🧪 Testing"   "🧪 Testing"    "${result}"

result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npx jest --coverage"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash jest → 🧪 Testing"       "🧪 Testing"    "${result}"

result=$(echo '{"tool_name":"Bash","tool_input":{"command":"webpack --mode production"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash webpack → 🔨 Building"   "🔨 Building"   "${result}"

result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm install --save-dev react"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash npm install → 📦 Installing"  "📦 Installing"  "${result}"

result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash git push → ⬆️ Pushing"   "⬆️ Pushing"    "${result}"

result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git pull --rebase"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash git pull → ⬇️ Pulling"   "⬇️ Pulling"    "${result}"

result=$(echo '{"tool_name":"Bash","tool_input":{"command":"docker build -t myapp ."}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash docker → 🐳 Docker"      "🐳 Docker"     "${result}"

result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash generic → 🖥️ Running"    "🖥️ Running"    "${result}"

# user-prompt handler
rm -f "${TMP_CONTEXT}" "${TMP_STATUS}"
result=$(echo '{"prompt":"Fix the login bug in the auth module"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" user-prompt && cat "${TMP_CONTEXT}" 2>/dev/null || true)
assert_contains "user-prompt writes context"        "Fix the login bug"  "${result}"
result=$(cat "${TMP_STATUS}" 2>/dev/null || true)
assert_contains "user-prompt clears idle (writes 💭 Thinking)" "💭 Thinking" "${result}"

# user-prompt: no trailing newline (exactly how Claude Code sends hook payloads)
rm -f "${TMP_CONTEXT}" "${TMP_STATUS}"
result=$(printf '%s' '{"prompt":"Refactor the database layer"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" user-prompt && cat "${TMP_CONTEXT}" 2>/dev/null || true)
assert_contains "user-prompt: no trailing newline" "Refactor the database" "${result}"

# stop handler clears status file
printf '🧪 Testing' > "${TMP_STATUS}"
echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" stop
result=$(cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "stop empties status file"  "${result}"

# hook_runner exits 0 with no env vars set (safe no-op)
exit_code=0
echo '{"tool_name":"Edit"}' | bash "${LIB_DIR}/hook_runner.sh" pre-tool || exit_code=$?
assert_equals "no-op when CCP vars unset exits 0"  "0"  "${exit_code}"

# ── Tests: setup_ccp_hooks / teardown_ccp_hooks ───────────────────────────────

echo ""
echo "setup_ccp_hooks / teardown_ccp_hooks"

HOOKS_TMP_DIR=$(mktemp -d)

# setup creates settings file with CCP hooks
settings_path=$(setup_ccp_hooks "${HOOKS_TMP_DIR}" "${LIB_DIR}/hook_runner.sh")
assert_equals "settings file created" \
    "${HOOKS_TMP_DIR}/.claude/settings.local.json" "${settings_path}"

pre_count=$(jq '.hooks.PreToolUse | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "PreToolUse hook injected"       "1"  "${pre_count}"

prompt_count=$(jq '.hooks.UserPromptSubmit | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "UserPromptSubmit hook injected" "1"  "${prompt_count}"

stop_count=$(jq '.hooks.Stop | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "Stop hook injected"             "1"  "${stop_count}"

# hook command references the runner
hook_cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "${settings_path}" 2>/dev/null || echo "")
assert_contains "PreToolUse command references hook_runner" "hook_runner.sh" "${hook_cmd}"
assert_contains "PreToolUse command calls pre-tool"         "pre-tool"       "${hook_cmd}"

# hook has async:true and timeout:1000
hook_async=$(jq -r '.hooks.PreToolUse[0].hooks[0].async' "${settings_path}" 2>/dev/null || echo "")
assert_equals "PreToolUse async:true" "true" "${hook_async}"

# second setup deduplicates (idempotent — still exactly 1 entry, not 2)
setup_ccp_hooks "${HOOKS_TMP_DIR}" "${LIB_DIR}/hook_runner.sh" > /dev/null
pre_count2=$(jq '.hooks.PreToolUse | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "second setup deduplicates (stays at 1)" "1" "${pre_count2}"

# teardown removes the current-PID hook entry
teardown_ccp_hooks "${settings_path}"
assert_equals "settings file removed when empty after teardown" \
    "0" "$([ ! -f "${settings_path}" ]; echo $?)"

# teardown on non-existent file is a no-op
teardown_ccp_hooks "/nonexistent/path.json"
pass "teardown on missing file is safe no-op"

# teardown preserves non-CCP hooks
mkdir -p "${HOOKS_TMP_DIR}/.claude"
printf '%s\n' '{"hooks":{"PreToolUse":[{"_other":"data","hooks":[]}]}}' \
    > "${settings_path}"
setup_ccp_hooks "${HOOKS_TMP_DIR}" "${LIB_DIR}/hook_runner.sh" > /dev/null
teardown_ccp_hooks "${settings_path}"
remaining=$(jq '.hooks.PreToolUse | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "teardown preserves non-CCP hooks" "1" "${remaining}"

rm -rf "${HOOKS_TMP_DIR}"
rm -f "${TMP_STATUS}" "${TMP_CONTEXT}"

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
