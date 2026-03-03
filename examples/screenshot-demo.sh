#!/usr/bin/env bash
# examples/screenshot-demo.sh
#
# Creates a large 4-pane iTerm2 window running 4 simultaneous ccp sessions
# with different projects/branches/tasks/statuses, then takes a full screenshot.
#
# Output: docs/demo.png (suitable for README / GIF source frames)
#
# Usage:
#   bash examples/screenshot-demo.sh [--out PATH]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB_DIR="${REPO_DIR}/lib"
BIN_CCP="${REPO_DIR}/bin/ccp"
HOOK_RUNNER="${LIB_DIR}/hook_runner.sh"

OUT_FILE="${REPO_DIR}/docs/demo.png"
NEXT_IS_OUT=false
for arg in "$@"; do
    $NEXT_IS_OUT && OUT_FILE="${arg}" && NEXT_IS_OUT=false && continue
    [[ "${arg}" == "--out" ]] && NEXT_IS_OUT=true
done

PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
export PATH

mkdir -p "$(dirname "${OUT_FILE}")"

TMP_BASE="$(mktemp -d /tmp/ccp_demo_XXXXXX)"
DEMO_WIN_ID=""

cleanup() {
    [[ -n "${DEMO_WIN_ID}" ]] && osascript << OSASCRIPT 2>/dev/null || true
tell application "iTerm2"
    try
        set theWin to first window whose id is ${DEMO_WIN_ID}
        close theWin
    end try
end tell
OSASCRIPT
    rm -rf "${TMP_BASE}" 2>/dev/null || true
}
trap cleanup EXIT

# ── Make fake git repos ────────────────────────────────────────────────────────

make_repo() {
    local name="$1" branch="$2"
    local dir="${TMP_BASE}/${name}"
    mkdir -p "${dir}"
    git -C "${dir}" init -q
    git -C "${dir}" checkout -q -b "${branch}" 2>/dev/null || true
    touch "${dir}/README.md"
    git -C "${dir}" add README.md
    git -C "${dir}" -c user.email="demo@ccp.sh" -c user.name="Demo" commit -q -m "init"
    echo "${dir}"
}

REPO_FRONTEND=$(make_repo "frontend-app"   "feat/dark-mode")
REPO_API=$(make_repo      "api-service"    "fix/rate-limiting")
REPO_INFRA=$(make_repo    "data-pipeline"  "feat/streaming-etl")
REPO_MOBILE=$(make_repo   "mobile-app"     "chore/deps-upgrade")

# ── Fake claude drivers ────────────────────────────────────────────────────────
# Each holds for 45s — plenty of time for screenshot + text visible in pane

make_driver() {
    local task="$1" tool_json="$2" pty_output="$3"
    local f="${TMP_BASE}/driver_${RANDOM}.sh"
    cat > "${f}" << DRIVER
#!/usr/bin/env bash
PATH="/opt/homebrew/bin:/usr/local/bin:\${PATH:-/usr/bin:/bin}"
HR="\${CCP_HOOK_RUNNER:-${HOOK_RUNNER}}"
printf '%s' '{"prompt":"${task}"}' | bash "\${HR}" user-prompt 2>/dev/null || true
sleep 0.4
printf '%s' '${tool_json}' | bash "\${HR}" pre-tool 2>/dev/null || true
echo ""
echo "${pty_output}"
sleep 45
printf '%s' '{}' | bash "\${HR}" stop 2>/dev/null || true
DRIVER
    chmod +x "${f}"
    echo "${f}"
}

DRIVER_1=$(make_driver \
    "Implement dark mode CSS variables for all components" \
    '{"tool_name":"Edit","tool_input":{"file_path":"src/styles/variables.css"}}' \
    "  → Updating 47 CSS custom properties...")

DRIVER_2=$(make_driver \
    "Fix rate limiting bypass in the authentication middleware" \
    '{"tool_name":"Bash","tool_input":{"command":"npm test -- --testPathPattern=auth"}}' \
    "  → Running 23 auth tests...")

DRIVER_3=$(make_driver \
    "Add backpressure handling to the Kafka streaming consumer" \
    '{"tool_name":"Bash","tool_input":{"command":"python3 -m pytest tests/test_consumer.py -v"}}' \
    "  → pytest: collecting 12 items...")

DRIVER_4=$(make_driver \
    "Upgrade React Native from 0.73 to 0.74 across all packages" \
    '{"tool_name":"Bash","tool_input":{"command":"npm install react-native@0.74"}}' \
    "  → npm: resolving 1,247 packages...")

# ── Create 2×2 window ──────────────────────────────────────────────────────────

echo "Creating 4-pane demo window..."

DEMO_WIN_ID=$(osascript << 'OSASCRIPT' 2>/dev/null
tell application "iTerm2"
    set newWin to (create window with default profile)
    -- Large window: nearly full screen, leave room for menu bar + taskbar
    set bounds of newWin to {60, 60, 1540, 1020}
    tell current tab of newWin
        set s1 to current session
        -- horizontal split → s1 top, s3 bottom
        set s3 to split horizontally with default profile of s1
        -- vertical split top → s1 left, s2 right
        set s2 to split vertically with default profile of s1
        -- vertical split bottom → s3 left, s4 right
        set s4 to split vertically with default profile of s3
    end tell
    return id of newWin
end tell
OSASCRIPT
)

echo "Window ID: ${DEMO_WIN_ID}"
sleep 0.5

# Helper: send text to nth session in demo window
send_to() {
    local n="$1" text="$2"
    local escaped="${text//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    osascript << OSASCRIPT 2>/dev/null
tell application "iTerm2"
    set theWin to first window whose id is ${DEMO_WIN_ID}
    set theSessions to sessions of current tab of theWin
    if (count of theSessions) >= ${n} then
        tell item ${n} of theSessions
            write text "${escaped}"
        end tell
    end if
end tell
OSASCRIPT
}

# Helper: get name of nth session
get_title() {
    local n="$1"
    osascript << OSASCRIPT 2>/dev/null
tell application "iTerm2"
    set theWin to first window whose id is ${DEMO_WIN_ID}
    set theSessions to sessions of current tab of theWin
    if (count of theSessions) >= ${n} then
        return name of item ${n} of theSessions
    end if
end tell
OSASCRIPT
}

# ── Launch 4 ccp sessions ─────────────────────────────────────────────────────

echo "Launching ccp sessions..."

# Give all 4 shells a moment to finish initializing before we type commands
sleep 1.5

# Pane 1 (top-left):    frontend-app · feat/dark-mode · ✏️ Editing
send_to 1 "clear && cd '${REPO_FRONTEND}' && CCP_CLAUDE_CMD='${DRIVER_1}' bash '${BIN_CCP}' -- dummy 2>/dev/null"
sleep 0.6

# Pane 2 (top-right):   api-service · fix/rate-limiting · 🧪 Testing
send_to 2 "clear && cd '${REPO_API}' && CCP_CLAUDE_CMD='${DRIVER_2}' bash '${BIN_CCP}' -- dummy 2>/dev/null"
sleep 0.6

# Pane 3 (bottom-left): data-pipeline · feat/streaming-etl · 🧪 Testing
send_to 3 "clear && cd '${REPO_INFRA}' && CCP_CLAUDE_CMD='${DRIVER_3}' bash '${BIN_CCP}' -- dummy 2>/dev/null"
sleep 0.6

# Pane 4 (bottom-right): mobile-app · chore/deps-upgrade · 📦 Installing
send_to 4 "clear && cd '${REPO_MOBILE}' && CCP_CLAUDE_CMD='${DRIVER_4}' bash '${BIN_CCP}' -- dummy 2>/dev/null"

# ── Wait for all 4 panes to show their projects ────────────────────────────────

echo "Waiting for all 4 panes to show project names..."
FOUND=0
WAIT_START=$SECONDS
while [[ $((SECONDS - WAIT_START)) -lt 25 && $FOUND -lt 4 ]]; do
    FOUND=0
    [[ "$(get_title 1 2>/dev/null || echo '')" == *"frontend-app"* ]] && FOUND=$((FOUND+1)) || true
    [[ "$(get_title 2 2>/dev/null || echo '')" == *"api-service"* ]]   && FOUND=$((FOUND+1)) || true
    [[ "$(get_title 3 2>/dev/null || echo '')" == *"data-pipeline"* ]] && FOUND=$((FOUND+1)) || true
    [[ "$(get_title 4 2>/dev/null || echo '')" == *"mobile-app"* ]]    && FOUND=$((FOUND+1)) || true
    echo "  ${FOUND}/4 panes ready ($(( SECONDS - WAIT_START ))s elapsed)..."
    [[ $FOUND -lt 4 ]] && sleep 1 || true
done

echo "  All ${FOUND}/4 panes showing project names"

# Wait for statuses to appear (hooks fire ~1s after UserPromptSubmit)
echo "Waiting for statuses to appear..."
STATUS_FOUND=0
WAIT_START=$SECONDS
while [[ $((SECONDS - WAIT_START)) -lt 12 && $STATUS_FOUND -lt 3 ]]; do
    STATUS_FOUND=0
    _t1=$(get_title 1 2>/dev/null || echo "")
    _t2=$(get_title 2 2>/dev/null || echo "")
    _t4=$(get_title 4 2>/dev/null || echo "")
    [[ "${_t1}" == *"Editing"* || "${_t1}" == *"Reading"*  ]] && STATUS_FOUND=$((STATUS_FOUND+1)) || true
    [[ "${_t2}" == *"Testing"* ]]                              && STATUS_FOUND=$((STATUS_FOUND+1)) || true
    [[ "${_t4}" == *"Installing"* || "${_t4}" == *"Running"* ]] && STATUS_FOUND=$((STATUS_FOUND+1)) || true
    [[ $STATUS_FOUND -lt 3 ]] && sleep 0.5 || true
done

# Let the spinners animate a bit
sleep 2

# ── Bring window to front and screenshot ──────────────────────────────────────

echo "Bringing window to front..."
osascript << OSASCRIPT 2>/dev/null || true
tell application "iTerm2"
    activate
    set theWin to first window whose id is ${DEMO_WIN_ID}
    set index of theWin to 1
end tell
OSASCRIPT

sleep 0.8  # compositor settle

# Get window bounds (left, top, right, bottom) → convert to x,y,w,h
BOUNDS=$(osascript << OSASCRIPT 2>/dev/null
tell application "iTerm2"
    set theWin to first window whose id is ${DEMO_WIN_ID}
    set b to bounds of theWin
    set x1 to (item 1 of b) as string
    set y1 to (item 2 of b) as string
    set w  to ((item 3 of b) - (item 1 of b)) as string
    set h  to ((item 4 of b) - (item 2 of b)) as string
    return x1 & "," & y1 & "," & w & "," & h
end tell
OSASCRIPT
)
# Strip any stray spaces
BOUNDS="${BOUNDS// /}"

echo "Capturing screenshot (bounds: ${BOUNDS})..."
screencapture -x -R "${BOUNDS}" "${OUT_FILE}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Print live titles
T1=$(get_title 1 2>/dev/null || echo "?")
T2=$(get_title 2 2>/dev/null || echo "?")
T3=$(get_title 3 2>/dev/null || echo "?")
T4=$(get_title 4 2>/dev/null || echo "?")
echo "Live pane titles at screenshot:"
echo "  [top-left]     ${T1}"
echo "  [top-right]    ${T2}"
echo "  [bottom-left]  ${T3}"
echo "  [bottom-right] ${T4}"
echo ""
echo "Screenshot saved: ${OUT_FILE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Hold sessions alive for 30s so you can see the window before it closes
echo "(Window stays open 30s — press Ctrl+C to close early)"
sleep 30
