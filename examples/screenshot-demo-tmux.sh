#!/usr/bin/env bash
# examples/screenshot-demo-tmux.sh
#
# Creates before/after tmux screenshots for the README.
#
# Layout: asymmetric 3-pane layout (more realistic than 4 equal panes)
#
#   ┌─ [pane title] ──────────────────────┬─ [pane title] ──────────┐
#   │                                     │                         │
#   │  auth-service  (left, ~62%)         │  dashboard-ui (top-rt)  │
#   │                                     ├─ [pane title] ──────────┤
#   │                                     │                         │
#   │                                     │  data-pipeline (bot-rt) │
#   └─────────────────────────────────────┴─────────────────────────┘
#   │ status bar                                                     │
#   └─────────────────────────────────────────────────────────────────┘
#
# BEFORE: pane-border-status on, but generic "project — claude" titles
#         (what you see without ccp even if you've enabled border status).
# AFTER:  pane-border-status on, rich ccp titles on every pane border.
#
# Output files:
#   docs/screenshots/tmux-before.png
#   docs/screenshots/tmux-after.png
#
# Requirements:
#   - tmux (brew install tmux)
#   - iTerm2 (used as the host terminal for screencapture)
#   - Python 3 with PyObjC/Quartz (for CGWindowID lookup)
#   - macOS screencapture (built-in)
#
# Usage:
#   bash examples/screenshot-demo-tmux.sh [--skip-before] [--skip-after]
#   bash examples/screenshot-demo-tmux.sh --only-after

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FAKE_TUI="${SCRIPT_DIR}/fake_claude_tui.sh"
SHOTS_DIR="${REPO_DIR}/docs/screenshots"
SESSION="ccp-shot"

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

# ── pre-flight ────────────────────────────────────────────────────────────────

if ! command -v tmux &>/dev/null; then
    printf "${RED}ERROR:${NC} tmux not found. Install with: brew install tmux\n"
    exit 1
fi

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

# ── iTerm2 helpers (single-pane window — tmux provides the splits) ─────────────

iterm_create_single() {
    osascript << 'APPLESCRIPT' 2>/dev/null
tell application "iTerm2"
    set newWin to (create window with default profile)
    return id of newWin
end tell
APPLESCRIPT
}

iterm_send() {
    local win_id="$1"
    local cmd="$2"
    local escaped="${cmd//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    osascript << APPLESCRIPT 2>/dev/null
tell application "iTerm2"
    set theWin to first window whose id is ${win_id}
    tell current session of current tab of theWin
        write text "${escaped}"
    end tell
end tell
APPLESCRIPT
}

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

iterm_close() {
    local win_id="$1"
    osascript << APPLESCRIPT 2>/dev/null || true
tell application "iTerm2"
    close (first window whose id is ${win_id})
end tell
APPLESCRIPT
}

# Set window to a nice fixed size that shows macOS chrome (titlebar, rounded
# corners, shadow) — required for clean transparent screenshots.
resize_window() {
    local win_id="$1"
    local screen_bounds
    screen_bounds=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null || echo "0 25 1440 900")
    screen_bounds="${screen_bounds//,/ }"
    local sx sy sx2 sy2 sw sh ww wh wx wy
    sx=$(echo "${screen_bounds}"  | awk '{print $1}')
    sy=$(echo "${screen_bounds}"  | awk '{print $2}')
    sx2=$(echo "${screen_bounds}" | awk '{print $3}')
    sy2=$(echo "${screen_bounds}" | awk '{print $4}')
    sw=$(( sx2 - sx ))
    sh=$(( sy2 - sy ))
    # 90% of screen width, 86% of height — leaves visible macOS drop shadow
    ww=$(( sw * 90 / 100 ))
    wh=$(( sh * 86 / 100 ))
    # Center horizontally; sit slightly above vertical center
    wx=$(( sx + (sw - ww) / 2 ))
    wy=$(( sy + (sh - wh) / 4 ))
    local wx2=$(( wx + ww ))
    local wy2=$(( wy + wh ))
    osascript << APPLESCRIPT 2>/dev/null || true
tell application "iTerm2"
    set theWin to first window whose id is ${win_id}
    set bounds of theWin to {${wx}, ${wy}, ${wx2}, ${wy2}}
end tell
APPLESCRIPT
    sleep 0.4
}

# Get the CoreGraphics window ID of the frontmost iTerm2 window.
# CGWindowListCopyWindowInfo returns windows in front-to-back order, so the
# first iTerm2 layer-0 window is the one currently in focus.
# Call this immediately after resize_window while the new window is still front.
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
# cg_id must be obtained right after the window is created/focused — not at
# capture time — because focus may have returned to the script's own terminal.
# This produces a PNG with transparent background, rounded corners, and
# macOS drop shadow — the same output as Shottr's window capture mode.
capture_window() {
    local cg_id="$1"    # CoreGraphics window ID (from get_cg_window_id)
    local outfile="$2"

    if [[ -z "${cg_id}" ]]; then
        warn "No CGWindowID — falling back to full-screen capture"
        screencapture -x "${outfile}"
        info "Saved (fallback): ${outfile}"
        return
    fi

    # -l: capture specific window with shadow + transparency
    # -x: suppress camera shutter sound
    screencapture -l "${cg_id}" -x "${outfile}"
    info "Saved: ${outfile}"
}

# ── tmux session setup ────────────────────────────────────────────────────────

# Build and populate the 3-pane session.
# title_mode: "before" or "after"
tmux_setup() {
    local title_mode="$1"

    # Kill any stale session from a previous run
    tmux kill-session -t "${SESSION}" 2>/dev/null || true

    # Create a detached session.
    # -x/-y set the initial pseudo-terminal size; tmux will resize when
    # a client attaches, so these are just a safe fallback.
    tmux new-session -d -s "${SESSION}" -x 220 -y 56

    # ── layout: left 62%, right-top + right-bottom ─────────────────────────────
    # split-window -h splits the current pane horizontally.
    # -p 38 means the NEW (right) pane gets 38% of the width.
    tmux split-window -h -t "${SESSION}:0" -p 38
    # Split the right pane (-t 0.1) vertically; new (bottom-right) gets 50%.
    tmux split-window -v -t "${SESSION}:0.1" -p 50

    # ── tmux appearance ────────────────────────────────────────────────────────
    # Status bar — dark, minimal, readable in screenshots
    tmux set -t "${SESSION}" status on
    tmux set -t "${SESSION}" status-style         "bg=colour235,fg=colour250"
    tmux set -t "${SESSION}" status-left          "#[bold,fg=colour111] ccp #[nobold,fg=colour240]│ "
    tmux set -t "${SESSION}" status-left-length   14
    tmux set -t "${SESSION}" status-right         "#[fg=colour240] %H:%M "
    tmux set -t "${SESSION}" status-right-length  10
    tmux set -t "${SESSION}" window-status-format          " #I:#W "
    tmux set -t "${SESSION}" window-status-current-format  "#[bold,fg=colour255] #I:#W "

    # Pane borders — bg=colour234 ensures the title row is visually distinct
    # even for panes at the outer terminal edge (no border line above them).
    tmux set -t "${SESSION}" pane-border-style        "bg=colour234,fg=colour238"
    tmux set -t "${SESSION}" pane-active-border-style "bg=colour234,fg=colour69"

    # pane-border-status is ON in both before and after modes — the comparison
    # is about what appears in the titles, not whether titles are shown at all.
    tmux set -t "${SESSION}" pane-border-status top
    tmux set -t "${SESSION}" automatic-rename off

    if [[ "${title_mode}" == "after" ]]; then
        # Rich ccp title format: "project (branch) | task | status"
        # Source of truth: lib/title.sh:format_title_prefix + lib/hook_runner.sh status strings
        tmux set -t "${SESSION}" pane-border-format \
            "#[bg=colour234,fg=colour111,bold] #{pane_title} #[nobold,fg=colour238]"
    else
        # "before" — border status on, but generic titles (no ccp).
        # Dimmer format to emphasise how little info you get without ccp.
        tmux set -t "${SESSION}" pane-border-format \
            "#[bg=colour234,fg=colour240] #{pane_title} "
    fi

    # ── launch fake TUIs ───────────────────────────────────────────────────────
    local -a scenarios=(editing testing building)
    local i
    for i in 0 1 2; do
        tmux send-keys -t "${SESSION}:0.${i}" \
            "bash '${FAKE_TUI}' --scenario '${scenarios[$i]}' --title-mode '${title_mode}'" Enter
        sleep 0.25
    done

    info "Waiting for TUIs to render (3s)..."
    sleep 3

    # ── set per-pane titles ────────────────────────────────────────────────────
    if [[ "${title_mode}" == "after" ]]; then
        # Rich ccp titles
        tmux select-pane -t "${SESSION}:0.0" -T "auth-service (feat/oauth2) | Fix JWT expiry check | ✏️ Editing"
        tmux select-pane -t "${SESSION}:0.1" -T "dashboard-ui (fix/layout-shift) | Audit component tests | 🧪 Testing"
        tmux select-pane -t "${SESSION}:0.2" -T "data-pipeline (feat/embeddings) | Fix TypeScript errors | 🔨 Building"
    else
        # Generic titles — what you see when pane-border-status is on but ccp
        # is not running (Claude Code sets no pane title by default).
        tmux select-pane -t "${SESSION}:0.0" -T "auth-service — claude"
        tmux select-pane -t "${SESSION}:0.1" -T "dashboard-ui — claude"
        tmux select-pane -t "${SESSION}:0.2" -T "data-pipeline — claude"
    fi
}

# ── BEFORE screenshot ─────────────────────────────────────────────────────────

if $DO_BEFORE; then
    heading "Creating BEFORE tmux screenshot (border status on, generic titles)"

    tmux_setup "before"
    info "Session ready: ${SESSION}"

    WIN=$(iterm_create_single)
    info "iTerm2 window ID: ${WIN}"
    resize_window "${WIN}"
    # Grab CGWindowID now — the new window is frontmost right after creation.
    # Do NOT wait until capture time: running the script may return focus to
    # this terminal and get_cg_window_id() would return the wrong window.
    CG_WIN=$(get_cg_window_id) || CG_WIN=""
    info "CGWindowID: ${CG_WIN}"
    sleep 0.4

    # Attach to the tmux session; tmux will resize to fill the iTerm2 window
    iterm_send "${WIN}" "tmux attach-session -t ${SESSION}"
    sleep 1.8   # let tmux attach + redraw

    iterm_focus "${WIN}"
    sleep 0.4

    capture_window "${CG_WIN}" "${SHOTS_DIR}/tmux-before.png"

    info "Detaching and cleaning up..."
    tmux kill-session -t "${SESSION}" 2>/dev/null || true
    iterm_close "${WIN}"
    sleep 0.5
fi

# ── AFTER screenshot ──────────────────────────────────────────────────────────

if $DO_AFTER; then
    heading "Creating AFTER tmux screenshot (pane borders show ccp titles)"

    tmux_setup "after"
    info "Session ready: ${SESSION}"

    WIN=$(iterm_create_single)
    info "iTerm2 window ID: ${WIN}"
    resize_window "${WIN}"
    CG_WIN=$(get_cg_window_id) || CG_WIN=""
    info "CGWindowID: ${CG_WIN}"
    sleep 0.4

    iterm_send "${WIN}" "tmux attach-session -t ${SESSION}"
    sleep 1.8

    # Re-apply pane titles after attach — the fake TUI's hold loop sends OSC 1
    # every 2s which in tmux 3.0+ can update #{pane_title}, potentially
    # overwriting our select-pane -T calls from tmux_setup.  Re-stamp here
    # right before the screenshot to guarantee the correct titles are shown.
    tmux select-pane -t "${SESSION}:0.0" -T "auth-service (feat/oauth2) | Fix JWT expiry check | ✏️ Editing"
    tmux select-pane -t "${SESSION}:0.1" -T "dashboard-ui (fix/layout-shift) | Audit component tests | 🧪 Testing"
    tmux select-pane -t "${SESSION}:0.2" -T "data-pipeline (feat/embeddings) | Fix TypeScript errors | 🔨 Building"
    sleep 0.3

    iterm_focus "${WIN}"
    sleep 0.4

    capture_window "${CG_WIN}" "${SHOTS_DIR}/tmux-after.png"

    info "Detaching and cleaning up..."
    tmux kill-session -t "${SESSION}" 2>/dev/null || true
    iterm_close "${WIN}"
    sleep 0.5
fi

# ── summary ───────────────────────────────────────────────────────────────────

heading "Done"
if $DO_BEFORE; then info "tmux-before.png → ${SHOTS_DIR}/tmux-before.png"; fi
if $DO_AFTER;  then info "tmux-after.png  → ${SHOTS_DIR}/tmux-after.png";  fi
echo ""
printf "  Re-run anytime:\n\n"
printf "    bash examples/screenshot-demo-tmux.sh\n\n"
