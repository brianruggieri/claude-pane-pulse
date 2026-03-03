#!/usr/bin/env bash
# tests/iterm2/test-iterm2-live.sh
#
# Live iTerm2 integration tests for ccp using AppleScript (no Python API needed).
#
# THE CORE USE CASE: multiple Claude Code sessions in split panes, each showing
# project · branch · task summary · status — readable at a glance.
#
# Tests:
#   T1  OSC 1 plumbing — pane title actually changes in iTerm2
#   T2  --no-dynamic static title (no status keywords appear)
#   T4  Full hook chain — status + task summary in live title
#   T7  Animated spinner PREPENDED to title
#   T10 ULTIMATE: 3 concurrent split panes, different project/branch/task/status,
#       no cross-contamination, human-readable at a glance
#
# Requirements:
#   - iTerm2 running (no Python API required — uses AppleScript only)
#   - jq, python3 available (Homebrew path added automatically)
#
# Usage:
#   bash tests/iterm2/test-iterm2-live.sh [--verbose] [--only T10]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIB_DIR="${REPO_DIR}/lib"
BIN_CCP="${REPO_DIR}/bin/ccp"
HOOK_RUNNER="${LIB_DIR}/hook_runner.sh"

VERBOSE=false
ONLY=""
NEXT_IS_ONLY=false
for arg in "$@"; do
    $NEXT_IS_ONLY && ONLY="${arg}" && NEXT_IS_ONLY=false && continue
    [[ "${arg}" == "--verbose" || "${arg}" == "-v" ]] && VERBOSE=true
    [[ "${arg}" == "--only" ]] && NEXT_IS_ONLY=true
done

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

# ── Test helpers ──────────────────────────────────────────────────────────────
PASS=0; FAIL=0

pass() { PASS=$((PASS+1)); echo -e "  ${GREEN}✓${NC} $1"; }
fail() { FAIL=$((FAIL+1)); echo -e "  ${RED}✗${NC} $1"; [[ -n "${2:-}" ]] && echo "    expected: $2" && echo "    got:      ${3:-}"; }

assert_eq()           { [[ "$2" == "$3" ]] && pass "$1" || fail "$1" "$2" "$3"; }
assert_contains()     { [[ "$3" == *"$2"* ]] && pass "$1" || fail "$1" "*$2*" "$3"; }
assert_not_contains() { [[ "$3" != *"$2"* ]] && pass "$1" || fail "$1" "NOT *$2*" "$3"; }

# ── AppleScript helpers (all target windows by ID, never by position) ─────────

# Create a new iTerm2 window with N vertical splits; echos the window ID
iterm_create_window() {
    local splits="${1:-1}"
    osascript << OSASCRIPT 2>/dev/null
tell application "iTerm2"
    set newWin to (create window with default profile)
    tell current tab of newWin
        set s to current session
        repeat ${splits} - 1 times
            set s to split vertically with default profile of s
        end repeat
    end tell
    return id of newWin
end tell
OSASCRIPT
}

# Get name of the nth session in the window with WIN_ID (1-indexed)
iterm_session_name() {
    local win_id="$1" n="${2:-1}"
    osascript << OSASCRIPT 2>/dev/null
tell application "iTerm2"
    set theWin to first window whose id is ${win_id}
    set theSessions to sessions of current tab of theWin
    if (count of theSessions) >= ${n} then
        return name of item ${n} of theSessions
    else
        return "NOT_FOUND"
    end if
end tell
OSASCRIPT
}

# Send text to nth session in the window with WIN_ID (1-indexed)
iterm_send() {
    local win_id="$1" n="$2"
    local text="$3"
    # Escape any backslashes and double-quotes so the AppleScript string is valid
    local escaped_text
    escaped_text="${text//\\/\\\\}"
    escaped_text="${escaped_text//\"/\\\"}"
    osascript << OSASCRIPT 2>/dev/null
tell application "iTerm2"
    set theWin to first window whose id is ${win_id}
    set theSessions to sessions of current tab of theWin
    if (count of theSessions) >= ${n} then
        tell item ${n} of theSessions
            write text "${escaped_text}"
        end tell
    end if
end tell
OSASCRIPT
}

# Close the window with WIN_ID
iterm_close_window() {
    local win_id="$1"
    osascript << OSASCRIPT 2>/dev/null || true
tell application "iTerm2"
    set theWin to first window whose id is ${win_id}
    close theWin
end tell
OSASCRIPT
}

# Wait for nth session in WIN_ID to show needle (polls 0.5s, timeout seconds)
wait_for_title() {
    local win_id="$1" n="$2" needle="$3" timeout_s="${4:-12}"
    local i=0 max=$(( timeout_s * 2 ))
    while [[ $i -lt $max ]]; do
        local title
        title=$(iterm_session_name "${win_id}" "${n}" 2>/dev/null || echo "")
        [[ "${title}" == *"${needle}"* ]] && echo "${title}" && return 0
        sleep 0.5
        i=$((i + 1))
    done
    echo "TIMEOUT"
    return 1
}

# Check if any line in a string contains a spinner char
has_spinner() {
    local text="$1"
    while IFS= read -r line; do
        case "${line}" in
            *"·"*|*"✢"*|*"✳"*|*"✶"*|*"✻"*|*"✽"*) return 0 ;;
        esac
    done <<< "${text}"
    return 1
}

# Check if any CCP_TITLE_LOG context line starts with a spinner char (prepended format)
spinner_is_prepended() {
    local text="$1"
    # Title log format: "base | context" — context is after " | "
    # Check if the context portion (after " | ") starts with a spinner
    while IFS= read -r line; do
        local context="${line#* | }"
        [[ "${context}" == "${line}" ]] && continue  # no " | " separator
        case "${context}" in
            "· "*|"✢ "*|"✳ "*|"✶ "*|"✻ "*|"✽ "*) return 0 ;;
        esac
    done <<< "${text}"
    return 1
}

# ── Pre-flight ─────────────────────────────────────────────────────────────────

# Check iTerm2 is accessible via AppleScript
if ! osascript -e 'tell application "iTerm2" to return "ok"' &>/dev/null; then
    echo -e "${RED}ERROR: Cannot connect to iTerm2 via AppleScript.${NC}"
    echo "Ensure iTerm2 is running."
    exit 1
fi

PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"
export PATH
for dep in jq python3; do
    command -v "$dep" &>/dev/null || { echo "ERROR: ${dep} not found"; exit 1; }
done

TMP_BASE="$(mktemp -d /tmp/ccp_iterm2_XXXXXX)"

# Track windows opened by this test so cleanup is surgical
OPENED_WINDOWS=()

cleanup() {
    for wid in "${OPENED_WINDOWS[@]:-}"; do
        [[ -z "${wid}" ]] && continue
        iterm_close_window "${wid}" 2>/dev/null || true
    done
    rm -rf "${TMP_BASE:-}" 2>/dev/null || true
}
trap cleanup EXIT

echo ""
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} ccp Live iTerm2 Integration Tests${NC}"
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Fake project dirs ─────────────────────────────────────────────────────────

make_fake_repo() {
    local name="$1" branch="$2"
    local dir="${TMP_BASE}/${name}"
    mkdir -p "${dir}"
    git -C "${dir}" init -q
    git -C "${dir}" checkout -q -b "${branch}" 2>/dev/null || true
    touch "${dir}/README.md"
    git -C "${dir}" add README.md
    git -C "${dir}" -c user.email="t@t.com" -c user.name="T" commit -q -m "init"
    echo "${dir}"
}

PROJ_ALPHA=$(make_fake_repo "alpha-api" "feat/login-flow")
PROJ_BETA=$(make_fake_repo "beta-ui" "fix/null-check-parser")
PROJ_GAMMA=$(make_fake_repo "gamma-infra" "chore/k8s-upgrade")

$VERBOSE && echo "  Repos: alpha=${PROJ_ALPHA}"
$VERBOSE && echo "          beta=${PROJ_BETA}"
$VERBOSE && echo "          gamma=${PROJ_GAMMA}"
echo ""

# ── Fake claude driver factory ─────────────────────────────────────────────────

make_fake_claude() {
    local task="$1" tool_json="$2" hold_s="${3:-4}"
    local script="${TMP_BASE}/fake_claude_${RANDOM}.sh"
    cat > "${script}" << FAKECLAUDE
#!/usr/bin/env bash
PATH="/opt/homebrew/bin:/usr/local/bin:\${PATH:-/usr/bin:/bin}"
HR="\${CCP_HOOK_RUNNER:-${HOOK_RUNNER}}"

printf '%s' '{"prompt":"${task}"}' | bash "\${HR}" user-prompt 2>/dev/null || true
sleep 0.4
printf '%s' '${tool_json}' | bash "\${HR}" pre-tool 2>/dev/null || true
sleep ${hold_s}
printf '%s' '{}' | bash "\${HR}" stop 2>/dev/null || true
sleep 1
FAKECLAUDE
    chmod +x "${script}"
    echo "${script}"
}

# ── T1: OSC 1 plumbing ────────────────────────────────────────────────────────
if [[ -z "${ONLY}" || "${ONLY}" == "T1" ]]; then
echo "── T1: OSC 1 plumbing ──────────────────────────────────────────────────────"

T1_LOG="${TMP_BASE}/t1.log"
T1_CLAUDE=$(make_fake_claude \
    "Fix JWT token expiry in login handler" \
    '{"tool_name":"Edit","tool_input":{"file_path":"auth/jwt.go"}}' 5)

WIN1=$(iterm_create_window 1)
OPENED_WINDOWS+=("${WIN1}")
iterm_send "${WIN1}" 1 "cd '${PROJ_ALPHA}' && CCP_TITLE_LOG='${T1_LOG}' CCP_CLAUDE_CMD='${T1_CLAUDE}' bash '${BIN_CCP}' -- dummy 2>/dev/null"

echo "  Waiting for 'alpha-api' in pane title (window ${WIN1})..."
T1_TITLE=$(wait_for_title "${WIN1}" 1 "alpha-api" 12) || T1_TITLE="TIMEOUT"

if [[ "${T1_TITLE}" == "TIMEOUT" ]]; then
    fail "T1: pane title shows project name" "*alpha-api*" "TIMEOUT"
else
    assert_contains "T1: pane title shows project name" "alpha-api" "${T1_TITLE}"
    assert_contains "T1: pane title shows branch" "feat" "${T1_TITLE}"
    $VERBOSE && echo "  Live title: ${T1_TITLE}"
fi

sleep 4
T1_LOG_CONTENT=$(cat "${T1_LOG}" 2>/dev/null || echo "")
assert_contains "T1: CCP_TITLE_LOG written" "alpha-api" "${T1_LOG_CONTENT}"
assert_contains "T1: ✏️ Editing in title log" "Editing" "${T1_LOG_CONTENT}"

iterm_close_window "${WIN1}"
echo ""
fi

# ── T2: --no-dynamic static title ────────────────────────────────────────────
if [[ -z "${ONLY}" || "${ONLY}" == "T2" ]]; then
echo "── T2: --no-dynamic static title ───────────────────────────────────────────"

T2_CLAUDE=$(make_fake_claude \
    "Refactor parser module" \
    '{"tool_name":"Read","tool_input":{"file_path":"parser.py"}}' 4)

WIN2=$(iterm_create_window 1)
OPENED_WINDOWS+=("${WIN2}")
iterm_send "${WIN2}" 1 "cd '${PROJ_BETA}' && CCP_CLAUDE_CMD='${T2_CLAUDE}' bash '${BIN_CCP}' --no-dynamic -- dummy 2>/dev/null"

sleep 4
T2_TITLE=$(iterm_session_name "${WIN2}" 1 2>/dev/null || echo "")
assert_not_contains "T2: --no-dynamic: no 'Reading' status" "Reading" "${T2_TITLE}"
assert_not_contains "T2: --no-dynamic: no spinner chars" "✳" "${T2_TITLE}"
$VERBOSE && echo "  Live title: ${T2_TITLE}"

iterm_close_window "${WIN2}"
echo ""
fi

# ── T4: Full hook chain ───────────────────────────────────────────────────────
if [[ -z "${ONLY}" || "${ONLY}" == "T4" ]]; then
echo "── T4: Full hook chain — status + task summary in live title ───────────────"

T4_LOG="${TMP_BASE}/t4.log"
T4_CLAUDE=$(make_fake_claude \
    "Fix the null pointer in the payment processor module" \
    '{"tool_name":"Bash","tool_input":{"command":"npm test"}}' 8)

WIN4=$(iterm_create_window 1)
OPENED_WINDOWS+=("${WIN4}")
iterm_send "${WIN4}" 1 "cd '${PROJ_ALPHA}' && CCP_TITLE_LOG='${T4_LOG}' CCP_CLAUDE_CMD='${T4_CLAUDE}' bash '${BIN_CCP}' -- dummy 2>/dev/null"

echo "  Waiting for 🧪 Testing in pane title..."
T4_LIVE=$(wait_for_title "${WIN4}" 1 "Testing" 14) || T4_LIVE="TIMEOUT"

if [[ "${T4_LIVE}" == "TIMEOUT" ]]; then
    fail "T4: 🧪 Testing in live title" "*Testing*" "TIMEOUT"
else
    assert_contains "T4: 🧪 Testing in live title" "Testing" "${T4_LIVE}"
    assert_contains "T4: project in live title" "alpha-api" "${T4_LIVE}"
    $VERBOSE && echo "  Live title: ${T4_LIVE}"
fi

sleep 8
T4_LOG_CONTENT=$(cat "${T4_LOG}" 2>/dev/null || echo "")
assert_contains "T4: task summary in title log" "null pointer" "${T4_LOG_CONTENT}"
assert_contains "T4: 🧪 Testing in title log" "Testing" "${T4_LOG_CONTENT}"
assert_contains "T4: project name in title log" "alpha-api" "${T4_LOG_CONTENT}"
$VERBOSE && echo "  Title log (last 3):" && echo "${T4_LOG_CONTENT}" | tail -3

iterm_close_window "${WIN4}"
echo ""
fi

# ── T7: Spinner PREPENDED ────────────────────────────────────────────────────
if [[ -z "${ONLY}" || "${ONLY}" == "T7" ]]; then
echo "── T7: Animated spinner PREPENDED to title ──────────────────────────────────"

T7_LOG="${TMP_BASE}/t7.log"
T7_CLAUDE=$(make_fake_claude \
    "Refactor the authentication middleware layer" \
    '{"tool_name":"Edit","tool_input":{"file_path":"middleware/auth.go"}}' 10)

WIN7=$(iterm_create_window 1)
OPENED_WINDOWS+=("${WIN7}")
iterm_send "${WIN7}" 1 "cd '${PROJ_ALPHA}' && CCP_TITLE_LOG='${T7_LOG}' CCP_CLAUDE_CMD='${T7_CLAUDE}' bash '${BIN_CCP}' -- dummy 2>/dev/null"

echo "  Watching for animated spinner (10s)..."
sleep 10

T7_LOG_CONTENT=$(cat "${T7_LOG}" 2>/dev/null || echo "")
$VERBOSE && echo "  Title log:" && echo "${T7_LOG_CONTENT}"

if has_spinner "${T7_LOG_CONTENT}"; then
    pass "T7: spinner char appears in title log"
else
    fail "T7: spinner char appears in title log" "one of [· ✢ ✳ ✶ ✻ ✽]" "${T7_LOG_CONTENT:0:300}"
fi

if spinner_is_prepended "${T7_LOG_CONTENT}"; then
    pass "T7: spinner is PREPENDED (context starts with spinner char)"
else
    EDITING_LINES=$(grep "Editing" <<< "${T7_LOG_CONTENT}" || echo "none")
    fail "T7: spinner is PREPENDED" "context starts with spinner" "${EDITING_LINES}"
fi

iterm_close_window "${WIN7}"
echo ""
fi

# ── T10: ULTIMATE — 3 concurrent split panes ─────────────────────────────────
if [[ -z "${ONLY}" || "${ONLY}" == "T10" ]]; then
echo "── T10: ULTIMATE — 3 concurrent split panes ─────────────────────────────────"
echo ""
echo "  Core use case: look at 3 split panes and immediately know"
echo "  project · branch · task · status for each. No cross-contamination."
echo ""

T10A_LOG="${TMP_BASE}/t10a.log"
T10B_LOG="${TMP_BASE}/t10b.log"
T10C_LOG="${TMP_BASE}/t10c.log"

FAKE_A=$(make_fake_claude \
    "Fix JWT token expiry in login handler" \
    '{"tool_name":"Edit","tool_input":{"file_path":"auth/jwt.go"}}' 22)

FAKE_B=$(make_fake_claude \
    "Fix the null check in parser utility" \
    '{"tool_name":"Bash","tool_input":{"command":"pytest tests/test_parser.py"}}' 22)

FAKE_C=$(make_fake_claude \
    "Upgrade Kubernetes cluster from 1.28 to 1.30" \
    '{"tool_name":"Bash","tool_input":{"command":"kubectl apply -f manifests/"}}' 22)

WIN10=$(iterm_create_window 3)
OPENED_WINDOWS+=("${WIN10}")
sleep 0.5

echo "  Launching 3 concurrent ccp sessions in window ${WIN10}..."
iterm_send "${WIN10}" 1 "cd '${PROJ_ALPHA}' && CCP_TITLE_LOG='${T10A_LOG}' CCP_CLAUDE_CMD='${FAKE_A}' bash '${BIN_CCP}' -- dummy 2>/dev/null"
sleep 0.3
iterm_send "${WIN10}" 2 "cd '${PROJ_BETA}' && CCP_TITLE_LOG='${T10B_LOG}' CCP_CLAUDE_CMD='${FAKE_B}' bash '${BIN_CCP}' -- dummy 2>/dev/null"
sleep 0.3
iterm_send "${WIN10}" 3 "cd '${PROJ_GAMMA}' && CCP_TITLE_LOG='${T10C_LOG}' CCP_CLAUDE_CMD='${FAKE_C}' bash '${BIN_CCP}' -- dummy 2>/dev/null"

echo "  Waiting for all 3 panes to show their projects (up to 14s)..."
FOUND_A=false; FOUND_B=false; FOUND_C=false
WATCH_START=$SECONDS
while [[ $((SECONDS - WATCH_START)) -lt 14 ]]; do
    TA=$(iterm_session_name "${WIN10}" 1 2>/dev/null || echo "")
    TB=$(iterm_session_name "${WIN10}" 2 2>/dev/null || echo "")
    TC=$(iterm_session_name "${WIN10}" 3 2>/dev/null || echo "")
    [[ "${TA}" == *"alpha-api"* ]] && FOUND_A=true
    [[ "${TB}" == *"beta-ui"* ]] && FOUND_B=true
    [[ "${TC}" == *"gamma-infra"* ]] && FOUND_C=true
    $FOUND_A && $FOUND_B && $FOUND_C && break
    sleep 1
done

TITLE_A=$(iterm_session_name "${WIN10}" 1 2>/dev/null || echo "NOT_FOUND")
TITLE_B=$(iterm_session_name "${WIN10}" 2 2>/dev/null || echo "NOT_FOUND")
TITLE_C=$(iterm_session_name "${WIN10}" 3 2>/dev/null || echo "NOT_FOUND")

echo ""
echo -e "  ${BOLD}Live pane titles — projects visible:${NC}"
echo -e "  Pane 1 (alpha-api):   ${YELLOW}${TITLE_A}${NC}"
echo -e "  Pane 2 (beta-ui):     ${YELLOW}${TITLE_B}${NC}"
echo -e "  Pane 3 (gamma-infra): ${YELLOW}${TITLE_C}${NC}"
echo ""

assert_contains "T10[A]: pane shows 'alpha-api'" "alpha-api" "${TITLE_A}"
assert_contains "T10[B]: pane shows 'beta-ui'" "beta-ui" "${TITLE_B}"
assert_contains "T10[C]: pane shows 'gamma-infra'" "gamma-infra" "${TITLE_C}"
assert_not_contains "T10[A]: no beta-ui bleed" "beta-ui" "${TITLE_A}"
assert_not_contains "T10[B]: no alpha-api bleed" "alpha-api" "${TITLE_B}"
assert_not_contains "T10[C]: no alpha-api bleed" "alpha-api" "${TITLE_C}"

echo "  Waiting for hook statuses to fire (6s)..."
sleep 6

TITLE_A2=$(iterm_session_name "${WIN10}" 1 2>/dev/null || echo "")
TITLE_B2=$(iterm_session_name "${WIN10}" 2 2>/dev/null || echo "")
TITLE_C2=$(iterm_session_name "${WIN10}" 3 2>/dev/null || echo "")

echo ""
echo -e "  ${BOLD}Live pane titles — statuses visible:${NC}"
echo -e "  Pane 1 (alpha-api):   ${YELLOW}${TITLE_A2}${NC}"
echo -e "  Pane 2 (beta-ui):     ${YELLOW}${TITLE_B2}${NC}"
echo -e "  Pane 3 (gamma-infra): ${YELLOW}${TITLE_C2}${NC}"
echo ""

assert_contains "T10[A]: ✏️ Editing in live title" "Editing" "${TITLE_A2}"
assert_contains "T10[B]: 🧪 Testing in live title" "Testing" "${TITLE_B2}"
assert_contains "T10[C]: 🖥️ Running in live title" "Running" "${TITLE_C2}"

echo "  Waiting for title logs to flush (10s)..."
sleep 10

LOG_A=$(cat "${T10A_LOG}" 2>/dev/null || echo "")
LOG_B=$(cat "${T10B_LOG}" 2>/dev/null || echo "")
LOG_C=$(cat "${T10C_LOG}" 2>/dev/null || echo "")

assert_contains "T10[A-log]: ✏️ Editing logged" "Editing" "${LOG_A}"
assert_contains "T10[B-log]: 🧪 Testing logged" "Testing" "${LOG_B}"
assert_contains "T10[C-log]: 🖥️ Running logged" "Running" "${LOG_C}"
assert_contains "T10[A-log]: task summary in log" "JWT" "${LOG_A}"
assert_contains "T10[B-log]: task summary in log" "null" "${LOG_B}"
assert_contains "T10[C-log]: task summary in log" "Kubernetes" "${LOG_C}"
assert_not_contains "T10[A-log]: no cross-contamination" "pytest" "${LOG_A}"
assert_not_contains "T10[B-log]: no cross-contamination" "jwt.go" "${LOG_B}"
assert_not_contains "T10[C-log]: no cross-contamination" "pytest" "${LOG_C}"

$VERBOSE && {
    echo "  Alpha log:" && echo "${LOG_A}" | head -4
    echo "  Beta log:"  && echo "${LOG_B}" | head -4
    echo "  Gamma log:" && echo "${LOG_C}" | head -4
}

iterm_close_window "${WIN10}"
echo ""
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
if [[ "${FAIL}" -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}All ${PASS} tests passed${NC}"
else
    echo -e "${RED}${BOLD}${FAIL} failed / $((PASS + FAIL)) total${NC}"
fi
echo -e "${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

[[ "${FAIL}" -eq 0 ]] && exit 0 || exit 1
