#!/usr/bin/env bash
# animate.sh — Simulates claude-pane-pulse title bar transitions
# Used by demo-animate.tape to generate hero-animated.gif

export TERM=xterm-256color

# ── Palette (Dracula) ─────────────────────────────────────────────────────────
R='\033[0m'
BG_TB='\033[48;2;40;41;58m'       # title bar background
FG_DIM='\033[38;2;98;114;164m'    # dim / separator
FG_CTX='\033[38;2;175;175;210m'   # context text in title
FG_SEP='\033[38;2;55;55;90m'      # · separator
FG_GREEN='\033[38;2;80;250;123m'
FG_CYAN='\033[38;2;139;233;253m'
FG_RED='\033[38;2;255;85;85m'
FG_ORANGE='\033[38;2;255;184;108m'
FG_PURPLE='\033[38;2;189;147;249m'
FG_WHITE='\033[38;2;248;248;242m'
FG_BODY='\033[38;2;200;200;220m'

PAD=70   # fill width for title bar

# Draw one "frame" of the animation
# Usage: frame CONTEXT STATUS STATUS_COLOR [CONTENT_LINES...]
frame() {
    local ctx="$1" status="$2" scolor="$3"
    shift 3

    # Clear + cursor home
    printf '\033[2J\033[H'

    # ── Title bar ──────────────────────────────────────────────────────────────
    printf "${BG_TB}${FG_DIM}  ● ● ●  ${FG_CTX}%s${FG_SEP}  ·  ${scolor}%s" "$ctx" "$status"
    # Pad remainder
    local used=$(( ${#ctx} + ${#status} + 13 ))
    printf "%*s${R}\n" $(( PAD - used < 0 ? 1 : PAD - used )) ""

    # ── Rule ───────────────────────────────────────────────────────────────────
    printf "${FG_DIM}─────────────────────────────────────────────────────────────────────────${R}\n"
    printf "\n"

    # ── Body lines ─────────────────────────────────────────────────────────────
    for line in "$@"; do
        printf "  %b\n" "$line"
    done
}

# ── Animation ─────────────────────────────────────────────────────────────────

CTX="PR #89 — Fix auth"

# 1. Idle
frame "$CTX" "💤 Idle" "${FG_DIM}"
sleep 1.2

# 2. Thinking
frame "$CTX" "💭 Thinking..." "${FG_CYAN}" \
    "${FG_CYAN}●${R} Reading src/auth/login.ts..." \
    "${FG_CYAN}●${R} Found the bug: missing null check on user object."
sleep 2

# 3. Building
frame "$CTX" "🔨 Building..." "${FG_ORANGE}" \
    "${FG_DIM}>${R} npm run build" \
    "" \
    "webpack 5.89.0 compiling..." \
    "${FG_DIM}  Hash: 7a8b9c0d1e2f3456${R}"
sleep 0.8
frame "$CTX" "🔨 Building..." "${FG_ORANGE}" \
    "${FG_DIM}>${R} npm run build" \
    "" \
    "webpack 5.89.0 compiled ${FG_GREEN}successfully${R} in 3421 ms" \
    "${FG_DIM}  Hash: 7a8b9c0d1e2f3456${R}"
sleep 1.5

# 4. Testing
frame "$CTX" "🧪 Testing..." "${FG_CYAN}" \
    "${FG_DIM}>${R} npm test" \
    "" \
    "${FG_DIM}> myrepo@1.0.0 test > jest${R}"
sleep 1
frame "$CTX" "🧪 Testing..." "${FG_CYAN}" \
    "${FG_DIM}>${R} npm test" \
    "" \
    "${FG_DIM}> myrepo@1.0.0 test > jest${R}" \
    "" \
    "${FG_GREEN} PASS${R}  src/auth/login.test.ts ${FG_DIM}(8.4s)${R}"
sleep 0.6
frame "$CTX" "🧪 Testing..." "${FG_CYAN}" \
    "${FG_DIM}>${R} npm test" \
    "" \
    "${FG_DIM}> myrepo@1.0.0 test > jest${R}" \
    "" \
    "${FG_GREEN} PASS${R}  src/auth/login.test.ts ${FG_DIM}(8.4s)${R}" \
    "${FG_GREEN} PASS${R}  src/auth/session.test.ts ${FG_DIM}(2.1s)${R}" \
    "${FG_GREEN} PASS${R}  src/auth/token.test.ts ${FG_DIM}(3.7s)${R}"
sleep 1

# 5. Tests passed ✅
frame "$CTX" "✅ Tests passed" "${FG_GREEN}" \
    "${FG_DIM}>${R} npm test" \
    "" \
    "${FG_GREEN} PASS${R}  src/auth/login.test.ts ${FG_DIM}(8.4s)${R}" \
    "${FG_GREEN} PASS${R}  src/auth/session.test.ts ${FG_DIM}(2.1s)${R}" \
    "${FG_GREEN} PASS${R}  src/auth/token.test.ts ${FG_DIM}(3.7s)${R}" \
    "" \
    "${FG_GREEN}✓${R} All tests passed ${FG_DIM}(16 suites, 47 tests)${R}"
sleep 2.5

# 6. Pushing
frame "$CTX" "⬆️  Pushing..." "${FG_ORANGE}" \
    "${FG_DIM}>${R} git push origin pr/89-fix-auth" \
    "" \
    "Counting objects: 15, done." \
    "Compressing objects: ${FG_GREEN}100%${R} (12/12), done." \
    "Writing objects: ${FG_GREEN}100%${R} (15/15), 2.43 KiB | 2.43 MiB/s, done."
sleep 2

# 7. Committed / done
frame "$CTX" "💾 Committed" "${FG_PURPLE}" \
    "${FG_DIM}>${R} git commit -m ${FG_ORANGE}\"fix: resolve auth null check\"${R}" \
    "" \
    "[pr/89 ${FG_ORANGE}a1b2c3d${R}] fix: resolve auth null check" \
    "${FG_DIM} 2 files changed, 8 insertions(+), 2 deletions(-)${R}" \
    "" \
    "${FG_GREEN}●${R} ${FG_CTX}PR ready for review. All checks passing.${R}"
sleep 3
