#!/usr/bin/env bash
# examples/screenshot-demo.sh
#
# Creates two iTerm2 windows showing the ccp "before vs after" comparison,
# then captures a screenshot of each.
#
# BEFORE window: 4 split panes running fake Claude Code sessions.
#   Pane titles are the generic "PROJECTNAME — claude" that you'd see
#   without ccp — you have to look inside each pane to know what's happening.
#
# AFTER window: identical pane content, but titles updated by ccp.
#   Each tab instantly shows: project · branch · task · animated status.
#
# Output files:
#   docs/screenshots/before.png
#   docs/screenshots/after.png
#
# Requirements:
#   - iTerm2 (accessible via AppleScript)
#   - macOS screencapture (built-in)
#
# Usage:
#   bash examples/screenshot-demo.sh [--skip-before] [--skip-after]
#   bash examples/screenshot-demo.sh --only-after

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FAKE_TUI="${SCRIPT_DIR}/fake_claude_tui.sh"
SHOTS_DIR="${REPO_DIR}/docs/screenshots"

DO_BEFORE=true
DO_AFTER=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-before) DO_BEFORE=false; shift ;;
        --skip-after)  DO_AFTER=false;  shift ;;
        --only-before) DO_AFTER=false;  shift ;;
        --only-after)  DO_BEFORE=false; shift ;;
        *) shift ;;
    esac
done

# ── colors ────────────────────────────────────────────────────────────────────

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { printf "  ${GREEN}→${NC}  %s\n" "$*"; }
warn()    { printf "  ${YELLOW}!${NC}  %s\n" "$*"; }
heading() { echo ""; printf "${BOLD}%s${NC}\n" "$*"; echo ""; }

# ── pre-flight ─────────────────────────────────────────────────────────────────

if ! osascript -e 'tell application "iTerm2" to return "ok"' &>/dev/null; then
    printf "${RED}ERROR:${NC} Cannot reach iTerm2 via AppleScript.\n"
    printf "       Make sure iTerm2 is running and Accessibility is enabled.\n"
    exit 1
fi

if [[ ! -f "${FAKE_TUI}" ]]; then
    printf "${RED}ERROR:${NC} fake_claude_tui.sh not found at %s\n" "${FAKE_TUI}"
    exit 1
fi

mkdir -p "${SHOTS_DIR}"

# ── AppleScript helpers ───────────────────────────────────────────────────────

# Create a 2×2 split pane iTerm2 window.
# Returns the window ID on stdout.
iterm_create_2x2() {
    osascript << 'APPLESCRIPT' 2>/dev/null
tell application "iTerm2"
    set newWin to (create window with default profile)
    tell current tab of newWin
        -- Start: single pane (top-left)
        set tl to current session
        -- Split right → top-right
        set tr to split vertically with default profile of tl
        -- Split top-left down → bottom-left
        set bl to split horizontally with default profile of tl
        -- Split top-right down → bottom-right
        set br to split horizontally with default profile of tr
    end tell
    return id of newWin
end tell
APPLESCRIPT
}

# Send a shell command to the nth session in the window (1-indexed, row-major).
iterm_send() {
    local win_id="$1" n="$2"
    local cmd="$3"
    local escaped="${cmd//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    osascript << APPLESCRIPT 2>/dev/null
tell application "iTerm2"
    set theWin to first window whose id is ${win_id}
    set theSessions to sessions of current tab of theWin
    if (count of theSessions) >= ${n} then
        tell item ${n} of theSessions
            write text "${escaped}"
        end tell
    end if
end tell
APPLESCRIPT
}

# Get the pixel bounds {left, top, right, bottom} of the window as space-separated values.
iterm_window_bounds() {
    local win_id="$1"
    osascript << APPLESCRIPT 2>/dev/null
tell application "iTerm2"
    set theWin to first window whose id is ${win_id}
    set b to bounds of theWin
    return ((item 1 of b) as text) & " " & ((item 2 of b) as text) & " " & ((item 3 of b) as text) & " " & ((item 4 of b) as text)
end tell
APPLESCRIPT
}

# Close the window (best-effort).
iterm_close() {
    local win_id="$1"
    osascript << APPLESCRIPT 2>/dev/null || true
tell application "iTerm2"
    close (first window whose id is ${win_id})
end tell
APPLESCRIPT
}

# Set all 4 pane names in a window directly via AppleScript.
# This bypasses shell auto-title and iTerm2 "job name" appending.
# t1..t4 are the title strings for panes 1-4 (row-major).
iterm_set_pane_names() {
    local win_id="$1" t1="${2:-}" t2="${3:-}" t3="${4:-}" t4="${5:-}"
    osascript - "${win_id}" "${t1}" "${t2}" "${t3}" "${t4}" << 'APPLESCRIPT' 2>/dev/null || true
on run argv
    set winId to (item 1 of argv) as integer
    set titles to {item 2 of argv, item 3 of argv, item 4 of argv, item 5 of argv}
    tell application "iTerm2"
        set theWin to first window whose id is winId
        set theSessions to sessions of current tab of theWin
        repeat with i from 1 to count of titles
            if (count of theSessions) >= i then
                set name of item i of theSessions to item i of titles
            end if
        end repeat
    end tell
end run
APPLESCRIPT
}

# Bring iTerm2 to the front and focus the given window.
iterm_focus() {
    local win_id="$1"
    osascript << APPLESCRIPT 2>/dev/null || true
tell application "iTerm2"
    activate
    set theWin to first window whose id is ${win_id}
    select theWin
end tell
APPLESCRIPT
}

# ── screenshot helpers ────────────────────────────────────────────────────────

# Get the CoreGraphics window ID of the frontmost iTerm2 window.
# Call immediately after creating/resizing the window, before anything
# can steal focus back to the script's own terminal.
get_cg_window_id() {
    python3 - << 'PY' 2>/dev/null
import Quartz
wins = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionOnScreenOnly,
    Quartz.kCGNullWindowID
)
for w in wins:
    if (w.get("kCGWindowOwnerName") == "iTerm2"
            and w.get("kCGWindowLayer", 1) == 0
            and w.get("kCGWindowAlpha", 0.0) > 0):
        print(w["kCGWindowNumber"])
        break
PY
}

# Capture an iTerm2 window using screencapture -l (window ID mode).
# Produces a PNG with transparent background, rounded corners, and macOS
# drop shadow — equivalent to Shottr window capture mode.
# cg_id must be obtained right after window creation, not at capture time.
capture_window() {
    local cg_id="$1"
    local outfile="$2"

    if [[ -z "${cg_id}" ]]; then
        warn "No CGWindowID — falling back to full-screen capture"
        screencapture -x "${outfile}"
        info "Saved (fallback): ${outfile}"
        return
    fi

    screencapture -l "${cg_id}" -x "${outfile}"
    info "Saved: ${outfile}"
}

# ── scenarios ─────────────────────────────────────────────────────────────────

# The 4 pane scenarios, in row-major order for a 2×2 grid:
#   Pane 1 (top-left)     editing   auth-service
#   Pane 2 (top-right)    testing   dashboard-ui
#   Pane 3 (bottom-left)  building  data-pipeline
#   Pane 4 (bottom-right) thinking  infra-tools
SCENARIOS=(editing testing building thinking)

# ── window sizing ─────────────────────────────────────────────────────────────

# Set window to a nice fixed size that keeps macOS chrome visible
# (titlebar, rounded corners, drop shadow) for clean transparent screenshots.
resize_window() {
    local win_id="$1"
    local screen_bounds
    screen_bounds=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null || echo "0 25 1440 900")
    screen_bounds="${screen_bounds//,/ }"
    local sx sy sx2 sy2 sw sh ww wh wx wy wx2 wy2
    sx=$(echo "${screen_bounds}"  | awk '{print $1}')
    sy=$(echo "${screen_bounds}"  | awk '{print $2}')
    sx2=$(echo "${screen_bounds}" | awk '{print $3}')
    sy2=$(echo "${screen_bounds}" | awk '{print $4}')
    [[ ${sy} -lt 25 ]] && sy=25
    sw=$(( sx2 - sx ))
    sh=$(( sy2 - sy ))
    ww=$(( sw * 90 / 100 ))
    wh=$(( sh * 86 / 100 ))
    wx=$(( sx + (sw - ww) / 2 ))
    wy=$(( sy + (sh - wh) / 4 ))
    wx2=$(( wx + ww ))
    wy2=$(( wy + wh ))
    osascript << APPLESCRIPT 2>/dev/null || true
tell application "iTerm2"
    set theWin to first window whose id is ${win_id}
    set bounds of theWin to {${wx}, ${wy}, ${wx2}, ${wy2}}
end tell
APPLESCRIPT
    sleep 0.4
}

# ── BEFORE window ─────────────────────────────────────────────────────────────

if $DO_BEFORE; then
    heading "Creating BEFORE window (generic titles, no ccp)"

    WIN_BEFORE=$(iterm_create_2x2)
    info "Window ID: ${WIN_BEFORE}"
    resize_window "${WIN_BEFORE}"
    # Grab CGWindowID now — window is frontmost right after creation.
    CG_BEFORE=$(get_cg_window_id) || CG_BEFORE=""
    info "CGWindowID: ${CG_BEFORE}"
    sleep 0.4

    # Dismiss any shell prompts and start fake TUIs
    local_pane=1
    for scenario in "${SCENARIOS[@]}"; do
        info "Pane ${local_pane}: --scenario ${scenario} --title-mode before"
        iterm_send "${WIN_BEFORE}" "${local_pane}" \
            "bash '${FAKE_TUI}' --scenario '${scenario}' --title-mode before"
        sleep 0.3
        local_pane=$(( local_pane + 1 ))
    done

    info "Waiting for TUIs to render (3s)..."
    sleep 3

    # Lock pane names via AppleScript — bypasses shell auto-title and
    # iTerm2 "append job name" profile setting
    info "Setting pane names (before)..."
    iterm_set_pane_names "${WIN_BEFORE}" \
        "auth-service — claude" \
        "dashboard-ui — claude" \
        "data-pipeline — claude" \
        "infra-tools — claude"
    sleep 0.4

    iterm_focus "${WIN_BEFORE}"
    sleep 0.3

    capture_window "${CG_BEFORE}" "${SHOTS_DIR}/before.png"

    info "Closing BEFORE window..."
    iterm_close "${WIN_BEFORE}"
    sleep 0.5
fi

# ── AFTER window ──────────────────────────────────────────────────────────────

if $DO_AFTER; then
    heading "Creating AFTER window (rich ccp titles)"

    WIN_AFTER=$(iterm_create_2x2)
    info "Window ID: ${WIN_AFTER}"
    resize_window "${WIN_AFTER}"
    CG_AFTER=$(get_cg_window_id) || CG_AFTER=""
    info "CGWindowID: ${CG_AFTER}"
    sleep 0.4

    local_pane=1
    for scenario in "${SCENARIOS[@]}"; do
        info "Pane ${local_pane}: --scenario ${scenario} --title-mode after"
        iterm_send "${WIN_AFTER}" "${local_pane}" \
            "bash '${FAKE_TUI}' --scenario '${scenario}' --title-mode after"
        sleep 0.3
        local_pane=$(( local_pane + 1 ))
    done

    info "Waiting for TUIs to render (3s)..."
    sleep 3

    # Lock pane names via AppleScript — bypasses shell auto-title / job name
    # Title format: "project (branch) | task | status"
    # Source of truth: lib/title.sh:format_title_prefix + lib/hook_runner.sh status strings
    # If ccp's title format changes, update these strings to match.
    info "Setting pane names (after)..."
    iterm_set_pane_names "${WIN_AFTER}" \
        "auth-service (feat/oauth2) | Fix JWT expiry check | ✏️ Editing" \
        "dashboard-ui (fix/layout-shift) | Audit component tests | 🧪 Testing" \
        "data-pipeline (feat/embeddings) | Fix TypeScript errors | 🔨 Building" \
        "infra-tools (chore/terraform-up) | Plan Terraform upgrade | 📖 Reading"
    sleep 0.4

    iterm_focus "${WIN_AFTER}"
    sleep 0.3

    capture_window "${CG_AFTER}" "${SHOTS_DIR}/after.png"

    info "Closing AFTER window..."
    iterm_close "${WIN_AFTER}"
    sleep 0.5
fi

# ── summary ───────────────────────────────────────────────────────────────────

heading "Done"
if $DO_BEFORE; then info "before.png → ${SHOTS_DIR}/before.png"; fi
if $DO_AFTER;  then info "after.png  → ${SHOTS_DIR}/after.png";  fi
echo ""
printf "  If the screenshots need tweaking, adjust font size or window\n"
printf "  dimensions in iTerm2, then re-run:\n\n"
printf "    bash examples/screenshot-demo.sh\n\n"
