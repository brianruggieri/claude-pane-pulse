#!/usr/bin/env bash
# tests/e2e/mock-claude.sh - Simulates Claude Code TUI output for e2e testing
#
# Emits realistic-looking Claude Code output with delays so the ccp monitor
# can detect each status transition.  Also fires hook_runner.sh (via
# CCP_HOOK_RUNNER, exported by bin/ccp) to simulate PreToolUse hooks for the
# tool calls that write named statuses (🧪 Testing, ⬆️ Pushing, etc.).
#
# Usage: CCP_CLAUDE_CMD=tests/e2e/mock-claude.sh ccp "PR #1 - Test"

DELAY="${MOCK_CLAUDE_DELAY:-0.4}"   # seconds between events; override to 0 for unit tests

sleep_step() { sleep "${DELAY}"; }

# fire_hook: simulate a PreToolUse hook call for a given tool + command.
# Uses CCP_HOOK_RUNNER exported by bin/ccp; silently skips if not set.
fire_hook() {
    local tool="$1" cmd="${2:-}"
    [[ -z "${CCP_HOOK_RUNNER:-}" ]] && return 0
    printf '%s' "{\"tool_name\":\"${tool}\",\"tool_input\":{\"command\":\"${cmd}\"}}" \
        | bash "${CCP_HOOK_RUNNER}" pre-tool 2>/dev/null || true
}

# ── Startup banner ────────────────────────────────────────────────────────────
printf '\r\n'
printf '▗ ▗   ▖ ▖  Claude Code v2.1.63 (mock)\r\n'
printf '           Sonnet 4.6 · Claude Max\r\n'
printf '\r\n'
printf '❯ Try "fix typecheck errors"\r\n'
printf '\r\n'

sleep_step

# ── Phase 1: Read some files (no status change expected) ──────────────────────
printf 'Let me look at the code first.\r\n'
printf 'Reading src/math.js...\r\n'
sleep_step

# ── Phase 2: Run tests → Testing ──────────────────────────────────────────────
fire_hook "Bash" "npm test"
printf 'Running the test suite to see what is failing.\r\n'
printf 'npm test\r\n'
sleep_step
printf '> test-project@1.0.0 test\r\n'
printf '> jest --no-coverage\r\n'
sleep_step
printf 'FAIL tests/math.test.js\r\n'
printf '  ● add › returns correct sum\r\n'
printf '    Expected: 5\r\n'
printf '    Received: 4\r\n'
printf '1 test failed, 2 tests passed\r\n'
sleep_step

# ── Phase 3: Building / compiling ─────────────────────────────────────────────
printf 'I can see the bug. Fixing it now.\r\n'
printf 'Building the fix...\r\n'
sleep_step

# ── Phase 4: Run tests again → Tests passed ───────────────────────────────────
fire_hook "Bash" "npm test"
printf 'npm test\r\n'
sleep_step
printf '> jest --no-coverage\r\n'
sleep_step
printf 'PASS tests/math.test.js\r\n'
printf 'PASS tests/auth.test.js\r\n'
printf '3 tests passed in 0.9s\r\n'
sleep_step

# ── Phase 5: Git commit ────────────────────────────────────────────────────────
printf 'Tests pass. Committing the fix.\r\n'
printf 'git commit -m "fix: correct off-by-one in add()"\r\n'
sleep_step
printf '[main abc1234] fix: correct off-by-one in add()\r\n'
sleep_step

# ── Phase 6: Git push → Pushing ───────────────────────────────────────────────
fire_hook "Bash" "git push origin main"
printf 'git push origin main\r\n'
sleep_step
printf 'Enumerating objects: 5, done.\r\n'
printf 'To github.com:user/test-project.git\r\n'
printf '   def5678..abc1234  main -> main\r\n'
sleep_step

# ── Done ──────────────────────────────────────────────────────────────────────
printf '\r\n'
printf 'All done! Fixed the bug, tests pass, pushed.\r\n'
printf '\r\n'
printf 'Resume this session with:\r\n'
printf 'claude --resume mock-session-0000\r\n'
