#!/usr/bin/env bash
# tests/test-chain.sh - Integration tests for the full ccp→pty→subprocess chain
#
# Tests what isolated unit tests cannot: that CCP_STATUS_FILE and CCP_CONTEXT_FILE
# survive the full execution chain  ccp → pty_wrapper.py → subprocess → hook_runner.sh
#
# Also verifies hook_runner.sh behavior with real jq in a controlled environment.
#
# Usage: bash tests/test-chain.sh [--verbose]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="${PROJECT_DIR}/lib"

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

# ── Test helpers ─────────────────────────────────────────────────────────────
PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; [[ "${2:-}" ]] && echo "  expected: $2" && echo "  got:      $3"; }

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "${expected}" == "${actual}" ]]; then pass "${label}"; else fail "${label}" "${expected}" "${actual}"; fi
}
assert_contains() {
    local label="$1" needle="$2" haystack="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then pass "${label}"; else fail "${label}" "*${needle}*" "${haystack}"; fi
}
assert_nonempty() {
    local label="$1" val="$2"
    if [[ -n "${val}" ]]; then pass "${label}"; else fail "${label}" "(non-empty)" "(empty)"; fi
}

# ── Setup temp workspace ─────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d /tmp/ccp_chain_test_XXXXXX)"
STATUS_FILE="${TMP_DIR}/status.txt"
CONTEXT_FILE="${TMP_DIR}/context.txt"
DEBUG_LOG="${TMP_DIR}/hook_debug.log"
FAKE_CLAUDE="${TMP_DIR}/fake_claude.sh"
PIPE="${TMP_DIR}/test.pipe"

cleanup() {
    rm -f "${FAKE_CLAUDE}" "${PIPE}"
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

export CCP_STATUS_FILE="${STATUS_FILE}"
export CCP_CONTEXT_FILE="${CONTEXT_FILE}"
export CCP_HOOK_RUNNER="${LIB_DIR}/hook_runner.sh"
export CCP_DEBUG_LOG="${DEBUG_LOG}"

# Add homebrew to PATH for jq
PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
export PATH

echo ""
echo "══════════════════════════════════════════════════════════════"
echo " CCP Chain Integration Tests"
echo "══════════════════════════════════════════════════════════════"
echo ""

# ── Section 1: hook_runner.sh unit (with real jq via PATH) ───────────────────
echo "── Section 1: hook_runner.sh (real jq, real env) ──"

# Test: pre-tool Edit
rm -f "${STATUS_FILE}"
echo '{"tool_name":"Edit","tool_input":{"file_path":"foo.sh"}}' \
    | bash "${LIB_DIR}/hook_runner.sh" pre-tool
assert_eq "pre-tool Edit → ✏️ Editing" "✏️ Editing" "$(cat "${STATUS_FILE}" 2>/dev/null || echo '')"

# Test: pre-tool Bash npm test
rm -f "${STATUS_FILE}"
echo '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' \
    | bash "${LIB_DIR}/hook_runner.sh" pre-tool
assert_eq "pre-tool Bash npm test → 🧪 Testing" "🧪 Testing" "$(cat "${STATUS_FILE}" 2>/dev/null || echo '')"

# Test: pre-tool Read
rm -f "${STATUS_FILE}"
echo '{"tool_name":"Read","tool_input":{"file_path":"README.md"}}' \
    | bash "${LIB_DIR}/hook_runner.sh" pre-tool
assert_eq "pre-tool Read → 📖 Reading" "📖 Reading" "$(cat "${STATUS_FILE}" 2>/dev/null || echo '')"

# Test: pre-tool git push
rm -f "${STATUS_FILE}"
echo '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' \
    | bash "${LIB_DIR}/hook_runner.sh" pre-tool
assert_eq "pre-tool git push → ⬆️ Pushing" "⬆️ Pushing" "$(cat "${STATUS_FILE}" 2>/dev/null || echo '')"

# Test: user-prompt writes context
rm -f "${CONTEXT_FILE}"
echo '{"prompt":"Fix the login authentication bug"}' \
    | bash "${LIB_DIR}/hook_runner.sh" user-prompt
assert_contains "user-prompt writes context" "Fix the login" "$(cat "${CONTEXT_FILE}" 2>/dev/null || echo '')"

# Test: user-prompt placeholder uses at most 5 words (no 60-char hard truncation)
rm -f "${CONTEXT_FILE}"
long_prompt="one two three four five six seven eight nine ten eleven twelve"
echo "{\"prompt\":\"${long_prompt}\"}" \
    | bash "${LIB_DIR}/hook_runner.sh" user-prompt
prompt_val="$(cat "${CONTEXT_FILE}" 2>/dev/null || echo '')"
word_count="$(printf '%s' "${prompt_val}" | wc -w | tr -d ' ')"
[[ "${word_count}" -le 5 ]] && pass "user-prompt placeholder is at most 5 words" \
                              || fail "user-prompt placeholder is at most 5 words" "≤5 words" "${word_count} words"

# Test: stop clears status
echo "🧪 Testing" > "${STATUS_FILE}"
echo '{}' | bash "${LIB_DIR}/hook_runner.sh" stop
assert_eq "stop clears status file" "" "$(cat "${STATUS_FILE}" 2>/dev/null || echo 'MISSING')"

# Test: exit code is always 0
exit_code=0
echo 'not json at all }{' | bash "${LIB_DIR}/hook_runner.sh" pre-tool || exit_code=$?
assert_eq "hook_runner exits 0 on bad JSON" "0" "${exit_code}"

exit_code=0
echo '{}' | bash "${LIB_DIR}/hook_runner.sh" pre-tool || exit_code=$?
assert_eq "hook_runner exits 0 on empty tool_name" "0" "${exit_code}"

# Test: debug log was written
assert_nonempty "debug log written" "$(cat "${DEBUG_LOG}" 2>/dev/null || echo '')"
[[ "${VERBOSE}" == "true" ]] && echo "--- debug log ---" && cat "${DEBUG_LOG}" && echo "---"

echo ""
echo "── Section 2: env vars flow through pty_wrapper.py ──"

# Build a fake "claude" that invokes hook_runner.sh directly (simulating what
# the real claude would do when its hooks fire) and then exits.
cat > "${FAKE_CLAUDE}" << 'FAKE_EOF'
#!/usr/bin/env bash
# Fake claude: fires hook_runner.sh the same way Claude Code would, then exits.
PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin}"

# Simulate UserPromptSubmit
echo '{"prompt":"Chain test prompt from fake claude"}' \
    | bash "${CCP_HOOK_RUNNER}" user-prompt

# Simulate PreToolUse (Read)
echo '{"tool_name":"Read","tool_input":{"file_path":"README.md"}}' \
    | bash "${CCP_HOOK_RUNNER}" pre-tool

# Save status before Stop clears it (so the test can assert on it)
cp "${CCP_STATUS_FILE}" "${CCP_STATUS_FILE}.pre_stop" 2>/dev/null || true

# Simulate Stop
echo '{}' | bash "${CCP_HOOK_RUNNER}" stop

echo "fake-claude-done"
FAKE_EOF
chmod +x "${FAKE_CLAUDE}"

# Reset files
rm -f "${STATUS_FILE}" "${CONTEXT_FILE}"

# Create named pipe
mkfifo "${PIPE}"

# Drain the pipe in background (pty_wrapper.py tees output there)
drain_log="${TMP_DIR}/drain.log"
cat "${PIPE}" > "${drain_log}" &
drain_pid=$!

# Run the full chain: pty_wrapper.py → fake_claude → hook_runner.sh
python3 "${LIB_DIR}/pty_wrapper.py" "${PIPE}" bash "${FAKE_CLAUDE}" 2>/dev/null || true

# Give drain a moment to flush
kill "${drain_pid}" 2>/dev/null || true
wait "${drain_pid}" 2>/dev/null || true

# Check that hook_runner.sh was reached and wrote files
context_val="$(cat "${CONTEXT_FILE}" 2>/dev/null || echo '')"
status_val="$(cat "${STATUS_FILE}" 2>/dev/null || echo 'MISSING')"

pre_stop_status="$(cat "${STATUS_FILE}.pre_stop" 2>/dev/null || echo '')"
assert_contains "chain: context written via pty_wrapper" "Chain test prompt" "${context_val}"
assert_eq       "chain: PreToolUse status written via pty_wrapper" "📖 Reading" "${pre_stop_status}"
assert_eq       "chain: Stop cleared status via pty_wrapper" "" "${status_val}"

# Verify fake claude output reached the drain (confirming pty is wired)
assert_contains "chain: pty output reaches FIFO" "fake-claude-done" "$(cat "${drain_log}" 2>/dev/null || echo '')"

echo ""
echo "── Section 3: setup_ccp_hooks deduplication ──"

HOOKS_TEST_DIR="${TMP_DIR}/hooks_project"
mkdir -p "${HOOKS_TEST_DIR}"

# Source hooks.sh (needs jq on PATH, which we already set)
source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/hooks.sh"

settings_file=$(setup_ccp_hooks "${HOOKS_TEST_DIR}" "${CCP_HOOK_RUNNER}")

# Verify file created and has exactly 1 of each hook type
pre_count=$(jq '.hooks.PreToolUse | length' "${settings_file}" 2>/dev/null || echo 0)
prompt_count=$(jq '.hooks.UserPromptSubmit | length' "${settings_file}" 2>/dev/null || echo 0)
stop_count=$(jq '.hooks.Stop | length' "${settings_file}" 2>/dev/null || echo 0)

assert_eq "setup: PreToolUse has exactly 1 entry" "1" "${pre_count}"
assert_eq "setup: UserPromptSubmit has exactly 1 entry" "1" "${prompt_count}"
assert_eq "setup: Stop has exactly 1 entry" "1" "${stop_count}"

# Run setup again (simulates restart without teardown) — should still have 1 of each
settings_file2=$(setup_ccp_hooks "${HOOKS_TEST_DIR}" "${CCP_HOOK_RUNNER}")
pre_count2=$(jq '.hooks.PreToolUse | length' "${settings_file2}" 2>/dev/null || echo 0)
assert_eq "setup: dedup prevents accumulation on re-run" "1" "${pre_count2}"

# Teardown removes our hooks
teardown_ccp_hooks "${settings_file}"
assert_eq "teardown: settings file removed when empty" "0" "$([[ ! -f "${settings_file}" ]]; echo $?)"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo " Results: ${PASS} passed, ${FAIL} failed"
echo "══════════════════════════════════════════════════════════════"
echo ""

[[ "${FAIL}" -eq 0 ]] && exit 0 || exit 1
