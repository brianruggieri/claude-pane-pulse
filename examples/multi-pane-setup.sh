#!/usr/bin/env bash
# examples/multi-pane-setup.sh - Launch multiple ccp sessions
#
# This script sets up a typical multi-agent Claude Code workspace.
# Choose your terminal: iTerm2 or tmux.
#
# Usage:
#   bash examples/multi-pane-setup.sh --iterm2   # iTerm2 split panes
#   bash examples/multi-pane-setup.sh --tmux     # tmux split windows
#   bash examples/multi-pane-setup.sh --print    # just print the commands

set -euo pipefail

MODE="${1:---print}"

# ── Session definitions ───────────────────────────────────────────────────────
# Edit these to match your actual work

declare -a SESSIONS=(
    "ccp --pr 89 'Fix authentication bug'"
    "ccp --issue 12 'Refactor API layer'"
    "ccp --feature 'OAuth integration'"
    "ccp --bug 'Login crash on iOS'"
)

declare -a DIRS=(
    "~/projects/my-app"
    "~/projects/my-app"
    "~/projects/my-app"
    "~/projects/my-app"
)

# ── Print mode ────────────────────────────────────────────────────────────────

if [[ "${MODE}" == "--print" ]]; then
    echo ""
    echo "Commands to run in separate terminal panes:"
    echo ""
    for i in "${!SESSIONS[@]}"; do
        echo "  Pane $((i + 1)): cd ${DIRS[$i]} && ${SESSIONS[$i]}"
    done
    echo ""
    echo "Run with --iterm2 or --tmux to launch automatically."
    echo ""
    exit 0
fi

# ── tmux mode ─────────────────────────────────────────────────────────────────

if [[ "${MODE}" == "--tmux" ]]; then
    if ! command -v tmux &> /dev/null; then
        echo "tmux is not installed. Install with: brew install tmux" >&2
        exit 1
    fi

    SESSION_NAME="claude-work"

    # Kill existing session if it exists
    tmux kill-session -t "${SESSION_NAME}" 2>/dev/null || true

    # Create new session with first pane
    tmux new-session -d -s "${SESSION_NAME}" -n "pane-1" \
        "cd ${DIRS[0]} && ${SESSIONS[0]}"

    # Add remaining panes as windows
    for i in 1 2 3; do
        if [[ "${i}" -lt "${#SESSIONS[@]}" ]]; then
            tmux new-window -t "${SESSION_NAME}" -n "pane-$((i + 1))" \
                "cd ${DIRS[$i]} && ${SESSIONS[$i]}"
        fi
    done

    # Attach to the session
    tmux select-window -t "${SESSION_NAME}:1"
    tmux attach-session -t "${SESSION_NAME}"
    exit 0
fi

# ── iTerm2 mode ───────────────────────────────────────────────────────────────

if [[ "${MODE}" == "--iterm2" ]]; then
    # Build the AppleScript to open splits
    # This creates a 2x2 grid: two vertical panes, each split horizontally

    PANE1="${SESSIONS[0]}"
    PANE2="${SESSIONS[1]:-}"
    PANE3="${SESSIONS[2]:-}"
    PANE4="${SESSIONS[3]:-}"

    osascript <<APPLESCRIPT
tell application "iTerm2"
    tell current window
        -- Pane 1 (top-left): already exists
        tell current session
            write text "cd ${DIRS[0]} && ${PANE1}"
        end tell

        -- Split vertical → Pane 2 (top-right)
$(if [[ -n "${PANE2}" ]]; then
echo "        set pane2 to (split vertically with default profile)"
echo "        tell pane2"
echo "            write text \"cd ${DIRS[1]} && ${PANE2}\""
echo "        end tell"
fi)

        -- Split Pane 1 horizontal → Pane 3 (bottom-left)
$(if [[ -n "${PANE3}" ]]; then
echo "        tell first session of current tab"
echo "            set pane3 to (split horizontally with default profile)"
echo "            tell pane3"
echo "                write text \"cd ${DIRS[2]} && ${PANE3}\""
echo "            end tell"
echo "        end tell"
fi)

        -- Split Pane 2 horizontal → Pane 4 (bottom-right)
$(if [[ -n "${PANE4}" ]]; then
echo "        tell second session of current tab"
echo "            set pane4 to (split horizontally with default profile)"
echo "            tell pane4"
echo "                write text \"cd ${DIRS[3]} && ${PANE4}\""
echo "            end tell"
echo "        end tell"
fi)
    end tell
end tell
APPLESCRIPT

    exit 0
fi

echo "Unknown mode: ${MODE}"
echo "Usage: $0 [--print | --tmux | --iterm2]"
exit 1
