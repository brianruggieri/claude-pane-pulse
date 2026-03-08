#!/usr/bin/env bash
# examples/gif-demo-4pane.sh
#
# Creates an animated GIF showing four independent ccp pane title updates.
# Each pane progresses through its own lifecycle — content AND title both
# change per frame so it looks like real parallel work in progress.
#
# Output: docs/screenshots/demo-4pane.gif
#
# Requirements:
#   - iTerm2 with AppleScript access
#   - ImageMagick: brew install imagemagick
#   - ffmpeg: brew install ffmpeg  (best quality GIF encoding)
#   - Optional: gifsicle (brew install gifsicle) for final compression
#
# Usage:
#   bash examples/gif-demo-4pane.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FAKE_TUI="${SCRIPT_DIR}/fake_claude_tui.sh"
SHOTS_DIR="${REPO_DIR}/docs/screenshots"
FRAMES_DIR="${SHOTS_DIR}/gif-frames-4pane"

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

# ── pre-flight ────────────────────────────────────────────────────────────────

osascript -e 'tell application "iTerm2" to return "ok"' &>/dev/null \
    || die "Cannot reach iTerm2 via AppleScript. Make sure iTerm2 is running."

[[ -f "${FAKE_TUI}" ]] \
    || die "fake_claude_tui.sh not found at ${FAKE_TUI}"

command -v magick &>/dev/null \
    || die "ImageMagick not found. Install with: brew install imagemagick"

command -v python3 &>/dev/null \
    || die "python3 not found. Install with: brew install python3"

mkdir -p "${SHOTS_DIR}" "${FRAMES_DIR}"
rm -f "${FRAMES_DIR}"/frame_*.png "${FRAMES_DIR}"/processed_*.png \
      "${FRAMES_DIR}"/palette.png

# ── frame sequence ────────────────────────────────────────────────────────────
#
# Each entry uses ^ as the field separator (never appears in terminal titles):
#   DELAY_CS ^ P1_TITLE ^ P2_TITLE ^ P3_TITLE ^ P4_TITLE ^ P1_SCENARIO ^ P2_SCENARIO ^ P3_SCENARIO ^ P4_SCENARIO
#
# DELAY_CS = GIF frame duration in ImageMagick hundredths-of-a-second.
#
# Story: 4 parallel Claude Code agents. Each pane's title AND content both
# change independently. The viewer sees work completing at different times
# across all 4 panes without looking at any terminal output.
#
# Pane 1 — auth-service:  editing JWT fix → tests pass → committed → idle
# Pane 2 — dashboard-ui:  tests running (with failures) → tests pass → done
# Pane 3 — data-pipeline: tsc build errors → build clean → done
# Pane 4 — infra-tools:   planning Terraform → editing → pushing → done

FRAMES=(
    # Frame 1: All 4 agents mid-work, different tasks
    "200^auth-service (feat/oauth2) | Fix JWT expiry | ✏️ Editing^dashboard-ui (fix/layout-shift) | Audit tests | 🧪 Testing^data-pipeline (feat/embeddings) | Fix TS errors | 🔨 Building^infra-tools (chore/tf-up) | Plan Terraform | 📖 Reading^editing^testing^building^thinking"

    # Frame 2: P1 runs tests and they pass; P4 pivots to editing
    "150^auth-service (feat/oauth2) | Fix JWT expiry | ✅ Tests passed^dashboard-ui (fix/layout-shift) | Audit tests | 🧪 Testing^data-pipeline (feat/embeddings) | Fix TS errors | 🔨 Building^infra-tools (chore/tf-up) | Plan Terraform | ✏️ Editing^complete^testing^building^thinking"

    # Frame 3: P1 commits; P3 build finishes with tests passing
    "150^auth-service (feat/oauth2) | Fix JWT expiry | 💾 Committed^dashboard-ui (fix/layout-shift) | Audit tests | 🧪 Testing^data-pipeline (feat/embeddings) | Fix TS errors | ✅ Tests passed^infra-tools (chore/tf-up) | Plan Terraform | ✏️ Editing^committed^testing^complete^thinking"

    # Frame 4: P1 goes idle; P2 tests pass; P3 commits; P4 pushes
    "150^auth-service (feat/oauth2) | Fix JWT expiry | ☕ Recharging^dashboard-ui (fix/layout-shift) | Audit tests | ✅ Tests passed^data-pipeline (feat/embeddings) | Fix TS errors | 💾 Committed^infra-tools (chore/tf-up) | Plan Terraform | ⬆️ Pushing^committed^complete^complete^pushing"

    # Frame 5: Everything wrapping up — hold on final state
    "200^auth-service (feat/oauth2) | Fix JWT expiry | 🫡 Standing by^dashboard-ui (fix/layout-shift) | Audit tests | 💾 Committed^data-pipeline (feat/embeddings) | Fix TS errors | 🫡 Standing by^infra-tools (chore/tf-up) | Plan Terraform | 💾 Committed^committed^complete^complete^pushing"
)

# ── AppleScript / window helpers ──────────────────────────────────────────────

iterm_create_2x2() {
    osascript << 'AS' 2>/dev/null
tell application "iTerm2"
    set newWin to (create window with default profile)
    tell current tab of newWin
        set tl to current session
        set tr to split vertically with default profile of tl
        set bl to split horizontally with default profile of tl
        set br to split horizontally with default profile of tr
    end tell
    return id of newWin
end tell
AS
}

iterm_send() {
    local win_id="$1" n="$2" cmd="$3"
    local esc="${cmd//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    osascript << AS 2>/dev/null
tell application "iTerm2"
    set theWin to first window whose id is ${win_id}
    set theSessions to sessions of current tab of theWin
    if (count of theSessions) >= ${n} then
        tell item ${n} of theSessions
            write text "${esc}"
        end tell
    end if
end tell
AS
}

# Set all 4 pane titles via AppleScript for immediate render.
# Combined with title-file polling in fake_claude_tui.sh for reliability.
iterm_set_pane_names() {
    local win_id="$1" t1="${2:-}" t2="${3:-}" t3="${4:-}" t4="${5:-}"
    osascript - "${win_id}" "${t1}" "${t2}" "${t3}" "${t4}" << 'AS' 2>/dev/null || true
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
AS
}

resize_window() {
    local win_id="$1"
    local screen_bounds
    screen_bounds=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null || echo "0 25 1440 900")
    screen_bounds="${screen_bounds//,/ }"
    local sx sy sx2 sy2 sw sh ww wh wx wy wx2 wy2
    sx=$(echo  "${screen_bounds}" | awk '{print $1}')
    sy=$(echo  "${screen_bounds}" | awk '{print $2}')
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
    osascript << AS 2>/dev/null || true
tell application "iTerm2"
    set theWin to first window whose id is ${win_id}
    set bounds of theWin to {${wx}, ${wy}, ${wx2}, ${wy2}}
end tell
AS
    sleep 0.4
}

iterm_focus() {
    local win_id="$1"
    osascript << AS 2>/dev/null || true
tell application "iTerm2"
    activate
    set theWin to first window whose id is ${win_id}
    select theWin
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
        warn "No CGWindowID — falling back to full-screen capture"
        screencapture -x "${outfile}"
    fi
}

# ── state files ───────────────────────────────────────────────────────────────

TF1="/tmp/ccp_4p_t1_$$.txt"
TF2="/tmp/ccp_4p_t2_$$.txt"
TF3="/tmp/ccp_4p_t3_$$.txt"
TF4="/tmp/ccp_4p_t4_$$.txt"
SF1="/tmp/ccp_4p_s1_$$.txt"
SF2="/tmp/ccp_4p_s2_$$.txt"
SF3="/tmp/ccp_4p_s3_$$.txt"
SF4="/tmp/ccp_4p_s4_$$.txt"

WIN=""

cleanup() {
    rm -f "${TF1}" "${TF2}" "${TF3}" "${TF4}" \
          "${SF1}" "${SF2}" "${SF3}" "${SF4}"
    [[ -n "${WIN}" ]] && iterm_close "${WIN}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Initialise title files empty; scenario files with starting scenarios
printf '' > "${TF1}"; printf '' > "${TF2}"
printf '' > "${TF3}"; printf '' > "${TF4}"
printf 'editing'  > "${SF1}"
printf 'testing'  > "${SF2}"
printf 'building' > "${SF3}"
printf 'thinking' > "${SF4}"

# ── create window ─────────────────────────────────────────────────────────────

heading "Creating 4-pane iTerm2 window"

WIN=$(iterm_create_2x2)
info "Window ID: ${WIN}"
resize_window "${WIN}"

CG=$(get_cg_window_id) || CG=""
info "CGWindowID: ${CG:-none (full-screen fallback)}"
sleep 0.4

# ── launch fake TUIs ──────────────────────────────────────────────────────────

heading "Starting pane sessions"

INIT_SCENARIOS=(editing testing building thinking)
TITLE_FILES=("${TF1}" "${TF2}" "${TF3}" "${TF4}")
SCEN_FILES=("${SF1}"  "${SF2}"  "${SF3}"  "${SF4}")

for i in 0 1 2 3; do
    pane_n=$(( i + 1 ))
    scenario="${INIT_SCENARIOS[$i]}"
    tf="${TITLE_FILES[$i]}"
    sf="${SCEN_FILES[$i]}"
    info "Pane ${pane_n}: scenario=${scenario}"
    iterm_send "${WIN}" "${pane_n}" \
        "bash '${FAKE_TUI}' --scenario '${scenario}' --title-file '${tf}' --scenario-file '${sf}'"
    sleep 0.4
done

info "Waiting for TUIs to render (3s)..."
sleep 3

iterm_focus "${WIN}"
sleep 0.3

# ── capture frames ────────────────────────────────────────────────────────────

heading "Capturing frames"

declare -a FRAME_FILES=()
declare -a FRAME_DELAYS=()
frame_n=0

# Track current scenario per pane to detect changes
cur_s1="${INIT_SCENARIOS[0]}"
cur_s2="${INIT_SCENARIOS[1]}"
cur_s3="${INIT_SCENARIOS[2]}"
cur_s4="${INIT_SCENARIOS[3]}"

for entry in "${FRAMES[@]}"; do
    # ^ is the field separator — never appears in terminal title strings
    IFS='^' read -r delay t1 t2 t3 t4 s1 s2 s3 s4 <<< "${entry}"
    frame_n=$(( frame_n + 1 ))
    padded=$(printf "%03d" "${frame_n}")

    info "Frame ${padded} (${delay}cs)"
    info "  P1: [${s1}] ${t1}"
    info "  P2: [${s2}] ${t2}"
    info "  P3: [${s3}] ${t3}"
    info "  P4: [${s4}] ${t4}"

    # Write scenario files for any pane whose scenario changes.
    # fake_claude_tui.sh polls every 0.3s and re-renders in-place on change.
    scenario_changed=false
    if [[ "${s1}" != "${cur_s1}" ]]; then printf '%s' "${s1}" > "${SF1}"; cur_s1="${s1}"; scenario_changed=true; fi
    if [[ "${s2}" != "${cur_s2}" ]]; then printf '%s' "${s2}" > "${SF2}"; cur_s2="${s2}"; scenario_changed=true; fi
    if [[ "${s3}" != "${cur_s3}" ]]; then printf '%s' "${s3}" > "${SF3}"; cur_s3="${s3}"; scenario_changed=true; fi
    if [[ "${s4}" != "${cur_s4}" ]]; then printf '%s' "${s4}" > "${SF4}"; cur_s4="${s4}"; scenario_changed=true; fi

    # Write title files + set via AppleScript (belt + suspenders)
    printf '%s' "${t1}" > "${TF1}"
    printf '%s' "${t2}" > "${TF2}"
    printf '%s' "${t3}" > "${TF3}"
    printf '%s' "${t4}" > "${TF4}"
    iterm_set_pane_names "${WIN}" "${t1}" "${t2}" "${t3}" "${t4}"

    # Wait for iTerm2 to render. Extra time when content changed (re-render cycle).
    if $scenario_changed; then
        render_wait=1.4  # scenario poll (0.3s) + render + iTerm2 repaint
    else
        render_wait=0.8
    fi
    sleep "${render_wait}"

    outfile="${FRAMES_DIR}/frame_${padded}.png"
    capture_frame "${CG}" "${outfile}"
    FRAME_FILES+=("${outfile}")
    FRAME_DELAYS+=("${delay}")
    info "  Captured: ${outfile}"

    # Hold for remaining frame duration (already spent render_wait seconds above)
    hold_s=$(python3 -c "d=int('${delay}')/100; r=d-${render_wait}; print(max(r,0))")
    [[ "${hold_s}" != "0" ]] && sleep "${hold_s}"
done

info "Captured ${frame_n} frames"

# ── close window ──────────────────────────────────────────────────────────────

heading "Closing window"
iterm_close "${WIN}"
WIN=""
sleep 0.3

# ── assemble GIF ──────────────────────────────────────────────────────────────

heading "Assembling GIF"

OUT="${SHOTS_DIR}/demo-4pane.gif"
PALETTE="${FRAMES_DIR}/palette.png"

# Pre-process: trim shadow + resize in one pass per frame.
# 1440px wide — keeps title bar text sharp on retina 2x captures.
info "Pre-processing frames (trim + resize to 1440px)..."
declare -a PROCESSED=()
for i in "${!FRAME_FILES[@]}"; do
    padded=$(printf "%03d" "$(( i + 1 ))")
    processed="${FRAMES_DIR}/processed_${padded}.png"
    magick "${FRAME_FILES[$i]}" -trim +repage -resize '1440x>' "${processed}"
    PROCESSED+=("${processed}")
done

if command -v ffmpeg &>/dev/null; then
    # ── ffmpeg two-pass pipeline ──────────────────────────────────────────────
    #
    # palettegen stats_mode=full  — builds one palette across ALL frames
    #   together for consistent colors, no per-frame shift
    # paletteuse dither=sierra2_4a — best dithering for fine text and edges
    # diff_mode=rectangle — only encodes the changed region per frame; since
    #   each frame changes only 1-2 panes, per-frame storage is minimal
    # -gifflags +offsetting+transdiff — native GIF frame offset encoding

    info "Pass 1: generating global palette from all frames..."

    INPUT_ARGS=()
    CONCAT_IN=""
    for i in "${!PROCESSED[@]}"; do
        delay_s=$(python3 -c "print(${FRAME_DELAYS[$i]}/100)")
        INPUT_ARGS+=(-loop 1 -t "${delay_s}" -i "${PROCESSED[$i]}")
        CONCAT_IN+="[${i}:v]"
    done
    n=${#PROCESSED[@]}
    CONCAT_FILTER="${CONCAT_IN}concat=n=${n}:v=1:a=0[v]"

    ffmpeg -y "${INPUT_ARGS[@]}" \
        -filter_complex "${CONCAT_FILTER};[v]palettegen=stats_mode=full:max_colors=256[p]" \
        -map "[p]" "${PALETTE}" 2>/dev/null

    info "Pass 2: encoding GIF with sierra2_4a dithering + rectangle diff..."

    ffmpeg -y "${INPUT_ARGS[@]}" -i "${PALETTE}" \
        -filter_complex "${CONCAT_FILTER};[v][${n}:v]paletteuse=dither=sierra2_4a:diff_mode=rectangle[out]" \
        -map "[out]" \
        -loop 0 \
        -gifflags +offsetting+transdiff \
        "${OUT}" 2>/dev/null

else
    warn "ffmpeg not found — falling back to ImageMagick (brew install ffmpeg for best quality)"
    CMD=(magick -loop 0)
    for i in "${!PROCESSED[@]}"; do
        CMD+=(-delay "${FRAME_DELAYS[$i]}" "${PROCESSED[$i]}")
    done
    CMD+=(-dither Riemersma -colors 256 -layers Optimize "${OUT}")
    "${CMD[@]}"
fi

SIZE=$(du -sh "${OUT}" | awk '{print $1}')
info "GIF assembled: ${OUT} (${SIZE})"

# ── gifsicle final pass ───────────────────────────────────────────────────────
#
# --lossy=30: conservative — reduces ~25-35% more without blurring text.
# --optimize=3: maximum lossless LZW + frame coalescing.
if command -v gifsicle &>/dev/null; then
    info "Final pass: gifsicle --optimize=3 --lossy=30..."
    gifsicle --batch --optimize=3 --lossy=30 "${OUT}"
    SIZE=$(du -sh "${OUT}" | awk '{print $1}')
    info "Optimized: ${OUT} (${SIZE})"
else
    warn "gifsicle not found — skipping (brew install gifsicle)"
fi

# ── summary ───────────────────────────────────────────────────────────────────

heading "Done"
printf "  Output: ${BOLD}%s${NC}\n" "${OUT}"
printf "  Size:   %s\n\n" "${SIZE}"
printf "  To embed in README:\n"
printf "  ${DIM}![ccp 4-pane demo](docs/screenshots/demo-4pane.gif)${NC}\n\n"
printf "  To re-run:\n"
printf "  ${DIM}bash examples/gif-demo-4pane.sh${NC}\n\n"
