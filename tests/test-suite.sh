#!/usr/bin/env bash
# tests/test-suite.sh - Claude Code Pulse test suite

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

# AI context summarization is opt-in (CCP_ENABLE_AI_CONTEXT=true).
# Don't set it here — tests must not invoke the Claude CLI.

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

assert_not_equals() {
    local name="$1"
    local unexpected="$2"
    local actual="$3"
    if [[ "${unexpected}" != "${actual}" ]]; then
        pass "${name}"
    else
        fail "${name}" "expected something other than: '${unexpected}'"
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

assert_not_contains() {
    local name="$1"
    local needle="$2"
    local haystack="$3"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        pass "${name}"
    else
        fail "${name}" "expected NOT to contain: '${needle}', got: '${haystack}'"
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


# ── Tests: set_title ──────────────────────────────────────────────────────────

echo ""
echo "set_title()"

# Capture escape sequences
CCP_TERMINAL_BACKEND="osc1"
title_output=$(set_title "test title" 2>/dev/null | cat -v)
# On iTerm2/modern terminals (TERM_PROGRAM unset in tests = iTerm2 path):
# title goes in OSC 1 (per-pane icon name); OSC 2 (window/app title) is cleared.
assert_contains "emits ESC]1; per-pane icon title" "^[]1;test title^G" "${title_output}"
assert_contains "emits ESC]2; cleared (empty)"     "^[]2;^G"           "${title_output}"
unset CCP_TERMINAL_BACKEND

# ── Tests: detect_terminal_backend ────────────────────────────────────────────

echo ""
echo "detect_terminal_backend()"

_saved_term_program="${TERM_PROGRAM-}"
_saved_tmux="${TMUX-}"
_saved_kitty_pid="${KITTY_PID-}"
unset TMUX KITTY_PID

TERM_PROGRAM="iTerm.app"
detect_terminal_backend
assert_equals "TERM_PROGRAM=iTerm.app → iterm2" "iterm2" "${CCP_TERMINAL_BACKEND}"

TERM_PROGRAM="Apple_Terminal"
detect_terminal_backend
assert_equals "TERM_PROGRAM=Apple_Terminal → apple-terminal" "apple-terminal" "${CCP_TERMINAL_BACKEND}"

TERM_PROGRAM="WezTerm"
detect_terminal_backend
assert_equals "TERM_PROGRAM=WezTerm → wezterm" "wezterm" "${CCP_TERMINAL_BACKEND}"

TERM_PROGRAM="ghostty"
detect_terminal_backend
assert_equals "TERM_PROGRAM=ghostty → ghostty" "ghostty" "${CCP_TERMINAL_BACKEND}"

unset TERM_PROGRAM KITTY_PID TMUX
detect_terminal_backend
assert_equals "no env vars → osc2" "osc2" "${CCP_TERMINAL_BACKEND}"

if [[ -n "${_saved_term_program}" ]]; then
    TERM_PROGRAM="${_saved_term_program}"
else
    unset TERM_PROGRAM
fi
if [[ -n "${_saved_tmux}" ]]; then
    TMUX="${_saved_tmux}"
else
    unset TMUX
fi
if [[ -n "${_saved_kitty_pid}" ]]; then
    KITTY_PID="${_saved_kitty_pid}"
else
    unset KITTY_PID
fi

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

# prune_dead_sessions cleans orphan state files for dead PIDs
echo '[]' > "${SESSION_FILE}"
# Create orphan state files for the fake dead PID
echo "📖 Reading" > "${STATE_DIR}/status.999999999.txt"
echo "some context" > "${STATE_DIR}/context.999999999.txt"
echo "main" > "${STATE_DIR}/branch.999999999.txt"
echo "999999999" > "${STATE_DIR}/monitor.999999999.pid"
echo "2" > "${STATE_DIR}/agents.999999999.txt"
# Inject the dead session so prune has something to remove
echo '[{"title":"Orphan","directory":"/tmp/orphan","started":"2026-01-01T00:00:00Z","pid":999999999}]' \
    > "${SESSION_FILE}"
prune_dead_sessions
orphan_status_exists=0
[[ -f "${STATE_DIR}/status.999999999.txt" ]] && orphan_status_exists=1
assert_equals "prune_dead_sessions removes orphan status file" "0" "${orphan_status_exists}"
orphan_context_exists=0
[[ -f "${STATE_DIR}/context.999999999.txt" ]] && orphan_context_exists=1
assert_equals "prune_dead_sessions removes orphan context file" "0" "${orphan_context_exists}"
orphan_branch_exists=0
[[ -f "${STATE_DIR}/branch.999999999.txt" ]] && orphan_branch_exists=1
assert_equals "prune_dead_sessions removes orphan branch file" "0" "${orphan_branch_exists}"
orphan_monitor_exists=0
[[ -f "${STATE_DIR}/monitor.999999999.pid" ]] && orphan_monitor_exists=1
assert_equals "prune_dead_sessions removes orphan monitor file" "0" "${orphan_monitor_exists}"
orphan_agents_exists=0
[[ -f "${STATE_DIR}/agents.999999999.txt" ]] && orphan_agents_exists=1
assert_equals "prune_dead_sessions removes orphan agents file" "0" "${orphan_agents_exists}"

# ── Tests: status_to_priority ─────────────────────────────────────────────────

echo ""
echo "status_to_priority()"

assert_equals "Error → 100"         "100" "$(status_to_priority "🐛 Error")"
assert_equals "Push failed → 100"   "100" "$(status_to_priority "🐛 Push failed")"
assert_equals "Pull failed → 100"   "100" "$(status_to_priority "🐛 Pull failed")"
assert_equals "Tests failed → 90"   "90"  "$(status_to_priority "❌ Tests failed")"
assert_equals "Awaiting approval → 88" "88" "$(status_to_priority "⏸️ Awaiting approval")"
assert_equals "Input needed → 85"   "85"  "$(status_to_priority "🙋 Input needed")"
assert_equals "Building → 80"       "80"  "$(status_to_priority "🔨 Building")"
assert_equals "Testing → 80"        "80"  "$(status_to_priority "🧪 Testing")"
assert_equals "Installing → 80"     "80"  "$(status_to_priority "📦 Installing")"
assert_equals "Pushing → 75"        "75"  "$(status_to_priority "⬆️ Pushing")"
assert_equals "Pulling → 75"        "75"  "$(status_to_priority "⬇️ Pulling")"
assert_equals "Merging → 75"        "75"  "$(status_to_priority "🔀 Merging")"
assert_equals "Rebasing → 75"       "75"  "$(status_to_priority "🔀 Rebasing")"
assert_equals "Cherry-picking → 75" "75"  "$(status_to_priority "🍒 Cherry-picking")"
assert_equals "Docker → 70"         "70"  "$(status_to_priority "🐳 Docker")"
assert_equals "Delegating → 70"     "70"  "$(status_to_priority "🤖 Delegating")"
assert_equals "Editing → 65"        "65"  "$(status_to_priority "✏️ Editing")"
assert_equals "Tests passed → 60"   "60"  "$(status_to_priority "✅ Tests passed")"
assert_equals "Completed → 60"      "60"  "$(status_to_priority "🏁 Completed")"
assert_equals "Running → 55"        "55"  "$(status_to_priority "🖥️ Running")"
assert_equals "Reading → 55"        "55"  "$(status_to_priority "📖 Reading")"
assert_equals "Browsing → 55"       "55"  "$(status_to_priority "🌐 Browsing")"
assert_equals "Working → 55"        "55"  "$(status_to_priority "🔧 Working")"
assert_equals "Sending → 55"        "55"  "$(status_to_priority "📤 Sending")"
assert_equals "Session started → 52" "52" "$(status_to_priority "🚀 Session started")"
assert_equals "Monitoring → 20"     "20"  "$(status_to_priority "📡 Monitoring")"
assert_equals "unknown → 50"        "50"  "$(status_to_priority "🔧 SomeTool")"

# ── Tests: hook_runner.sh ─────────────────────────────────────────────────────

echo ""
echo "hook_runner.sh"

TMP_STATUS="${STATE_DIR}/test-status.txt"
TMP_CONTEXT="${STATE_DIR}/test-context.txt"
rm -f "${TMP_STATUS}" "${TMP_CONTEXT}"

# pre-tool: file editing tools
# Note: rm -f before each test ensures priority-aware writes start from a clean state
rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"foo.sh"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Edit → ✏️ Editing"    "✏️ Editing"   "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Write","tool_input":{"file_path":"out.txt"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Write → ✏️ Editing"   "✏️ Editing"   "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Read","tool_input":{"file_path":"foo.sh"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Read → 📖 Reading"    "📖 Reading"   "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"WebFetch","tool_input":{"url":"https://example.com"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "WebFetch → 🌐 Browsing"  "🌐 Browsing"  "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Task","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Task → 🤖 Delegating"  "🤖 Delegating"  "${result}"

# pre-tool: Bash sub-matching
rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash npm test → 🧪 Testing"   "🧪 Testing"    "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npx jest --coverage"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash jest → 🧪 Testing"       "🧪 Testing"    "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"webpack --mode production"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash webpack → 🔨 Building"   "🔨 Building"   "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm install --save-dev react"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash npm install → 📦 Installing"  "📦 Installing"  "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash git push → ⬆️ Pushing"   "⬆️ Pushing"    "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git pull --rebase"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash git pull → ⬇️ Pulling"   "⬇️ Pulling"    "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git rebase main"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash git rebase → 🔀 Rebasing"         "🔀 Rebasing"         "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git rebase --continue"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash git rebase --continue → 🔀 Rebasing" "🔀 Rebasing"      "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git cherry-pick abc123"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash git cherry-pick → 🍒 Cherry-picking" "🍒 Cherry-picking" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git cherry-pick --abort"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash git cherry-pick --abort → 🍒 Cherry-picking" "🍒 Cherry-picking" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"docker build -t myapp ."}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash docker → 🐳 Docker"      "🐳 Docker"     "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "Bash generic → 🖥️ Running"    "🖥️ Running"    "${result}"

# pre-tool: ToolSearch (Claude's built-in tool discovery)
rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"ToolSearch","tool_input":{"query":"slack"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "ToolSearch → 📖 Reading"       "📖 Reading"    "${result}"

# pre-tool: MCP tool classification (action verb heuristic)
rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"mcp__filesystem__read_file","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "mcp read_file → 📖 Reading"    "📖 Reading"    "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"mcp__filesystem__list_directory","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "mcp list_directory → 📖 Reading" "📖 Reading"  "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"mcp__github__search_code","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "mcp search_code → 📖 Reading"  "📖 Reading"    "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"mcp__filesystem__write_file","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "mcp write_file → ✏️ Editing"   "✏️ Editing"    "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"mcp__github__create_pull_request","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "mcp create_pull_request → ✏️ Editing" "✏️ Editing" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"mcp__github__add_issue_comment","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "mcp add_issue_comment → 📤 Sending" "📤 Sending" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"mcp__playwright__browser_navigate","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "mcp browser_navigate → 🌐 Browsing" "🌐 Browsing" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"mcp__playwright__browser_click","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "mcp browser_click → 🌐 Browsing"    "🌐 Browsing" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"mcp__plugin_context7__resolve-library-id","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "mcp resolve-library-id → 📖 Reading" "📖 Reading" "${result}"

# pre-tool: completely unknown tool → generic fallback
rm -f "${TMP_STATUS}"
result=$(echo '{"tool_name":"SomeRandomTool","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "unknown tool → 🔧 Working"     "🔧 Working"    "${result}"

# user-prompt handler
rm -f "${TMP_CONTEXT}" "${TMP_STATUS}"
result=$(echo '{"prompt":"Fix the login bug in the auth module"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" user-prompt && cat "${TMP_CONTEXT}" 2>/dev/null || true)
assert_contains "user-prompt writes context"        "Fix the login bug"  "${result}"
result=$(cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "user-prompt writes 💭 Thinking to status file" "💭 Thinking" "${result}"

# user-prompt: no trailing newline (exactly how Claude Code sends hook payloads)
rm -f "${TMP_CONTEXT}" "${TMP_STATUS}"
result=$(printf '%s' '{"prompt":"Refactor the database layer"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" user-prompt && cat "${TMP_CONTEXT}" 2>/dev/null || true)
assert_contains "user-prompt: no trailing newline" "Refactor the database" "${result}"

echo ""
echo "user-prompt: context sanitization"

TMP_STATUS="${STATE_DIR}/test-sanitize-status.txt"
TMP_CONTEXT="${STATE_DIR}/test-sanitize-context.txt"

# Pasted terminal content with venv prefix
rm -f "${TMP_CONTEXT}" "${TMP_STATUS}"
result=$(printf '%s' '{"prompt":"(venv) brianruggieri@Flexias-MacBook-Pro candidate-eval % fix the bug"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" user-prompt && cat "${TMP_CONTEXT}" 2>/dev/null || true)
assert_not_contains "sanitize: venv prefix stripped" "(venv)" "${result}"
assert_contains "sanitize: actual content preserved" "fix the bug" "${result}"

# Pasted terminal with user@host prefix (no venv)
rm -f "${TMP_CONTEXT}" "${TMP_STATUS}"
result=$(printf '%s' '{"prompt":"user@hostname project % do the thing"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" user-prompt && cat "${TMP_CONTEXT}" 2>/dev/null || true)
assert_not_contains "sanitize: user@host stripped" "user@hostname" "${result}"

# Shell prompt character stripped
rm -f "${TMP_CONTEXT}" "${TMP_STATUS}"
result=$(printf '%s' '{"prompt":"$ npm test"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" user-prompt && cat "${TMP_CONTEXT}" 2>/dev/null || true)
assert_equals "sanitize: $ prompt stripped" "npm test" "${result}"

rm -f "${TMP_STATUS}" "${TMP_CONTEXT}"

# stop handler clears status file
printf '🧪 Testing' > "${TMP_STATUS}"
echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" stop
result=$(cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "stop empties status file"  "${result}"

# ── Tests: stop-hook haiku summarization ──────────────────────────────────────

echo ""
echo "stop-hook haiku summarization"

# Set up a mock claude binary that captures stdin and outputs a fixed summary
MOCK_CLAUDE_DIR=$(mktemp -d)
cat > "${MOCK_CLAUDE_DIR}/claude" <<'MOCK'
#!/usr/bin/env bash
# Mock claude binary — reads stdin, outputs a fixed summary
cat > /dev/null  # consume stdin
echo "Fixed Auth Login Flow"
MOCK
chmod +x "${MOCK_CLAUDE_DIR}/claude"

# Each test uses a unique context file to avoid races with disowned background subprocesses
HAIKU_CTX_1="${STATE_DIR}/haiku-ctx-1.txt"
HAIKU_CTX_2="${STATE_DIR}/haiku-ctx-2.txt"
HAIKU_CTX_3="${STATE_DIR}/haiku-ctx-3.txt"
HAIKU_CTX_4="${STATE_DIR}/haiku-ctx-4.txt"
HAIKU_CTX_5="${STATE_DIR}/haiku-ctx-5.txt"
HAIKU_CTX_6="${STATE_DIR}/haiku-ctx-6.txt"

# Test 1: stop hook with AI context enabled + last_assistant_message → haiku writes summary
rm -f "${TMP_STATUS}" "${HAIKU_CTX_1}"
printf '🧪 Testing' > "${TMP_STATUS}"
printf '%s' '{"last_assistant_message":"I fixed the authentication flow by updating the login handler to properly validate tokens."}' \
    | CLAUDECODE=1 \
      CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${HAIKU_CTX_1}" \
      CCP_ENABLE_AI_CONTEXT=true CCP_CLAUDE_BIN="${MOCK_CLAUDE_DIR}/claude" \
      bash "${LIB_DIR}/hook_runner.sh" stop
result=""
for _ in {1..20}; do
    [[ -f "${HAIKU_CTX_1}" ]] && result=$(cat "${HAIKU_CTX_1}" 2>/dev/null || true)
    [[ -n "${result}" ]] && break
    sleep 0.25
done
assert_equals "stop-haiku: writes summary to context file" "Fixed Auth Login Flow" "${result}"
# Also verify status was still cleared (existing behavior preserved)
status_result=$(cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "stop-haiku: status still cleared" "${status_result}"

# Test 2: stop hook skips haiku when CCP_ENABLE_AI_CONTEXT is not true
rm -f "${TMP_STATUS}" "${HAIKU_CTX_2}"
printf '🧪 Testing' > "${TMP_STATUS}"
printf '%s' '{"last_assistant_message":"I fixed the bug."}' \
    | CLAUDECODE=1 \
      CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${HAIKU_CTX_2}" \
      CCP_ENABLE_AI_CONTEXT=false CCP_CLAUDE_BIN="${MOCK_CLAUDE_DIR}/claude" \
      bash "${LIB_DIR}/hook_runner.sh" stop
sleep 1
result=$(cat "${HAIKU_CTX_2}" 2>/dev/null || true)
assert_empty "stop-haiku: skips when AI context disabled" "${result}"

# Test 3: stop hook skips haiku when last_assistant_message is empty
rm -f "${TMP_STATUS}" "${HAIKU_CTX_3}"
printf '🧪 Testing' > "${TMP_STATUS}"
printf '%s' '{"last_assistant_message":""}' \
    | CLAUDECODE=1 \
      CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${HAIKU_CTX_3}" \
      CCP_ENABLE_AI_CONTEXT=true CCP_CLAUDE_BIN="${MOCK_CLAUDE_DIR}/claude" \
      bash "${LIB_DIR}/hook_runner.sh" stop
sleep 1
result=$(cat "${HAIKU_CTX_3}" 2>/dev/null || true)
assert_empty "stop-haiku: skips when last_assistant_message is empty" "${result}"

# Test 4: stop hook skips haiku when last_assistant_message field is missing from JSON
rm -f "${TMP_STATUS}" "${HAIKU_CTX_4}"
printf '🧪 Testing' > "${TMP_STATUS}"
printf '%s' '{"some_other_field":"hello"}' \
    | CLAUDECODE=1 \
      CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${HAIKU_CTX_4}" \
      CCP_ENABLE_AI_CONTEXT=true CCP_CLAUDE_BIN="${MOCK_CLAUDE_DIR}/claude" \
      bash "${LIB_DIR}/hook_runner.sh" stop
sleep 1
result=$(cat "${HAIKU_CTX_4}" 2>/dev/null || true)
assert_empty "stop-haiku: skips when last_assistant_message field missing" "${result}"

# Test 5: messages >1000 chars are truncated to first 500 + "..." + last 500
rm -f "${TMP_STATUS}" "${HAIKU_CTX_5}"
printf '🧪 Testing' > "${TMP_STATUS}"
# Build a mock claude that echoes back a snippet of what it received on stdin
# so we can verify truncation happened
MOCK_TRUNC_DIR=$(mktemp -d)
cat > "${MOCK_TRUNC_DIR}/claude" <<'MOCK'
#!/usr/bin/env bash
# Mock claude binary — captures stdin content to a file for inspection
input=$(cat)
# Write the received input to a sidecar file for the test to inspect
echo "${input}" > "${MOCK_TRUNC_DIR_SIDECAR}"
echo "Truncation Test Summary"
MOCK
chmod +x "${MOCK_TRUNC_DIR}/claude"
MOCK_SIDECAR="${MOCK_TRUNC_DIR}/captured_input.txt"

# Build a 1200-char message: 600 A's + 600 B's
long_msg=$(printf '%0600d' 0 | tr '0' 'A')$(printf '%0600d' 0 | tr '0' 'B')
json_long=$(printf '{"last_assistant_message":"%s"}' "${long_msg}")
printf '%s' "${json_long}" \
    | CLAUDECODE=1 \
      CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${HAIKU_CTX_5}" \
      CCP_ENABLE_AI_CONTEXT=true CCP_CLAUDE_BIN="${MOCK_TRUNC_DIR}/claude" \
      MOCK_TRUNC_DIR_SIDECAR="${MOCK_SIDECAR}" \
      bash "${LIB_DIR}/hook_runner.sh" stop
result=""
for _ in {1..20}; do
    [[ -f "${HAIKU_CTX_5}" ]] && result=$(cat "${HAIKU_CTX_5}" 2>/dev/null || true)
    [[ -n "${result}" ]] && break
    sleep 0.25
done
assert_equals "stop-haiku: truncated message produces summary" "Truncation Test Summary" "${result}"
# Verify the captured input contains " ... " (truncation marker)
if [[ -f "${MOCK_SIDECAR}" ]]; then
    captured=$(cat "${MOCK_SIDECAR}" 2>/dev/null || true)
    if [[ "${captured}" == *" ... "* ]]; then
        pass "stop-haiku: truncated message contains ' ... ' marker"
    else
        fail "stop-haiku: truncated message contains ' ... ' marker" "captured input did not contain ' ... '"
    fi
else
    fail "stop-haiku: truncated message contains ' ... ' marker" "sidecar file not found"
fi
rm -rf "${MOCK_TRUNC_DIR}"

# Test 6: CLAUDECODE env var is unset in the haiku subprocess
rm -f "${TMP_STATUS}" "${HAIKU_CTX_6}"
printf '🧪 Testing' > "${TMP_STATUS}"
MOCK_CLAUDECODE_DIR=$(mktemp -d)
cat > "${MOCK_CLAUDECODE_DIR}/claude" <<'MOCK'
#!/usr/bin/env bash
cat > /dev/null
if [[ -z "${CLAUDECODE:-}" ]]; then
    echo "CLAUDECODE_ABSENT"
else
    echo "CLAUDECODE_PRESENT"
fi
MOCK
chmod +x "${MOCK_CLAUDECODE_DIR}/claude"
printf '%s' '{"last_assistant_message":"I fixed the bug by adding a null check."}' \
    | CLAUDECODE=1 \
      CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${HAIKU_CTX_6}" \
      CCP_ENABLE_AI_CONTEXT=true CCP_CLAUDE_BIN="${MOCK_CLAUDECODE_DIR}/claude" \
      bash "${LIB_DIR}/hook_runner.sh" stop
result=""
for _ in {1..20}; do
    [[ -f "${HAIKU_CTX_6}" ]] && result=$(cat "${HAIKU_CTX_6}" 2>/dev/null || true)
    [[ -n "${result}" ]] && break
    sleep 0.25
done
assert_equals "stop-haiku: CLAUDECODE is unset in haiku subprocess" "CLAUDECODE_ABSENT" "${result}"
rm -rf "${MOCK_CLAUDECODE_DIR}"

rm -rf "${MOCK_CLAUDE_DIR}"
rm -f "${TMP_STATUS}" "${TMP_CONTEXT}"

# post-tool handler writes completion statuses from Bash output
printf '🧪 Testing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":"3 tests passed"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: tests passed → ✅ Tests passed" "✅ Tests passed" "${result}"

printf '🧪 Testing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":"2 tests failed"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: tests failed → ❌ Tests failed" "❌ Tests failed" "${result}"

printf '🧪 Testing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix\""},"tool_response":"[main abc123] fix"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: git commit output → 💾 Committed" "💾 Committed" "${result}"

printf '✏️ Editing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Read","tool_input":{},"tool_response":"3 tests passed"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: non-Bash leaves status unchanged" "✏️ Editing" "${result}"

# post-tool: stale approval/input states cleared after Bash tool completes
# Regression: PermissionRequest/Notification hooks fire async and can overwrite
# the active status set by PreToolUse.  PostToolUse must always write to the
# status file so these stale states don't persist after the tool finishes.

# Generic Bash (no special output) clears "Awaiting approval" → idle
printf '⏸️ Awaiting approval' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"tool_response":"file.txt"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "post-tool: generic Bash clears stale ⏸️ Awaiting approval" "${result}"

# Generic Bash (no special output) clears "Input needed" → idle
printf '🙋 Input needed' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"cat README.md"},"tool_response":"contents"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "post-tool: generic Bash clears stale 🙋 Input needed" "${result}"

# Test-pass Bash still writes ✅ even when status was "Awaiting approval"
printf '⏸️ Awaiting approval' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":"5 tests passed"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: tests passed overrides stale ⏸️ Awaiting approval" "✅ Tests passed" "${result}"

# Test-fail Bash still writes ❌ even when status was "Awaiting approval"
printf '⏸️ Awaiting approval' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":"2 tests failed"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: tests failed overrides stale ⏸️ Awaiting approval" "❌ Tests failed" "${result}"

# Commit Bash still writes 💾 even when status was "Awaiting approval"
printf '⏸️ Awaiting approval' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix\""},"tool_response":"[main abc123] fix"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: commit overrides stale ⏸️ Awaiting approval" "💾 Committed" "${result}"

# Generic Bash (no special output) clears any stale active status → idle
# (previously would leave e.g. "🖥️ Running" from a prior pre-tool call)
printf '🖥️ Running' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo done"},"tool_response":"done"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "post-tool: generic Bash clears stale 🖥️ Running on completion" "${result}"

# Non-Bash tools still leave status unchanged (no post-tool writes for Edit/Read/etc.)
printf '⏸️ Awaiting approval' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Edit","tool_input":{},"tool_response":""}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: non-Bash (Edit) does not clear status" "⏸️ Awaiting approval" "${result}"

printf '🧪 Testing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm test"},"error":"exit 1"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool-failure && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool-failure: Bash test command → ❌ Tests failed" "❌ Tests failed" "${result}"

printf '✏️ Editing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"error":"boom"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool-failure && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool-failure: generic failure → 🐛 Error" "🐛 Error" "${result}"

# post-tool: push failure detection
printf '⬆️ Pushing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"tool_response":"error: failed to push some refs to '\''origin'\''"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: git push error: failed to push → 🐛 Push failed" "🐛 Push failed" "${result}"

printf '⬆️ Pushing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"tool_response":"To github.com:user/repo.git\n ! [rejected]        main -> main (fetch first)"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: git push ! [rejected] → 🐛 Push failed" "🐛 Push failed" "${result}"

printf '⬆️ Pushing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"tool_response":"! [remote rejected] main -> main (protected branch)"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: git push ! [remote rejected] → 🐛 Push failed" "🐛 Push failed" "${result}"

printf '⬆️ Pushing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"tool_response":"ERROR: Repository not found."}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: git push ERROR: → 🐛 Push failed" "🐛 Push failed" "${result}"

# Successful push clears status
printf '⬆️ Pushing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"tool_response":"To github.com:user/repo.git\n   abc1234..def5678  main -> main"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "post-tool: git push success clears status" "${result}"

# post-tool: pull failure detection
printf '⬇️ Pulling' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git pull origin main"},"tool_response":"CONFLICT (content): Merge conflict in src/foo.ts\nAutomatic merge failed; fix conflicts and then commit the result."}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: git pull CONFLICT → 🐛 Pull failed" "🐛 Pull failed" "${result}"

printf '⬇️ Pulling' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git pull"},"tool_response":"error: Your local changes to the following files would be overwritten by merge"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: git pull error: → 🐛 Pull failed" "🐛 Pull failed" "${result}"

printf '⬇️ Pulling' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git pull origin main"},"tool_response":"fatal: refusing to merge unrelated histories"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: git pull fatal: → 🐛 Pull failed" "🐛 Pull failed" "${result}"

printf '⬇️ Pulling' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git pull"},"tool_response":"Automatic merge failed; fix conflicts and then commit the result."}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "post-tool: git pull Automatic merge failed → 🐛 Pull failed" "🐛 Pull failed" "${result}"

# Successful pull clears status
printf '⬇️ Pulling' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git pull origin main"},"tool_response":"Already up to date."}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "post-tool: git pull success clears status" "${result}"

# post-tool: branch change detection writes CCP_BRANCH_FILE
# hook_runner.sh detects git checkout/switch/branch commands and calls
# `git rev-parse --abbrev-ref HEAD` in the current directory to capture the
# new branch.  Since tests can't actually switch branches, we verify the
# detection triggers and writes the current HEAD.
TMP_BRANCH="${STATE_DIR}/test-branch.txt"
rm -f "${TMP_BRANCH}"

expected_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git checkout feature/new"},"tool_response":"Switched to branch feature/new"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_BRANCH_FILE="${TMP_BRANCH}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_BRANCH}" 2>/dev/null || true)
assert_equals "post-tool: git checkout writes branch file" "${expected_branch}" "${result}"

rm -f "${TMP_BRANCH}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git switch main"},"tool_response":"Switched to branch main"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_BRANCH_FILE="${TMP_BRANCH}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_BRANCH}" 2>/dev/null || true)
assert_equals "post-tool: git switch writes branch file" "${expected_branch}" "${result}"

rm -f "${TMP_BRANCH}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git branch new-feature"},"tool_response":""}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_BRANCH_FILE="${TMP_BRANCH}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_BRANCH}" 2>/dev/null || true)
assert_equals "post-tool: git branch writes branch file" "${expected_branch}" "${result}"

rm -f "${TMP_BRANCH}"
echo '{"tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":"3 tests passed"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_BRANCH_FILE="${TMP_BRANCH}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool
if [[ ! -f "${TMP_BRANCH}" ]]; then
    pass "post-tool: non-git command does not create branch file"
else
    fail "post-tool: non-git command does not create branch file" "file exists with: $(cat "${TMP_BRANCH}")"
fi

rm -f "${TMP_BRANCH}"
echo '{"tool_name":"Bash","tool_input":{"command":"git checkout main"},"tool_response":"Switched to branch main"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool
if [[ ! -f "${TMP_BRANCH}" ]]; then
    pass "post-tool: no CCP_BRANCH_FILE → no branch file created"
else
    fail "post-tool: no CCP_BRANCH_FILE → no branch file created" "file exists with: $(cat "${TMP_BRANCH}")"
fi

rm -f "${TMP_BRANCH}"

# post-tool: branch detection fires even when CCP_STATUS_FILE is unset
# (branch-only usage — verifies the mid-handler guard includes CCP_BRANCH_FILE)
TMP_BRANCH="${STATE_DIR}/test-branch-only.txt"
rm -f "${TMP_BRANCH}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git checkout main"},"tool_response":"Switched to branch main"}' \
    | CCP_BRANCH_FILE="${TMP_BRANCH}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_BRANCH}" 2>/dev/null || true)
assert_equals "post-tool: branch detection fires without CCP_STATUS_FILE" "${expected_branch}" "${result}"
rm -f "${TMP_BRANCH}"

echo ""
echo "post-tool: git commit message capture"

TMP_STATUS="${STATE_DIR}/test-commit-ctx-status.txt"
TMP_CONTEXT="${STATE_DIR}/test-commit-ctx-context.txt"

# post-tool: git commit writes commit subject to context file
rm -f "${TMP_STATUS}" "${TMP_CONTEXT}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"Fix null check in parser\""},"tool_response":"[main abc1234] Fix null check in parser\n 1 file changed, 2 insertions(+)"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_CONTEXT}" 2>/dev/null || true)
assert_equals "commit: subject written to context file" "Fix null check in parser" "${result}"
# Status should also be set
status_result=$(cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "commit: status set to Committed" "💾 Committed" "${status_result}"

rm -f "${TMP_STATUS}" "${TMP_CONTEXT}"

# event handler: quiet (default) high-signal coverage
result=$(echo '{"permission":"needed"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event PermissionRequest && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event quiet: PermissionRequest → ⏸️ Awaiting approval" "⏸️ Awaiting approval" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"message":"Action required: choose one option"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event Notification && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event quiet: Notification action-needed → 🙋 Input needed" "🙋 Input needed" "${result}"

printf '✏️ Editing' > "${TMP_STATUS}"
result=$(echo '{"message":"Background refresh complete"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event Notification && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event quiet: generic Notification leaves status unchanged" "✏️ Editing" "${result}"

result=$(echo '{"task":"done"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event TaskCompleted && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event quiet: TaskCompleted → 🏁 Completed" "🏁 Completed" "${result}"

result=$(echo '{"reason":"clear"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event SessionEnd && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event quiet: SessionEnd clear → 🏁 Completed" "🏁 Completed" "${result}"

printf '✏️ Editing' > "${TMP_STATUS}"
result=$(echo '{"reason":"manual"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event SessionStart && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event quiet: SessionStart suppressed (verbose-only)" "✏️ Editing" "${result}"

printf '✏️ Editing' > "${TMP_STATUS}"
result=$(echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event UnknownFutureEvent && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event quiet: unknown event suppressed" "✏️ Editing" "${result}"

# event handler: verbose profile
rm -f "${TMP_STATUS}"
result=$(echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=verbose \
      bash "${LIB_DIR}/hook_runner.sh" event SessionStart && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event verbose: SessionStart → 🚀 Session started" "🚀 Session started" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=verbose \
      bash "${LIB_DIR}/hook_runner.sh" event PreCompact && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event verbose: PreCompact → 🧠 Compacting" "🧠 Compacting" "${result}"

TMP_AGENTS="${STATE_DIR}/test-agents.txt"
rm -f "${TMP_AGENTS}"

# SubagentStart increments counter: 0 → 1
rm -f "${TMP_STATUS}"
result=$(echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_AGENTS_FILE="${TMP_AGENTS}" CCP_STATUS_PROFILE=verbose \
      bash "${LIB_DIR}/hook_runner.sh" event SubagentStart && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event verbose: SubagentStart → 🤖 Subagent started" "🤖 Subagent started" "${result}"
result=$(cat "${TMP_AGENTS}" 2>/dev/null || true)
assert_equals "SubagentStart: counter 0→1" "1" "${result}"

# SubagentStart increments again: 1 → 2
echo '1' > "${TMP_AGENTS}"
echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_AGENTS_FILE="${TMP_AGENTS}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event SubagentStart
result=$(cat "${TMP_AGENTS}" 2>/dev/null || true)
assert_equals "SubagentStart: counter 1→2" "2" "${result}"

# SubagentStop decrements: 2 → 1
echo '2' > "${TMP_AGENTS}"
echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_AGENTS_FILE="${TMP_AGENTS}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event SubagentStop
result=$(cat "${TMP_AGENTS}" 2>/dev/null || true)
assert_equals "SubagentStop: counter 2→1" "1" "${result}"

# SubagentStop at 1 removes the file: 1 → gone
echo '1' > "${TMP_AGENTS}"
echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_AGENTS_FILE="${TMP_AGENTS}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event SubagentStop
if [[ ! -f "${TMP_AGENTS}" ]]; then
    pass "SubagentStop: counter 1→0 removes agents file"
else
    fail "SubagentStop: counter 1→0 removes agents file" "file still exists with: $(cat "${TMP_AGENTS}")"
fi

# SubagentStop with no agents file is a safe no-op (never goes negative)
rm -f "${TMP_AGENTS}"
echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_AGENTS_FILE="${TMP_AGENTS}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event SubagentStop
if [[ ! -f "${TMP_AGENTS}" ]]; then
    pass "SubagentStop: no agents file → safe no-op, no negative value"
else
    fail "SubagentStop: no agents file → safe no-op, no negative value" "file created with: $(cat "${TMP_AGENTS}")"
fi

# SubagentStop in verbose still writes status even after decrement
echo '1' > "${TMP_AGENTS}"
rm -f "${TMP_STATUS}"
result=$(echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_AGENTS_FILE="${TMP_AGENTS}" CCP_STATUS_PROFILE=verbose \
      bash "${LIB_DIR}/hook_runner.sh" event SubagentStop && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event verbose: SubagentStop → ✅ Subagent finished" "✅ Subagent finished" "${result}"

# No CCP_AGENTS_FILE set → SubagentStart/Stop are no-ops for counter, verbose status still fires
rm -f "${TMP_AGENTS}"
rm -f "${TMP_STATUS}"
result=$(echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=verbose \
      bash "${LIB_DIR}/hook_runner.sh" event SubagentStart && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "SubagentStart: no CCP_AGENTS_FILE → verbose status still written" "🤖 Subagent started" "${result}"
if [[ ! -f "${TMP_AGENTS}" ]]; then
    pass "SubagentStart: no CCP_AGENTS_FILE → no counter file created"
else
    fail "SubagentStart: no CCP_AGENTS_FILE → no counter file created" "unexpected file: $(cat "${TMP_AGENTS}")"
fi

rm -f "${TMP_AGENTS}"

rm -f "${TMP_STATUS}"
result=$(echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=verbose \
      bash "${LIB_DIR}/hook_runner.sh" event TeammateIdle && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event verbose: TeammateIdle → 👥 Teammate idle" "👥 Teammate idle" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=verbose \
      bash "${LIB_DIR}/hook_runner.sh" event ConfigChange && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event verbose: ConfigChange → ⚙️ Config changed" "⚙️ Config changed" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=verbose \
      bash "${LIB_DIR}/hook_runner.sh" event WorktreeCreate && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event verbose: WorktreeCreate fallback → 🔔 WorktreeCreate" "🔔 WorktreeCreate" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=verbose \
      bash "${LIB_DIR}/hook_runner.sh" event WorktreeRemove && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event verbose: WorktreeRemove fallback → 🔔 WorktreeRemove" "🔔 WorktreeRemove" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{"message":"Background refresh complete"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=verbose \
      bash "${LIB_DIR}/hook_runner.sh" event Notification && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event verbose: generic Notification → 🔔 Notification" "🔔 Notification" "${result}"

rm -f "${TMP_STATUS}"
result=$(echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=verbose \
      bash "${LIB_DIR}/hook_runner.sh" event UnknownFutureEvent && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "event verbose: unknown event fallback" "🔔 UnknownFutureEvent" "${result}"

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

post_count=$(jq '.hooks.PostToolUse | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "PostToolUse hook injected"      "1"  "${post_count}"

post_fail_count=$(jq '.hooks.PostToolUseFailure | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "PostToolUseFailure hook injected" "1" "${post_fail_count}"

permission_count=$(jq '.hooks.PermissionRequest | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "PermissionRequest hook injected" "1" "${permission_count}"

notification_count=$(jq '.hooks.Notification | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "Notification hook injected" "1" "${notification_count}"

task_completed_count=$(jq '.hooks.TaskCompleted | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "TaskCompleted hook injected" "1" "${task_completed_count}"

session_start_count=$(jq '.hooks.SessionStart | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "SessionStart hook injected" "1" "${session_start_count}"

session_end_count=$(jq '.hooks.SessionEnd | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "SessionEnd hook injected" "1" "${session_end_count}"

pre_compact_count=$(jq '.hooks.PreCompact | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "PreCompact hook injected" "1" "${pre_compact_count}"

sub_start_count=$(jq '.hooks.SubagentStart | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "SubagentStart hook injected" "1" "${sub_start_count}"

sub_stop_count=$(jq '.hooks.SubagentStop | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "SubagentStop hook injected" "1" "${sub_stop_count}"

teammate_idle_count=$(jq '.hooks.TeammateIdle | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "TeammateIdle hook injected" "1" "${teammate_idle_count}"

config_change_count=$(jq '.hooks.ConfigChange | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "ConfigChange hook injected" "1" "${config_change_count}"

worktree_create_count=$(jq '.hooks.WorktreeCreate | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "WorktreeCreate not injected (lifecycle hook, not notification)" "0" "${worktree_create_count}"

worktree_remove_count=$(jq '.hooks.WorktreeRemove | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "WorktreeRemove not injected (lifecycle hook, not notification)" "0" "${worktree_remove_count}"

# hook command references the runner
hook_cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "${settings_path}" 2>/dev/null || echo "")
assert_contains "PreToolUse command references hook_runner" "hook_runner.sh" "${hook_cmd}"
assert_contains "PreToolUse command calls pre-tool"         "pre-tool"       "${hook_cmd}"

# hook has async:true
hook_async=$(jq -r '.hooks.PreToolUse[0].hooks[0].async' "${settings_path}" 2>/dev/null || echo "")
assert_equals "PreToolUse async:true" "true" "${hook_async}"

# second setup deduplicates (idempotent — still exactly 1 entry, not 2)
setup_ccp_hooks "${HOOKS_TMP_DIR}" "${LIB_DIR}/hook_runner.sh" > /dev/null
pre_count2=$(jq '.hooks.PreToolUse | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "second setup deduplicates (stays at 1)" "1" "${pre_count2}"
post_count2=$(jq '.hooks.PostToolUse | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "second setup deduplicates PostToolUse (stays at 1)" "1" "${post_count2}"
post_fail_count2=$(jq '.hooks.PostToolUseFailure | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "second setup deduplicates PostToolUseFailure (stays at 1)" "1" "${post_fail_count2}"
session_start_count2=$(jq '.hooks.SessionStart | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "second setup deduplicates SessionStart (stays at 1)" "1" "${session_start_count2}"

# cross-path dedup: stale entry from a different path (e.g. source repo) is cleaned up
mkdir -p "${HOOKS_TMP_DIR}/.claude"
printf '%s\n' \
    '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"bash \"/other/path/hook_runner.sh\" user-prompt"}]}]}}' \
    > "${settings_path}"
setup_ccp_hooks "${HOOKS_TMP_DIR}" "${LIB_DIR}/hook_runner.sh" > /dev/null
stale_count=$(jq '.hooks.UserPromptSubmit | length' "${settings_path}" 2>/dev/null || echo 0)
assert_equals "stale path-variant entry deduped on setup (stays at 1)" "1" "${stale_count}"

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

# ── Tests: bin/ccp status profile parsing ─────────────────────────────────────

echo ""
echo "bin/ccp --status-profile"

BIN_CCP="${PROJECT_DIR}/bin/ccp"
CLI_TMP_DIR=$(mktemp -d)
CLI_STATE_DIR="${CLI_TMP_DIR}/state"
mkdir -p "${CLI_STATE_DIR}"
CLI_SESSION_FILE="${CLI_STATE_DIR}/sessions.json"
echo '[]' > "${CLI_SESSION_FILE}"

cli_exit=0
CCP_CLAUDE_CMD=/usr/bin/true CCP_STATUS_PROFILE=quiet \
STATE_DIR="${CLI_STATE_DIR}" SESSION_FILE="${CLI_SESSION_FILE}" \
"${BIN_CCP}" --status-profile verbose --no-dynamic "status-profile test" \
    >/dev/null 2>/dev/null || cli_exit=$?
assert_equals "bin/ccp: --status-profile verbose succeeds" "0" "${cli_exit}"

cli_exit=0
cli_err="${CLI_TMP_DIR}/invalid-profile.err"
CCP_CLAUDE_CMD=/usr/bin/true CCP_STATUS_PROFILE=quiet \
STATE_DIR="${CLI_STATE_DIR}" SESSION_FILE="${CLI_SESSION_FILE}" \
"${BIN_CCP}" --status-profile noisy --no-dynamic "status-profile test" \
    >/dev/null 2>"${cli_err}" || cli_exit=$?
assert_equals "bin/ccp: invalid --status-profile exits 1" "1" "${cli_exit}"
assert_contains "bin/ccp: invalid profile emits clear error" \
    "Invalid status profile 'noisy'" "$(cat "${cli_err}" 2>/dev/null || true)"

rm -rf "${CLI_TMP_DIR}"

# ── Tests: priority-aware status writes ────────────────────────────────────────

echo ""
echo "priority-aware status writes (_priority_write)"

TMP_STATUS="${STATE_DIR}/test-priority-status.txt"
TMP_CONTEXT="${STATE_DIR}/test-priority-context.txt"
rm -f "${TMP_STATUS}" "${TMP_CONTEXT}"

# 1. Pre-tool blocked by Awaiting approval (p88 > p65 Editing)
printf '⏸️ Awaiting approval' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"foo.sh"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: pre-tool Edit blocked by ⏸️ Awaiting approval" "⏸️ Awaiting approval" "${result}"

# 2. Pre-tool blocked by Error (p100 > p55 Reading)
printf '🐛 Error' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Read","tool_input":{"file_path":"foo.sh"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: pre-tool Read blocked by 🐛 Error" "🐛 Error" "${result}"

# 3. Event PermissionRequest wins over Running (p88 > p55)
printf '🖥️ Running' > "${TMP_STATUS}"
result=$(echo '{"permission":"needed"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event PermissionRequest && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: PermissionRequest wins over 🖥️ Running" "⏸️ Awaiting approval" "${result}"

# 4. Equal priority allows write (p88 == p88)
printf '⏸️ Awaiting approval' > "${TMP_STATUS}"
result=$(echo '{"permission":"needed"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event PermissionRequest && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: equal priority allows write (⏸️ → ⏸️)" "⏸️ Awaiting approval" "${result}"

# 5. Completion bypasses priority (Tests passed over Awaiting approval)
printf '⏸️ Awaiting approval' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"npm test"},"tool_response":"5 tests passed"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: ✅ Tests passed bypasses ⏸️ Awaiting approval" "✅ Tests passed" "${result}"

# 6. Error always wins (post-tool-failure over Testing)
printf '🧪 Testing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"error":"boom"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool-failure && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: 🐛 Error always wins over 🧪 Testing" "🐛 Error" "${result}"

# 7. TaskCompleted bypasses priority (over Editing)
printf '✏️ Editing' > "${TMP_STATUS}"
result=$(echo '{"task":"done"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" CCP_STATUS_PROFILE=quiet \
      bash "${LIB_DIR}/hook_runner.sh" event TaskCompleted && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: 🏁 Completed bypasses ✏️ Editing" "🏁 Completed" "${result}"

# 8. Delegating wins over Running (p70 > p55)
printf '🖥️ Running' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Agent","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: 🤖 Delegating wins over 🖥️ Running" "🤖 Delegating" "${result}"

# 9. Running blocked by Delegating (p55 < p70)
printf '🤖 Delegating' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: 🖥️ Running blocked by 🤖 Delegating" "🤖 Delegating" "${result}"

# 10. User-prompt Thinking resets regardless of priority
printf '⏸️ Awaiting approval' > "${TMP_STATUS}"
echo '{"prompt":"Fix the bug"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" user-prompt
result=$(cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: user-prompt 💭 Thinking resets ⏸️ Awaiting approval" "💭 Thinking" "${result}"

# 11. Stop clears regardless of priority
printf '🐛 Error' > "${TMP_STATUS}"
echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" stop
result=$(cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "priority: stop clears 🐛 Error regardless" "${result}"

# 12. Post-tool clear resets regardless of priority
printf '⏸️ Awaiting approval' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"echo hi"},"tool_response":"hi"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "priority: post-tool generic Bash clears ⏸️ Awaiting approval" "${result}"

# 13. Equal priority allows transition (Reading → Browsing, both p55)
printf '📖 Reading' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"WebFetch","tool_input":{"url":"https://example.com"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: 🌐 Browsing replaces 📖 Reading (equal p55)" "🌐 Browsing" "${result}"

# 14. Empty file allows any write
rm -f "${TMP_STATUS}"
printf '' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Read","tool_input":{"file_path":"foo.sh"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: empty file allows 📖 Reading" "📖 Reading" "${result}"

# 15. Working (p55) blocked by Editing (p65)
printf '✏️ Editing' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"SomeRandomTool","tool_input":{}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "priority: 🔧 Working (p55) blocked by ✏️ Editing (p65)" "✏️ Editing" "${result}"

rm -f "${TMP_STATUS}" "${TMP_CONTEXT}"

# ── Tests: dedup ──────────────────────────────────────────────────────────────

echo ""
echo "status write deduplication"

TMP_STATUS="${STATE_DIR}/test-dedup-status.txt"
TMP_CONTEXT="${STATE_DIR}/test-dedup-context.txt"
rm -f "${TMP_STATUS}" "${TMP_CONTEXT}"

# 1. Pre-tool same status skipped (Reading → Read = still Reading, no write)
printf '📖 Reading' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Read","tool_input":{"file_path":"foo.sh"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "dedup: pre-tool same status skipped (📖 Reading → Read)" "📖 Reading" "${result}"

# 2. Pre-tool different status writes (Reading → Edit = Editing)
printf '📖 Reading' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Edit","tool_input":{"file_path":"foo.sh"}}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" pre-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_equals "dedup: pre-tool different status writes (📖 Reading → ✏️ Editing)" "✏️ Editing" "${result}"

# 3. Post-tool empty dedup (already empty → generic Bash → still empty)
printf '' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":"ok"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "dedup: post-tool empty dedup (already empty stays empty)" "${result}"

# 4. Post-tool empty clears stale (⏸️ Awaiting approval → generic Bash → cleared)
printf '⏸️ Awaiting approval' > "${TMP_STATUS}"
result=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":"ok"}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" post-tool && cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "dedup: post-tool empty clears stale ⏸️ Awaiting approval" "${result}"

# 5. Stop dedup (already empty → stop → still empty)
printf '' > "${TMP_STATUS}"
echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" stop
result=$(cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "dedup: stop on already-empty file stays empty" "${result}"

# 6. Stop clears non-empty (🖥️ Running → stop → cleared)
printf '🖥️ Running' > "${TMP_STATUS}"
echo '{}' \
    | CCP_STATUS_FILE="${TMP_STATUS}" CCP_CONTEXT_FILE="${TMP_CONTEXT}" \
      bash "${LIB_DIR}/hook_runner.sh" stop
result=$(cat "${TMP_STATUS}" 2>/dev/null || true)
assert_empty "dedup: stop clears non-empty 🖥️ Running" "${result}"

rm -f "${TMP_STATUS}" "${TMP_CONTEXT}"

# ── Tests: bin/ccp startup messaging ──────────────────────────────────────────

echo ""
echo "bin/ccp startup messaging"

BIN_CCP="${PROJECT_DIR}/bin/ccp"
CLI_TMP_DIR=$(mktemp -d)
CLI_STATE_DIR="${CLI_TMP_DIR}/state"
mkdir -p "${CLI_STATE_DIR}"
CLI_SESSION_FILE="${CLI_STATE_DIR}/sessions.json"
echo '[]' > "${CLI_SESSION_FILE}"

# --goto: matching session emits "Resuming:" line
CLI_GOTO_STATE_DIR="${CLI_TMP_DIR}/goto-state"
mkdir -p "${CLI_GOTO_STATE_DIR}"
CLI_GOTO_SESSION_FILE="${CLI_GOTO_STATE_DIR}/sessions.json"
# Inject a live session (use current PID so it appears alive to find_session)
printf '[{"pid":%d,"title":"Fix Auth Bug","directory":"%s"}]' "$$" "${CLI_TMP_DIR}" \
    > "${CLI_GOTO_SESSION_FILE}"

cli_out3="${CLI_TMP_DIR}/startup-goto.out"
CCP_CLAUDE_CMD=/usr/bin/true CCP_STATUS_PROFILE=quiet \
STATE_DIR="${CLI_GOTO_STATE_DIR}" SESSION_FILE="${CLI_GOTO_SESSION_FILE}" \
"${BIN_CCP}" --goto "Fix Auth" --no-dynamic \
    >"${cli_out3}" 2>&1 || true
assert_contains "bin/ccp: --goto shows Resuming line with matched title" \
    "Resuming:" "$(cat "${cli_out3}" 2>/dev/null || true)"
assert_contains "bin/ccp: --goto Resuming line includes session title" \
    "Fix Auth Bug" "$(cat "${cli_out3}" 2>/dev/null || true)"

rm -rf "${CLI_TMP_DIR}"

# ── Tests: --print mode auto-disables dynamic titles ─────────────────────────

echo ""
echo "bin/ccp --print mode detection"

BIN_CCP="${PROJECT_DIR}/bin/ccp"
CLI_TMP_DIR=$(mktemp -d)
CLI_STATE_DIR="${CLI_TMP_DIR}/state"
mkdir -p "${CLI_STATE_DIR}"
CLI_SESSION_FILE="${CLI_STATE_DIR}/sessions.json"
echo '[]' > "${CLI_SESSION_FILE}"

# --print flag should auto-disable dynamic titles (succeeds without monitor)
cli_exit=0
cli_out="${CLI_TMP_DIR}/print-long.out"
CCP_CLAUDE_CMD=/usr/bin/true CCP_STATUS_PROFILE=quiet \
STATE_DIR="${CLI_STATE_DIR}" SESSION_FILE="${CLI_SESSION_FILE}" \
"${BIN_CCP}" --print "Summarize this" \
    >"${cli_out}" 2>&1 || cli_exit=$?
assert_equals "bin/ccp: --print flag exits 0" "0" "${cli_exit}"
assert_contains "bin/ccp: --print logs skip message" \
    "Skipping dynamic titles: --print mode detected" \
    "$(cat "${cli_out}" 2>/dev/null || true)"

# -p short flag should also auto-disable dynamic titles
cli_exit=0
cli_out="${CLI_TMP_DIR}/print-short.out"
CCP_CLAUDE_CMD=/usr/bin/true CCP_STATUS_PROFILE=quiet \
STATE_DIR="${CLI_STATE_DIR}" SESSION_FILE="${CLI_SESSION_FILE}" \
"${BIN_CCP}" -p "Summarize this" \
    >"${cli_out}" 2>&1 || cli_exit=$?
assert_equals "bin/ccp: -p flag exits 0" "0" "${cli_exit}"
assert_contains "bin/ccp: -p logs skip message" \
    "Skipping dynamic titles: --print mode detected" \
    "$(cat "${cli_out}" 2>/dev/null || true)"

# --print after -- separator should also be detected
cli_exit=0
cli_out="${CLI_TMP_DIR}/print-separator.out"
CCP_CLAUDE_CMD=/usr/bin/true CCP_STATUS_PROFILE=quiet \
STATE_DIR="${CLI_STATE_DIR}" SESSION_FILE="${CLI_SESSION_FILE}" \
"${BIN_CCP}" "My task" -- --print \
    >"${cli_out}" 2>&1 || cli_exit=$?
assert_equals "bin/ccp: --print after -- exits 0" "0" "${cli_exit}"
assert_contains "bin/ccp: --print after -- logs skip message" \
    "Skipping dynamic titles: --print mode detected" \
    "$(cat "${cli_out}" 2>/dev/null || true)"

# --no-dynamic disables titles explicitly; should NOT emit auto-detect skip message
cli_exit=0
cli_out="${CLI_TMP_DIR}/normal.out"
CCP_CLAUDE_CMD=/usr/bin/true CCP_STATUS_PROFILE=quiet \
STATE_DIR="${CLI_STATE_DIR}" SESSION_FILE="${CLI_SESSION_FILE}" \
"${BIN_CCP}" --no-dynamic "Normal task" \
    >"${cli_out}" 2>&1 || cli_exit=$?
assert_equals "bin/ccp: --no-dynamic exits 0" "0" "${cli_exit}"
# Should NOT contain the --print auto-detect skip message
if [[ "$(cat "${cli_out}" 2>/dev/null || true)" == *"Skipping dynamic titles: --print mode detected"* ]]; then
    fail "bin/ccp: --no-dynamic should not trigger --print auto-detection message"
else
    pass "bin/ccp: --no-dynamic does not trigger --print auto-detection message"
fi

# --output-format json should auto-disable dynamic titles
cli_exit=0
cli_out="${CLI_TMP_DIR}/output-json.out"
CCP_CLAUDE_CMD=/usr/bin/true CCP_STATUS_PROFILE=quiet \
STATE_DIR="${CLI_STATE_DIR}" SESSION_FILE="${CLI_SESSION_FILE}" \
"${BIN_CCP}" --output-format json "Summarize this" \
    >"${cli_out}" 2>&1 || cli_exit=$?
assert_equals "bin/ccp: --output-format json exits 0" "0" "${cli_exit}"
assert_contains "bin/ccp: --output-format json logs skip message" \
    "Skipping dynamic titles: --output-format json detected" \
    "$(cat "${cli_out}" 2>/dev/null || true)"

# --output-format stream-json should auto-disable dynamic titles
cli_exit=0
cli_out="${CLI_TMP_DIR}/output-stream-json.out"
CCP_CLAUDE_CMD=/usr/bin/true CCP_STATUS_PROFILE=quiet \
STATE_DIR="${CLI_STATE_DIR}" SESSION_FILE="${CLI_SESSION_FILE}" \
"${BIN_CCP}" --output-format stream-json "Summarize this" \
    >"${cli_out}" 2>&1 || cli_exit=$?
assert_equals "bin/ccp: --output-format stream-json exits 0" "0" "${cli_exit}"
assert_contains "bin/ccp: --output-format stream-json logs skip message" \
    "Skipping dynamic titles: --output-format stream-json detected" \
    "$(cat "${cli_out}" 2>/dev/null || true)"

# --output-format text should NOT trigger the skip
cli_exit=0
cli_out="${CLI_TMP_DIR}/output-text.out"
CCP_CLAUDE_CMD=/usr/bin/true CCP_STATUS_PROFILE=quiet \
STATE_DIR="${CLI_STATE_DIR}" SESSION_FILE="${CLI_SESSION_FILE}" \
"${BIN_CCP}" --output-format text --no-dynamic "Normal task" \
    >"${cli_out}" 2>&1 || cli_exit=$?
assert_equals "bin/ccp: --output-format text exits 0" "0" "${cli_exit}"
if [[ "$(cat "${cli_out}" 2>/dev/null || true)" == *"Skipping dynamic titles: --output-format"* ]]; then
    fail "bin/ccp: --output-format text should not trigger auto-disable"
else
    pass "bin/ccp: --output-format text does not trigger auto-disable"
fi

rm -rf "${CLI_TMP_DIR}"

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
