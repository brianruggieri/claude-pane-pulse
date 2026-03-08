#!/usr/bin/env bash
# examples/fake_claude_tui.sh
#
# Renders a realistic ANSI-accurate Claude Code TUI snapshot in the terminal.
# Used for README screenshots — shows a frozen mid-session state for each of
# four common scenarios.
#
# Usage:
#   bash examples/fake_claude_tui.sh --scenario editing
#   bash examples/fake_claude_tui.sh --scenario testing  --title-mode before
#   bash examples/fake_claude_tui.sh --scenario building --title-mode after
#   bash examples/fake_claude_tui.sh --scenario thinking
#
# Scenarios:
#   editing   auth-service  feat/oauth2          ✏️  editing a TS file
#   testing   dashboard-ui  fix/layout-shift     🧪  running jest
#   building  data-pipeline feat/embeddings      🔨  running tsc
#   thinking  infra-tools   chore/terraform-up   💭  mid-response stream
#
# --title-mode before   pane title = "PROJECTNAME — claude" (no status)
# --title-mode after    pane title = "PROJECT (BRANCH) | TASK | STATUS"
#                       (default)
#
# Holds the terminal open after rendering (sleep loop) until SIGTERM or Ctrl-C.

# ── args ──────────────────────────────────────────────────────────────────────

SCENARIO="editing"
TITLE_MODE="after"
TITLE_FILE=""
SCENARIO_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scenario)      SCENARIO="$2";      shift 2 ;;
        --title-mode)    TITLE_MODE="$2";    shift 2 ;;
        --title-file)    TITLE_FILE="$2";    shift 2 ;;
        --scenario-file) SCENARIO_FILE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# ── colors ────────────────────────────────────────────────────────────────────

R=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[31m'
GRN=$'\033[32m'
YEL=$'\033[33m'
BLU=$'\033[34m'
CYN=$'\033[36m'
WHT=$'\033[97m'

# Claude's characteristic amber bullet / spinner color
AMB=$'\033[38;2;215;115;55m'

# Softer green / red for diffs (less saturated, easier on eyes in screenshots)
DGRN=$'\033[38;2;80;195;110m'
DRED=$'\033[38;2;210;80;80m'

BULLET="${AMB}●${R}"
SPIN="${AMB}✳${R}"

# ── helpers ───────────────────────────────────────────────────────────────────

set_title() {
    # OSC 1 = per-pane title (iTerm2 split panes)
    # OSC 2 = window title (cleared so we don't pollute the app-level bar)
    printf '\033]1;%s\007' "$1"
    printf '\033]2;\007'
}

# Print a dim horizontal rule that fills the terminal width
hrule() {
    local w
    w=$(tput cols 2>/dev/null || echo "100")
    printf '%s' "${DIM}"
    printf '─%.0s' $(seq 1 "${w}")
    printf '%s\n' "${R}"
}

# Print a dim section divider with optional label (for diff headers)
diff_rule() {
    local label="${1:-}"
    local w
    w=$(tput cols 2>/dev/null || echo "100")
    if [[ -n "${label}" ]]; then
        local pad=$(( (w - ${#label} - 4) / 2 ))
        [[ ${pad} -lt 2 ]] && pad=2
        printf '%s' "${DIM}"
        printf '─%.0s' $(seq 1 "${pad}")
        printf ' %s ' "${label}"
        printf '─%.0s' $(seq 1 "$(( w - pad - ${#label} - 4 ))")
        printf '%s\n' "${R}"
    else
        printf '%s' "${DIM}"
        printf '─%.0s' $(seq 1 "${w}")
        printf '%s\n' "${R}"
    fi
}

blank() { echo ""; }

# ── scenario data ─────────────────────────────────────────────────────────────

case "${SCENARIO}" in
    editing)
        PROJECT="auth-service"
        BRANCH="feat/oauth2"
        TASK="Fix JWT expiry check"
        STATUS_LABEL="✏️ Editing"
        ;;
    testing)
        PROJECT="dashboard-ui"
        BRANCH="fix/layout-shift"
        TASK="Audit component tests"
        STATUS_LABEL="🧪 Testing"
        ;;
    building)
        PROJECT="data-pipeline"
        BRANCH="feat/embeddings"
        TASK="Fix TypeScript errors"
        STATUS_LABEL="🔨 Building"
        ;;
    thinking)
        PROJECT="infra-tools"
        BRANCH="chore/terraform-up"
        TASK="Plan Terraform upgrade"
        STATUS_LABEL="📖 Reading"
        ;;
    complete)
        PROJECT="auth-service"
        BRANCH="feat/oauth2"
        TASK="Fix JWT expiry check"
        STATUS_LABEL="✅ Tests passed"
        ;;
    committed)
        PROJECT="auth-service"
        BRANCH="feat/oauth2"
        TASK="Fix JWT expiry"
        STATUS_LABEL="💾 Committed"
        ;;
    pushing)
        PROJECT="infra-tools"
        BRANCH="chore/tf-up"
        TASK="Plan Terraform"
        STATUS_LABEL="⬆️ Pushing"
        ;;
    *)
        echo "Unknown scenario: ${SCENARIO}" >&2
        echo "Valid: editing testing building thinking complete committed pushing" >&2
        exit 1
        ;;
esac

# ── pane title ────────────────────────────────────────────────────────────────

if [[ "${TITLE_MODE}" == "before" ]]; then
    set_title "${PROJECT} — claude"
else
    set_title "${PROJECT} (${BRANCH}) | ${TASK} | ${STATUS_LABEL}"
fi

# ── render scenario ───────────────────────────────────────────────────────────

tput clear 2>/dev/null || printf '\033[2J\033[H'
tput civis 2>/dev/null || true   # hide cursor for cleaner screenshot

render_editing() {
    blank
    printf "  ${DIM}❯ show me the recent git log, then fix the issue${R}\n"
    blank
    printf "  ${DIM}${BULLET} Bash(git log --oneline -5)${R}\n"
    printf "  ${DIM}  3f9a1c2 feat: add OAuth2 PKCE flow${R}\n"
    printf "  ${DIM}  a04e7d8 fix: handle token refresh race condition${R}\n"
    printf "  ${DIM}  bb1c34f chore: upgrade passport to 0.7.0${R}\n"
    blank
    printf "  ${BOLD}❯ fix the JWT expiry validation in the auth middleware${R}\n"
    blank
    printf "  ${BULLET} Read(src/auth/middleware.ts) · 287 lines\n"
    blank
    printf "  Found the issue. ${BOLD}validateToken${R} verifies the JWT signature\n"
    printf "  but never checks the ${CYN}exp${R} claim — tokens stay valid forever\n"
    printf "  after they should have expired. Fixing this now.\n"
    blank
    printf "  ${BULLET} ${BOLD}Edit(src/auth/middleware.ts)${R}\n"
    diff_rule "src/auth/middleware.ts · lines 44–53"
    printf "  ${DIM}  43${R}   }\n"
    printf "  ${DIM}  44${R}   function validateToken(token: string): TokenPayload {\n"
    printf "  ${DRED}  45 -   const payload = jwt.verify(token, SECRET);${R}\n"
    printf "  ${DRED}  46 -   return { valid: true };${R}\n"
    printf "  ${DGRN}  45 +   const decoded = jwt.verify(token, SECRET) as JWTPayload;${R}\n"
    printf "  ${DGRN}  46 +   if (decoded.exp < Math.floor(Date.now() / 1000)) {${R}\n"
    printf "  ${DGRN}  47 +     throw new TokenExpiredError('token expired');${R}\n"
    printf "  ${DGRN}  48 +   }${R}\n"
    printf "  ${DGRN}  49 +   return { valid: true, sub: decoded.sub };${R}\n"
    printf "  ${DIM}  50${R}   }\n"
    diff_rule
    blank
    printf "  ${SPIN} Writing changes…\n"
    blank
    printf "  ${DIM}❯${R} \n"
}

render_testing() {
    blank
    printf "  ${DIM}❯ check test coverage on the sidebar component${R}\n"
    blank
    printf "  ${DIM}${BULLET} Bash(npx jest --coverage Sidebar --no-ci)${R}\n"
    printf "  ${DIM}  Coverage: 94.2%% (3 uncovered branches)${R}\n"
    blank
    printf "  ${BOLD}❯ run the layout tests and fix any failures${R}\n"
    blank
    printf "  ${BULLET} ${BOLD}Bash(npm test -- --testPathPattern=layout)${R}\n"
    blank
    printf "  ${DIM}  > dashboard-ui@2.4.1 test${R}\n"
    printf "  ${DIM}  > jest --testPathPattern=layout --no-coverage${R}\n"
    blank
    printf "  ${DIM}  PASS  src/components/__tests__/Header.test.tsx${R}\n"
    printf "  ${DIM}  PASS  src/components/__tests__/Sidebar.test.tsx${R}\n"
    printf "  ${DRED}  FAIL  src/components/__tests__/Grid.test.tsx${R}\n"
    blank
    printf "  ${DRED}  ● Grid › should apply responsive breakpoints${R}\n"
    blank
    printf "    Expected element to have class ${DGRN}\"grid-cols-3\"${R}\n"
    printf "    Received: ${DRED}\"grid-cols-2\"${R}\n"
    blank
    printf "  The breakpoint logic uses ${CYN}tailwind.config.js${R} screen sizes but\n"
    printf "  the test fixture doesn't set a viewport. Adding a ${BOLD}jsdom${R} resize.\n"
    blank
    printf "  ${SPIN} Running tests…\n"
    blank
    printf "  ${DIM}❯${R} \n"
}

render_building() {
    blank
    printf "  ${DIM}❯ how many strict-mode errors are there?${R}\n"
    blank
    printf "  ${DIM}${BULLET} Bash(tsc --strict --noEmit 2>&1 | wc -l)${R}\n"
    printf "  ${DIM}  47${R}\n"
    blank
    printf "  ${BOLD}❯ fix all TypeScript strict mode errors in the pipeline${R}\n"
    blank
    printf "  ${BULLET} ${BOLD}Bash(tsc --strict --noEmit)${R}\n"
    blank
    printf "  ${DRED}  src/pipeline/embeddings.ts(47,12): error TS2322${R}\n"
    printf "    ${DIM}Type 'string | undefined' is not assignable to 'string'.${R}\n"
    blank
    printf "  ${DRED}  src/pipeline/transform.ts(93,8): error TS7006${R}\n"
    printf "    ${DIM}Parameter 'doc' implicitly has an 'any' type.${R}\n"
    blank
    printf "  I'll fix these one by one. Starting with the undefined assignment\n"
    printf "  in ${CYN}embeddings.ts${R} — the model config key needs a fallback.\n"
    blank
    printf "  ${BULLET} Edit(src/pipeline/embeddings.ts)\n"
    diff_rule "src/pipeline/embeddings.ts · lines 45–50"
    printf "  ${DRED}  47 -   const model = config.model;${R}\n"
    printf "  ${DGRN}  47 +   const model = config.model ?? 'text-embedding-3-small';${R}\n"
    diff_rule
    blank
    printf "  ${SPIN} Compiling…\n"
    blank
    printf "  ${DIM}❯${R} \n"
}

render_thinking() {
    blank
    printf "  ${DIM}❯ what changed in provider 4.x that we need to handle?${R}\n"
    blank
    printf "  ${DIM}${BULLET} Read(CHANGELOG.md) · 823 lines${R}\n"
    printf "  ${DIM}  The S3 resource split was the biggest 4.x change.${R}\n"
    blank
    printf "  ${BOLD}❯ plan the full Terraform AWS provider upgrade from 4.x to 5.x${R}\n"
    blank
    printf "  ${BULLET} Read(terraform/providers.tf) · 42 lines\n"
    printf "  ${BULLET} Read(terraform/main.tf) · 156 lines\n"
    printf "  ${BULLET} Read(terraform/modules/vpc/main.tf) · 89 lines\n"
    blank
    printf "  I'm reviewing the AWS provider 5.x migration guide alongside\n"
    printf "  your current configs. Here are the breaking changes that affect\n"
    printf "  this codebase:\n"
    blank
    printf "  ${BOLD}1. aws_s3_bucket split${R} — the monolithic resource is now\n"
    printf "     split into ${CYN}aws_s3_bucket_acl${R}, ${CYN}aws_s3_bucket_versioning${R},\n"
    printf "     and ${CYN}aws_s3_bucket_server_side_encryption_configuration${R}.\n"
    printf "     You have 4 S3 buckets in ${CYN}main.tf${R} that need updating.\n"
    blank
    printf "  ${BOLD}2. aws_instance default_tags${R} — tag inheritance behavior\n"
    printf "     changed. Your ${CYN}modules/vpc/main.tf${R} relies on implicit…\n"
    blank
    printf "  ${SPIN} Reading…\n"
    blank
    printf "  ${DIM}❯${R} \n"
}

render_complete() {
    blank
    printf "  ${DIM}❯ run the full auth test suite${R}\n"
    blank
    printf "  ${BULLET} ${BOLD}Bash(npm test -- --testPathPattern=auth)${R}\n"
    blank
    printf "  ${DIM}  > auth-service@3.1.0 test${R}\n"
    printf "  ${DIM}  > jest --testPathPattern=auth${R}\n"
    blank
    printf "  ${DGRN}  PASS  src/auth/__tests__/middleware.test.ts${R}\n"
    printf "  ${DGRN}  PASS  src/auth/__tests__/jwt.test.ts${R}\n"
    printf "  ${DGRN}  PASS  src/auth/__tests__/refresh.test.ts${R}\n"
    blank
    printf "  ${DGRN}  Test Suites: 3 passed, 3 total${R}\n"
    printf "  ${DGRN}  Tests:       18 passed, 18 total${R}\n"
    printf "  ${DIM}  Time:        1.843s${R}\n"
    blank
    printf "  All auth tests pass. The ${CYN}exp${R} claim fix is working correctly —\n"
    printf "  expired tokens are now rejected as expected.\n"
    blank
    printf "  ${DIM}❯${R} \n"
}

render_committed() {
    blank
    printf "  ${DIM}❯ commit the fix${R}\n"
    blank
    printf "  ${DGRN}  PASS  src/auth/__tests__/middleware.test.ts${R}\n"
    printf "  ${DGRN}  PASS  src/auth/__tests__/jwt.test.ts${R}\n"
    printf "  ${DGRN}  Tests: 18 passed, 18 total${R}\n"
    blank
    printf "  ${BULLET} ${BOLD}Bash(git add -A && git commit -m 'fix: validate JWT exp claim in middleware')${R}\n"
    blank
    printf "  ${DIM}  [feat/oauth2 3f9a1c2] fix: validate JWT exp claim in middleware${R}\n"
    printf "  ${DIM}   1 file changed, 8 insertions(+), 2 deletions(-)${R}\n"
    blank
    printf "  Committed as ${CYN}3f9a1c2${R}. Ready to push.\n"
    blank
    printf "  ${DIM}❯${R} \n"
}

render_pushing() {
    blank
    printf "  ${DIM}❯ push the branch and open a PR${R}\n"
    blank
    printf "  ${BULLET} Edit(terraform/main.tf)\n"
    diff_rule "terraform/main.tf · aws_s3_bucket split"
    printf "  ${DRED}  47 -   resource \"aws_s3_bucket\" \"logs\" {${R}\n"
    printf "  ${DGRN}  47 +   resource \"aws_s3_bucket\" \"logs\" {}${R}\n"
    printf "  ${DGRN}  48 +   resource \"aws_s3_bucket_versioning\" \"logs\" {${R}\n"
    printf "  ${DGRN}  49 +     bucket = aws_s3_bucket.logs.id${R}\n"
    diff_rule
    blank
    printf "  ${BULLET} ${BOLD}Bash(git push origin chore/tf-up)${R}\n"
    blank
    printf "  ${DIM}  Enumerating objects: 7, done.${R}\n"
    printf "  ${DIM}  Counting objects: 100%% (7/7), done.${R}\n"
    printf "  ${DIM}  Writing objects: 100%% (4/4), 1.21 KiB | 1.21 MiB/s, done.${R}\n"
    printf "  ${DIM}  To github.com:acme/infra-tools.git${R}\n"
    printf "  ${DGRN}   * [new branch]  chore/tf-up -> chore/tf-up${R}\n"
    blank
    printf "  ${SPIN} Pushing…\n"
    blank
    printf "  ${DIM}❯${R} \n"
}

_render_scenario() {
    tput clear 2>/dev/null || printf '\033[2J\033[H'
    tput civis 2>/dev/null || true
    case "$1" in
        editing)   render_editing   ;;
        testing)   render_testing   ;;
        building)  render_building  ;;
        thinking)  render_thinking  ;;
        complete)  render_complete  ;;
        committed) render_committed ;;
        pushing)   render_pushing   ;;
    esac
}

_render_scenario "${SCENARIO}"

# ── hold for screenshot ────────────────────────────────────────────────────────

# Build the full title string once for use in the refresh loop
if [[ "${TITLE_MODE}" == "before" ]]; then
    _pane_title="${PROJECT} — claude"
else
    _pane_title="${PROJECT} (${BRANCH}) | ${TASK} | ${STATUS_LABEL}"
fi

# Re-show cursor on exit
trap 'tput cnorm 2>/dev/null || true' EXIT INT TERM

# Suppress zsh/oh-my-zsh auto-title so it doesn't overwrite our OSC title
export DISABLE_AUTO_TITLE=true

# Dynamic mode: orchestrator drives titles via TITLE_FILE and/or content via
# SCENARIO_FILE. Both files are polled every 0.3s. When SCENARIO_FILE changes,
# the screen is cleared and the new scenario is rendered in-place — no process
# restart, no shell prompt flash. Used by gif-demo-4pane.sh.
if [[ -n "${TITLE_FILE}" || -n "${SCENARIO_FILE}" ]]; then
    _last_scenario="${SCENARIO}"
    while true; do
        if [[ -n "${TITLE_FILE}" ]]; then
            _t="$(cat "${TITLE_FILE}" 2>/dev/null || true)"
            [[ -n "${_t}" ]] && set_title "${_t}"
        fi
        if [[ -n "${SCENARIO_FILE}" ]]; then
            _new_s="$(cat "${SCENARIO_FILE}" 2>/dev/null || true)"
            if [[ -n "${_new_s}" && "${_new_s}" != "${_last_scenario}" ]]; then
                _last_scenario="${_new_s}"
                _render_scenario "${_new_s}"
            fi
        fi
        if [[ -t 0 ]]; then
            read -r -t 0.3 2>/dev/null || true
        else
            sleep 0.3
        fi
    done
else
    # Static mode: refresh the fixed title every ~2s.
    while true; do
        set_title "${_pane_title}"
        if [[ -t 0 ]]; then
            read -r -t 2 2>/dev/null || true
        else
            sleep 2
        fi
    done
fi
