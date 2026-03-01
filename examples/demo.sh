#!/usr/bin/env bash
# examples/demo.sh - Interactive demo of Claude Pane Pulse status updates
#
# This script simulates Claude Code output to show how ccp updates
# terminal titles in real time. No actual Claude Code session required.
#
# Usage: bash examples/demo.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Use a temp STATE_DIR so demo doesn't pollute real sessions
STATE_DIR=$(mktemp -d)
SESSION_FILE="${STATE_DIR}/sessions.json"
echo '[]' > "${SESSION_FILE}"
export STATE_DIR SESSION_FILE

source "${LIB_DIR}/core.sh"
source "${LIB_DIR}/title.sh"
source "${LIB_DIR}/monitor.sh"

BASE_TITLE="Demo: PR #42 - Add OAuth"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude Pane Pulse — Demo"
echo "  Base title: ${BASE_TITLE}"
echo "  Watch your terminal tab/title bar!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

set_title "${BASE_TITLE}"
sleep 1

simulate_status() {
    local label="$1"
    local line="$2"
    local duration="${3:-2}"

    echo -e "  Simulating: ${label}"
    result=$(extract_context "${line}")
    context="${result%|*}"

    if [[ -n "${context}" ]]; then
        for frame in 0 1 2 3 0 1; do
            animated=$(animate_status "${context}" "${frame}")
            update_title_with_context "${BASE_TITLE}" "${animated}"
            echo -ne "\r    Title: ${BASE_TITLE} | ${animated}        "
            sleep 0.4
        done
        echo ""
    else
        echo "    (no status detected)"
    fi
    sleep "${duration}"
}

echo "Cycling through all status types..."
echo ""

simulate_status "💭 Thinking"     "Let me think about this OAuth flow..."  1
simulate_status "📦 Installing"   "npm install passport passport-google"   1
simulate_status "🔨 Building"     "Building the project..."                1
simulate_status "🧪 Testing"      "jest --testPathPattern auth"            1
simulate_status "✅ Tests passed" "12 tests passed"                        1
simulate_status "💾 Committed"    "git commit -m 'feat: add OAuth'"        1
simulate_status "⬆️ Pushing"      "git push origin feature/oauth"          1
simulate_status "❌ Tests failed" "3 tests failed"                         1
simulate_status "🐛 Error"        "Error: token validation failed"         1

echo ""
echo "  Setting: 💤 Idle"
update_title_with_context "${BASE_TITLE}" "💤 Idle"
sleep 1

echo ""
echo "  Restoring base title..."
set_title "${BASE_TITLE}"

rm -rf "${STATE_DIR}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Demo complete! Run 'ccp --help' to get started."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
