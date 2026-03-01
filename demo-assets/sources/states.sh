#!/usr/bin/env bash
# states.sh — sourced by VHS tape; each function draws one animation frame

HR='\033[38;2;55;57;84m────────────────────────────────────────────────────────────────────────────\033[0m'

tb() {
    # tb <context> <status_color_code> <status_text>
    local ctx="$1" col="$2" status="$3"
    printf '\033[48;2;38;39;56m\033[38;2;95;97;130m  ● ● ●  '
    printf '\033[38;2;172;172;205m%s' "$ctx"
    printf '\033[38;2;52;52;84m  ·  '
    printf '\033[%sm%s\033[0m\n' "$col" "$status"
    printf "%b\n\n" "$HR"
}

state_idle() {
    tb "PR #89 — Fix auth" "38;2;98;114;164" "💤 Idle"
}

state_thinking() {
    tb "PR #89 — Fix auth" "38;2;139;233;253" "💭 Thinking..."
    printf '  \033[38;2;139;233;253m>\033[0m Reading src/auth/login.ts...\n'
    printf '  \033[38;2;139;233;253m>\033[0m Found bug: missing null check on user object.\n'
}

state_building() {
    tb "PR #89 — Fix auth" "38;2;255;184;108" "🔨 Building..."
    printf '  \033[38;2;88;100;122m>\033[0m npm run build\n\n'
    printf '  webpack 5.89.0 compiled \033[38;2;80;250;123msuccessfully\033[0m in 3421 ms\n'
}

state_testing() {
    tb "PR #89 — Fix auth" "38;2;139;233;253" "🧪 Testing..."
    printf '  \033[38;2;88;100;122m>\033[0m npm test\n\n'
}

state_tests_appearing() {
    tb "PR #89 — Fix auth" "38;2;139;233;253" "🧪 Testing..."
    printf '  \033[38;2;88;100;122m>\033[0m npm test\n\n'
    printf '  \033[38;2;80;250;123mPASS\033[0m  src/auth/login.test.ts \033[38;2;88;100;122m(8.4s)\033[0m\n'
}

state_tests_more() {
    tb "PR #89 — Fix auth" "38;2;139;233;253" "🧪 Testing..."
    printf '  \033[38;2;88;100;122m>\033[0m npm test\n\n'
    printf '  \033[38;2;80;250;123mPASS\033[0m  src/auth/login.test.ts \033[38;2;88;100;122m(8.4s)\033[0m\n'
    printf '  \033[38;2;80;250;123mPASS\033[0m  src/auth/session.test.ts \033[38;2;88;100;122m(2.1s)\033[0m\n'
    printf '  \033[38;2;80;250;123mPASS\033[0m  src/auth/token.test.ts \033[38;2;88;100;122m(3.7s)\033[0m\n'
}

state_passed() {
    tb "PR #89 — Fix auth" "38;2;80;250;123" "✅ Tests passed"
    printf '  \033[38;2;80;250;123mPASS\033[0m  src/auth/login.test.ts \033[38;2;88;100;122m(8.4s)\033[0m\n'
    printf '  \033[38;2;80;250;123mPASS\033[0m  src/auth/session.test.ts \033[38;2;88;100;122m(2.1s)\033[0m\n'
    printf '  \033[38;2;80;250;123mPASS\033[0m  src/auth/token.test.ts \033[38;2;88;100;122m(3.7s)\033[0m\n\n'
    printf '  \033[38;2;80;250;123m✓\033[0m All tests passed \033[38;2;88;100;122m(16 suites, 47 tests)\033[0m\n'
}

state_pushing() {
    tb "PR #89 — Fix auth" "38;2;255;184;108" "⬆️  Pushing..."
    printf '  \033[38;2;88;100;122m>\033[0m git push origin pr/89-fix-auth\n'
    printf '  Writing objects: \033[38;2;80;250;123m100%%\033[0m (15/15), 2.43 KiB, done.\n'
}

state_committed() {
    tb "PR #89 — Fix auth" "38;2;189;147;249" "💾 Committed"
    printf '  \033[38;2;88;100;122m>\033[0m git commit -m \033[38;2;255;184;108m"fix: resolve auth null check"\033[0m\n\n'
    printf '  [pr/89 \033[38;2;255;184;108ma1b2c3d\033[0m] fix: resolve auth null check\n'
    printf '  \033[38;2;88;100;122m 2 files changed, 8 insertions(+), 2 deletions(-)\033[0m\n\n'
    printf '  \033[38;2;80;250;123m●\033[0m \033[38;2;172;172;205mPR ready for review. All checks passing.\033[0m\n'
}
