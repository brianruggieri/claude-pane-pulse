#!/usr/bin/env bash
# examples/gif-demo.sh
#
# Creates an animated GIF showing ccp pane title updates cycling through
# a realistic sequence of statuses. The terminal content is a plain shell
# prompt — the demo is entirely in the title bar.
#
# Output: docs/screenshots/demo.gif
#
# Requirements:
#   - iTerm2 with AppleScript access
#   - ImageMagick: brew install imagemagick
#   - Optional: gifsicle (brew install gifsicle) for optimization
#
# Usage:
#   bash examples/gif-demo.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHOTS_DIR="${REPO_DIR}/docs/screenshots"
FRAMES_DIR="${SHOTS_DIR}/gif-frames"

# ── colors ────────────────────────────────────────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { printf "  ${GREEN}→${NC}  %s\n" "$*"; }
warn()    { printf "  ${YELLOW}!${NC}  %s\n" "$*"; }
heading() { printf "\n${BOLD}%s${NC}\n\n" "$*"; }
die()     { printf "${RED}ERROR:${NC} %s\n" "$*" >&2; exit 1; }

# ── preflight ─────────────────────────────────────────────────────────────────

osascript -e 'tell application "iTerm2" to return "ok"' &>/dev/null \
    || die "Cannot reach iTerm2 via AppleScript. Make sure iTerm2 is running."

command -v magick &>/dev/null \
    || die "ImageMagick not found. Install with: brew install imagemagick (provides magick command)"

mkdir -p "${SHOTS_DIR}" "${FRAMES_DIR}"
rm -f "${FRAMES_DIR}"/frame_*.png

# ── title sequence ────────────────────────────────────────────────────────────
#
# Each entry: "HOLD_SECONDS|PANE_TITLE"
# Simulates a realistic ccp session lifecycle for auth-service/feat/oauth2.

FRAMES=(
    "2.5|auth-service — claude"
    "2.0|auth-service (feat/oauth2) | Fix JWT expiry check | 💭 Thinking"
    "2.5|auth-service (feat/oauth2) | Fix JWT expiry check | 📖 Reading"
    "2.5|auth-service (feat/oauth2) | Fix JWT expiry check | ✏️ Editing"
    "2.0|auth-service (feat/oauth2) | Fix JWT expiry check | 🧪 Testing"
    "2.5|auth-service (feat/oauth2) | Fix JWT expiry check | ✅ Tests passed"
    "2.0|auth-service (feat/oauth2) | Fix JWT expiry check | 💾 Committed"
    "2.0|auth-service (feat/oauth2) | 🫡 Standing by"
)

# Delay values for ImageMagick (hundredths of a second)
# Derived from HOLD_SECONDS × 100
declare -a IM_DELAYS=()

# ── AppleScript helpers ───────────────────────────────────────────────────────

iterm_create_window() {
    osascript << 'AS'
tell application "iTerm2"
    set w to (create window with default profile)
    return id of w
end tell
AS
}

iterm_send() {
    local win_id="$1" cmd="$2"
    local esc="${cmd//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    osascript << AS 2>/dev/null
tell application "iTerm2"
    tell current session of current tab of (first window whose id is ${win_id})
        write text "${esc}"
    end tell
end tell
AS
}


iterm_resize() {
    local win_id="$1"
    # Wide, short window — tab bar is prominent, minimal terminal content visible.
    # 960×140 pt gives the macOS chrome + iTerm2 tab bar + ~2 terminal lines.
    local screen_w screen_h wx wy ww wh
    screen_w=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null \
        | awk -F'[, ]+' '{print $3}') || screen_w=1440
    screen_h=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null \
        | awk -F'[, ]+' '{print $4}') || screen_h=900
    ww=960; wh=140
    wx=$(( (screen_w - ww) / 2 ))
    wy=$(( (screen_h - wh) / 3 ))
    osascript << AS 2>/dev/null || true
tell application "iTerm2"
    set bounds of (first window whose id is ${win_id}) to {${wx}, ${wy}, $((wx + ww)), $((wy + wh))}
end tell
AS
    sleep 0.5
}

iterm_focus() {
    local win_id="$1"
    osascript << AS 2>/dev/null || true
tell application "iTerm2"
    activate
    select (first window whose id is ${win_id})
end tell
AS
}

iterm_close() {
    local win_id="$1"
    osascript << AS 2>/dev/null || true
tell application "iTerm2"
    close (first window whose id is ${win_id})
end tell
AS
}

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

capture_frame() {
    local cg_id="$1" outfile="$2"
    if [[ -n "${cg_id}" ]]; then
        screencapture -l "${cg_id}" -x "${outfile}"
    else
        screencapture -x "${outfile}"
    fi
}

# ── main ──────────────────────────────────────────────────────────────────────

heading "Creating iTerm2 window"

WIN=$(iterm_create_window)
info "Window ID: ${WIN}"

iterm_resize "${WIN}"
iterm_focus "${WIN}"
sleep 0.3

CG=$(get_cg_window_id) || CG=""
info "CGWindowID: ${CG:-none (will use full-screen fallback)}"

# Use a temp file to drive the title — the pane runs a loop that reads from it
# and re-asserts the OSC escape every 0.3s, preventing zsh from overwriting.
# This mirrors how ccp's monitor.sh drives title updates via a status file.
TITLE_FILE="/tmp/ccp_gif_title_$$.txt"
printf '%s' "" > "${TITLE_FILE}"

PANE_LOOP="export DISABLE_AUTO_TITLE=true; clear; "
PANE_LOOP+="T='${TITLE_FILE}'; "
PANE_LOOP+="while true; do "
PANE_LOOP+="  t=\$(cat \"\$T\" 2>/dev/null); "
PANE_LOOP+="  printf '\\033]1;%s\\007\\033]2;\\007' \"\$t\"; "
PANE_LOOP+="  read -r -t 0.3 2>/dev/null || true; "
PANE_LOOP+="done"

iterm_send "${WIN}" "${PANE_LOOP}"
sleep 0.8

heading "Capturing frames"

frame_n=0
for entry in "${FRAMES[@]}"; do
    hold="${entry%%|*}"
    title="${entry#*|}"
    frame_n=$(( frame_n + 1 ))
    padded=$(printf "%03d" "${frame_n}")

    info "Frame ${padded}: ${title}"

    # Write new title to the file — pane loop picks it up within 0.3s
    printf '%s' "${title}" > "${TITLE_FILE}"
    sleep 0.7    # wait for loop to fire + iTerm2 to render

    outfile="${FRAMES_DIR}/frame_${padded}.png"
    capture_frame "${CG}" "${outfile}"

    # Record delay in ImageMagick hundredths-of-a-second units
    delay_cs=$(python3 -c "print(int(float('${hold}') * 100))")
    IM_DELAYS+=("${delay_cs}")

    # Hold for remainder of frame duration (already spent ~0.7s above)
    remaining=$(python3 -c "r=float('${hold}')-0.7; print(max(r,0))")
    [[ "${remaining}" != "0" ]] && sleep "${remaining}"
done

info "Captured ${frame_n} frames"
rm -f "${TITLE_FILE}"

heading "Closing window"
iterm_close "${WIN}"
sleep 0.3

# ── assemble GIF ──────────────────────────────────────────────────────────────

heading "Assembling APNG"

OUT="${SHOTS_DIR}/demo.apng"

# Crop each frame: flatten alpha to white, trim shadow padding from screencapture -l.
info "Processing frames..."
for i in "${!IM_DELAYS[@]}"; do
    frame_n=$(( i + 1 ))
    padded=$(printf "%03d" "${frame_n}")
    src="${FRAMES_DIR}/frame_${padded}.png"
    cropped="${FRAMES_DIR}/cropped_${padded}.png"
    magick "${src}" -background white -alpha remove -alpha off -trim +repage "${cropped}"
done

# Build ffmpeg concat file with per-frame durations (in seconds).
# APNG via ffmpeg preserves full PNG quality — no palette reduction, no dithering.
CONCAT_FILE="${FRAMES_DIR}/concat.txt"
> "${CONCAT_FILE}"
for i in "${!IM_DELAYS[@]}"; do
    frame_n=$(( i + 1 ))
    padded=$(printf "%03d" "${frame_n}")
    duration_s=$(python3 -c "print(${IM_DELAYS[$i]} / 100)")
    printf "file 'cropped_%s.png'\nduration %s\n" "${padded}" "${duration_s}" >> "${CONCAT_FILE}"
done
# ffmpeg concat requires the last frame listed twice (duration ignored on final entry)
last_padded=$(printf "%03d" "${#IM_DELAYS[@]}")
printf "file 'cropped_%s.png'\n" "${last_padded}" >> "${CONCAT_FILE}"

ffmpeg -y -f concat -safe 0 -i "${CONCAT_FILE}" \
    -plays 0 \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
    "${OUT}" 2>/dev/null

info "APNG assembled: ${OUT} ($(du -sh "${OUT}" | awk '{print $1}'))"

# ── summary ───────────────────────────────────────────────────────────────────

heading "Done"
printf "  Output: ${BOLD}%s${NC}\n" "${OUT}"
printf "  Size:   %s\n\n" "$(du -sh "${OUT}" | awk '{print $1}')"
printf "  To embed in README:\n"
printf "  ${DIM}![ccp demo](docs/screenshots/demo.apng)${NC}\n\n"
printf "  To re-run:\n"
printf "  ${DIM}bash examples/gif-demo.sh${NC}\n\n"
