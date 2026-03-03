#!/usr/bin/env bash
# tests/e2e/run-e2e.sh - End-to-end test for claude-pane-pulse
#
# Runs ccp with a mock claude that emits pre-recorded output, captures all
# title changes via CCP_TITLE_LOG, then asserts the expected sequence was seen.
#
# Usage:
#   bash tests/e2e/run-e2e.sh            # normal (with delays)
#   FAST=1 bash tests/e2e/run-e2e.sh    # fast (no delays, for CI)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; FAILURES=$((FAILURES + 1)); }
FAILURES=0

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  claude-pane-pulse — E2E Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Setup ─────────────────────────────────────────────────────────────────────
TITLE_LOG="$(mktemp /tmp/ccp-e2e-titles.XXXXXX)"
STATE_TMP="$(mktemp -d /tmp/ccp-e2e-state.XXXXXX)"
MOCK_CLAUDE="${SCRIPT_DIR}/mock-claude.sh"
chmod +x "${MOCK_CLAUDE}"

# Compressed delays in fast/CI mode
if [[ "${FAST:-0}" = "1" ]]; then
    export MOCK_CLAUDE_DELAY=0.05
else
    export MOCK_CLAUDE_DELAY=0.4
fi

cleanup() {
    rm -f "${TITLE_LOG}"
    rm -rf "${STATE_TMP}"
}
trap cleanup EXIT

# ── Test 1: Initial title is set ──────────────────────────────────────────────
echo -e "${BLUE}Running: ccp \"PR #89 - Fix auth\" (mock claude)${NC}"
echo ""

export CCP_TITLE_LOG="${TITLE_LOG}"
export CCP_CLAUDE_CMD="${MOCK_CLAUDE}"
export STATE_DIR="${STATE_TMP}"
export SESSION_FILE="${STATE_TMP}/sessions.json"

# Run ccp with --no-dynamic first to test static title setting
"${REPO_DIR}/bin/ccp" --no-dynamic "PR #89 - Fix auth" 2>/dev/null || true

if grep -qF "PR #89 - Fix auth" "${TITLE_LOG}" 2>/dev/null; then
    pass "Static title 'PR #89 - Fix auth' was set"
else
    fail "Static title was NOT set (log: $(cat "${TITLE_LOG}" 2>/dev/null | head -5 || echo 'empty'))"
fi
truncate -s 0 "${TITLE_LOG}"

# ── Test 2: Dynamic title with mock claude ────────────────────────────────────
echo ""
echo -e "${BLUE}Running: dynamic mode with mock claude output${NC}"
echo ""

"${REPO_DIR}/bin/ccp" "PR #89 - Fix auth" 2>/dev/null || true

# Give the monitor a moment to flush remaining titles
sleep 0.5

# Dump the captured title sequence for inspection
echo "  Captured title sequence:"
while IFS= read -r line; do
    echo "    → ${line}"
done < "${TITLE_LOG}"
echo ""

# ── Assertions ────────────────────────────────────────────────────────────────

assert_title_seen() {
    local expected="$1"
    local description="$2"
    if grep -qF "${expected}" "${TITLE_LOG}" 2>/dev/null; then
        pass "${description}"
    else
        fail "${description} (expected to see: '${expected}')"
    fi
}

assert_title_seen "PR #89 - Fix auth"          "Base title set on startup"
assert_title_seen "✅ Tests passed"             "Tests passed status appeared"
assert_title_seen "💾 Committed"               "Committed status appeared (git commit)"

# Verify ordering: Tests passed must appear before Committed
PASSED_LINE=$(grep -n "Tests passed" "${TITLE_LOG}" 2>/dev/null | head -1 | cut -d: -f1 || echo "0")
COMMIT_LINE=$(grep -n "Committed"    "${TITLE_LOG}" 2>/dev/null | head -1 | cut -d: -f1 || echo "0")
if [[ "${PASSED_LINE}" -gt 0 && "${COMMIT_LINE}" -gt 0 && \
      "${PASSED_LINE}" -lt "${COMMIT_LINE}" ]]; then
    pass "Status order: Tests passed → Committed (correct)"
else
    fail "Status order wrong (Tests passed line ${PASSED_LINE}, Committed line ${COMMIT_LINE})"
fi
# Note: hook-based statuses (🧪 Testing, ⬆️ Pushing) are verified in test-statuses.sh
# and test-chain.sh. They rely on the 1-second heartbeat firing within a window that
# is too narrow in FAST mode (MOCK_CLAUDE_DELAY=0.05s < heartbeat period).

# ── Test 3: Quick-format helpers ──────────────────────────────────────────────
echo ""
echo -e "${BLUE}Running: quick-format title helpers${NC}"
echo ""
truncate -s 0 "${TITLE_LOG}"

"${REPO_DIR}/bin/ccp" --no-dynamic --pr 42 "Add OAuth" 2>/dev/null || true
assert_title_seen "PR #42 - Add OAuth" "--pr format produces correct title"
truncate -s 0 "${TITLE_LOG}"

"${REPO_DIR}/bin/ccp" --no-dynamic --feature "dark mode" 2>/dev/null || true
assert_title_seen "Feature: dark mode" "--feature format produces correct title"
truncate -s 0 "${TITLE_LOG}"

"${REPO_DIR}/bin/ccp" --no-dynamic --bug "login crash" 2>/dev/null || true
assert_title_seen "Bug: login crash" "--bug format produces correct title"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ ${FAILURES} -eq 0 ]]; then
    echo -e "${GREEN}✓ All e2e tests passed${NC}"
else
    echo -e "${RED}✗ ${FAILURES} e2e test(s) failed${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit "${FAILURES}"
