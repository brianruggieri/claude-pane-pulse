#!/usr/bin/env bash
# lib/monitor.sh - Dynamic title monitoring with status priorities
# Prevent double-sourcing
[[ -n "${_CCP_MONITOR_SOURCED:-}" ]] && return
_CCP_MONITOR_SOURCED=1

# Source dependencies (safe: guarded against double-source)
_MONITOR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core.sh
source "${_MONITOR_SCRIPT_DIR}/core.sh"
# shellcheck source=lib/title.sh
source "${_MONITOR_SCRIPT_DIR}/title.sh"

# ── Status priority levels ────────────────────────────────────────────────────
# 🐛 Error          = 100
# ❌ Tests failed   = 90
# ⏸️ Awaiting approval = 88
# 🙋 Input needed   = 85
# 🔨 Building       = 80
# 🧪 Testing        = 80
# 📦 Installing     = 80
# ⬆️ Pushing        = 75
# ⬇️ Pulling        = 75
# 🔀 Merging        = 75
# 🐳 Docker         = 70
# 💭 Thinking       = 70  (structural: any ● line with trailing …)
# ✏️ Editing        = 65
# ✅ Tests passed   = 60
# 💾 Committed      = 60
# 🏁 Completed      = 60
# 🖥️ Running        = 55  (catch-all for unrecognised ● Bash() lines)
# 💤 Idle           = 10

# ── status_to_priority ────────────────────────────────────────────────────────
# Map a status string (as written by hook_runner.sh) to a priority integer.
status_to_priority() {
    local status="$1"
    if [[ "${status}" =~ "🐛 Error" ]]; then
        echo 100
    elif [[ "${status}" =~ "❌ Tests failed" ]]; then
        echo 90
    elif [[ "${status}" =~ "⏸️ Awaiting approval" ]]; then
        echo 88
    elif [[ "${status}" =~ "🙋 Input needed" ]]; then
        echo 85
    elif [[ "${status}" =~ (Building|Testing|Installing) ]]; then
        echo 80
    elif [[ "${status}" =~ (Pushing|Pulling|Merging) ]]; then
        echo 75
    elif [[ "${status}" =~ (Docker|Thinking|Delegating) ]]; then
        echo 70
    elif [[ "${status}" =~ "✏️ Editing" ]]; then
        echo 65
    elif [[ "${status}" =~ (Tests\ passed|Committed|Completed|Subagent\ finished) ]]; then
        echo 60
    elif [[ "${status}" =~ (Session\ started|Compacting|Subagent\ started|Teammate\ idle|Config\ changed|Worktree|Notification|Session\ ended) ]]; then
        echo 52
    elif [[ "${status}" =~ (Reading|Browsing|Running) ]]; then
        echo 55
    else
        echo 50
    fi
}

# ── extract_context ───────────────────────────────────────────────────────────
# Legacy: retained for test compatibility. Not called in production.
# Parse a stripped line of output and return "status|priority".
# Empty status means no match — caller keeps the previous context.
#
# Pattern philosophy:
#   • Error/failure patterns anchor to word boundaries to avoid false positives.
#   • Build/test/install patterns match both raw command output AND Claude Code's
#     "● Bash(command...)" tool-call headers, so they fire the moment Claude
#     decides to run a command rather than only after the command prints output.
#   • Thinking is detected structurally: any "● <word>..." line means Claude is
#     processing, regardless of the specific phrase Claude uses ("Dilly-dallying",
#     "Thinking", "Pondering", or any future variant).
#   • File-editing is detected from "● Edit(" / "● Write(" tool-call headers.
#   • A generic "● Bash(" catch-all covers any shell command not matched above.
extract_context() {
    local line="$1"
    local context=""
    local priority=0

    # ── Error states (highest priority) ──────────────────────────────────────
    # Anchor to line start / word boundaries to reduce false positives on
    # build output that legitimately prints error messages mid-stream.
    if [[ "${line}" =~ ^(Error|error):[[:space:]] || \
          "${line}" =~ ^(Exception|Traceback) || \
          "${line}" =~ ^FAILED || \
          "${line}" =~ [[:space:]]FAILED ]]; then
        context="🐛 Error"
        priority=100

    # ── Test failures ─────────────────────────────────────────────────────────
    elif [[ "${line}" =~ [0-9]+[[:space:]]+(tests?|specs?)[[:space:]]+(failed|failing) ]]; then
        context="❌ Tests failed"
        priority=90

    # ── Active builds ─────────────────────────────────────────────────────────
    # Matches: raw output keywords OR ● Bash( lines containing build commands.
    elif [[ "${line}" =~ (Building|Compiling|Bundling) || \
            "${line}" =~ ●[[:space:]]*Bash\(.*(build|compile|bundle|webpack|rollup|esbuild|tsc[[:space:]]|vite[[:space:]]build|cargo[[:space:]]build|make[[:space:]]|cmake|gradle|mvn[[:space:]]package) ]]; then
        context="🔨 Building"
        priority=80

    # ── Active tests ──────────────────────────────────────────────────────────
    elif [[ "${line}" =~ (npm|yarn|pnpm)[[:space:]].*test || \
            "${line}" =~ ●[[:space:]]*Bash\(.*(jest|vitest|pytest|mocha|rspec|go[[:space:]]test|cargo[[:space:]]test|phpunit|bun[[:space:]]test) ]]; then
        context="🧪 Testing"
        priority=80

    # ── Package installs ──────────────────────────────────────────────────────
    elif [[ "${line}" =~ (npm|yarn)[[:space:]]+(install|add|ci) || \
            "${line}" =~ ●[[:space:]]*Bash\(.*(npm|yarn|pnpm|bun)[[:space:]]+(install|add|ci|i[[:space:]]) || \
            "${line}" =~ ●[[:space:]]*Bash\(pip[[:space:]]+(install|download) || \
            "${line}" =~ ●[[:space:]]*Bash\(cargo[[:space:]]add ]]; then
        context="📦 Installing"
        priority=80

    # ── Git: push / pull / merge ──────────────────────────────────────────────
    # These match both raw "git push" output AND "● Bash(git push ...)" headers.
    elif [[ "${line}" =~ git[[:space:]]+push ]]; then
        context="⬆️ Pushing"
        priority=75
    elif [[ "${line}" =~ git[[:space:]]+pull ]]; then
        context="⬇️ Pulling"
        priority=75
    elif [[ "${line}" =~ git[[:space:]]+merge ]]; then
        context="🔀 Merging"
        priority=75

    # ── Docker ────────────────────────────────────────────────────────────────
    elif [[ "${line}" =~ docker[[:space:]]+(build|run|push|compose) ]]; then
        context="🐳 Docker"
        priority=70

    # ── File editing ──────────────────────────────────────────────────────────
    elif [[ "${line}" =~ ●[[:space:]]*(Edit|Write|MultiEdit|NotebookEdit)\( ]]; then
        context="✏️ Editing"
        priority=65

    # ── Test success ──────────────────────────────────────────────────────────
    elif [[ "${line}" =~ [0-9]+[[:space:]]+(tests?|specs?)[[:space:]]+passed ]]; then
        context="✅ Tests passed"
        priority=60

    # ── Git commit completion ─────────────────────────────────────────────────
    elif [[ "${line}" =~ git[[:space:]]+commit ]]; then
        context="💾 Committed"
        priority=60

    # ── Generic shell command (catch-all for unrecognised ● Bash lines) ───────
    elif [[ "${line}" =~ ●[[:space:]]*Bash\( ]]; then
        context="🖥️ Running"
        priority=55

    fi

    echo "${context}|${priority}"
}

title_updater() {
    local base_title="$1"

    (
        # keep the updater alive on non-zero checks/sleeps
        set +e

        local current_context=""
        local task_summary=""
        local clean_summary=""
        local prev_display_context=""
        local last_hook_check=$SECONDS
        local status_file="${CCP_STATUS_FILE:-}"
        local context_file="${CCP_CONTEXT_FILE:-}"

        local title_prefix
        title_prefix=$(format_title_prefix "${CCP_PROJECT_NAME:-}" "${CCP_BRANCH_NAME:-}")

        # Assert base title once before Claude Code starts.
        update_title_with_context "${base_title}" ""

        while true; do
            sleep 1 || break

            local current_time=$SECONDS
            if [[ $((current_time - last_hook_check)) -ge 1 ]]; then
                last_hook_check=$current_time

                local hook_status=""
                if [[ -n "${status_file}" && -f "${status_file}" ]]; then
                    hook_status=$(< "${status_file}") || hook_status=""
                fi

                if [[ -n "${hook_status}" ]]; then
                    if [[ "${hook_status}" != "${current_context}" ]]; then
                        current_context="${hook_status}"
                    fi
                else
                    current_context="💤 Idle"
                fi

                local new_summary=""
                if [[ -n "${context_file}" && -f "${context_file}" ]]; then
                    new_summary=$(< "${context_file}") || new_summary=""
                fi

                if [[ "${new_summary}" != "${task_summary}" ]]; then
                    task_summary="${new_summary}"
                    clean_summary="${task_summary}"
                    if [[ -n "${CCP_PROJECT_NAME:-}" && -n "${clean_summary}" ]]; then
                        clean_summary=$(printf '%s' "${clean_summary}" \
                            | sed "s/ (${CCP_PROJECT_NAME})[^,]*,\{0,1\}[[:space:]]*//g" \
                            | sed 's/^[[:space:]]*//' \
                            | sed 's/[[:space:]]*$//')
                    fi
                fi
            fi

            local display_content=""
            if [[ -n "${clean_summary}" && -n "${current_context}" ]]; then
                display_content="${clean_summary} | ${current_context}"
            elif [[ -n "${clean_summary}" ]]; then
                display_content="${clean_summary}"
            elif [[ -n "${current_context}" ]]; then
                display_content="${current_context}"
            fi

            local _body=""
            if [[ -n "${title_prefix}" && -n "${display_content}" ]]; then
                _body="${title_prefix}${display_content}"
            elif [[ -n "${title_prefix}" ]]; then
                _body="${title_prefix%' | '}"
            else
                _body="${display_content}"
            fi

            local display_context="${_body}"

            if [[ "${display_context}" != "${prev_display_context}" ]]; then
                update_title_with_context "${base_title}" "${display_context}"
                prev_display_context="${display_context}"
            fi
        done
    ) &

    local monitor_pid=$!
    echo "${monitor_pid}" > "${STATE_DIR}/monitor.$$.pid"
}

cleanup_monitor() {
    local monitor_pid_file="${STATE_DIR}/monitor.$$.pid"
    if [[ -f "${monitor_pid_file}" ]]; then
        local monitor_pid
        monitor_pid=$(< "${monitor_pid_file}")
        kill "${monitor_pid}" 2>/dev/null || true
        wait "${monitor_pid}" 2>/dev/null || true
        rm -f "${monitor_pid_file}"
    fi
}

export -f status_to_priority
export -f extract_context
export -f title_updater
export -f cleanup_monitor
