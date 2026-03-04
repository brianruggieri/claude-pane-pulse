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
# shellcheck source=lib/status.sh
source "${_MONITOR_SCRIPT_DIR}/status.sh"

# ── Status priority levels ────────────────────────────────────────────────────
# 🐛 Error          = 100
# ❌ Tests failed   = 90
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
# 🖥️ Running        = 55  (catch-all for unrecognised ● Bash() lines)
# 💤 Idle           = 10

# ── extract_context ───────────────────────────────────────────────────────────
# Parse a stripped line of output and return "status|priority".
# Empty status means no match — caller keeps the previous context.
#
# Pattern philosophy:
#   • Error/failure patterns anchor to word boundaries to avoid false positives.
#   • Build/test/install patterns match both raw command output AND Claude Code's
#     "● Bash(command...)" tool-call headers, so they fire the moment Claude
#     decides to run a command rather than only after the command prints output.
#   • Thinking is detected via FIFO liveness + hooks, not text parsing.
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

# monitor_claude_output: run Claude Code with real-time title updates
monitor_claude_output() {
    local base_title="$1"
    local pipe="${STATE_DIR}/pipe.$$"

    # Create named pipe for output monitoring
    mkfifo "${pipe}" 2>/dev/null || true

    # ── Background monitor subshell ──────────────────────────────────────────
    # Reads from the FIFO, strips ANSI codes, updates the terminal title.
    # Uses read -t 1 so we heartbeat the title every second even when output
    # is quiet, preventing Claude Code's TUI from permanently overriding it.
    (
        # bash 3.2 (macOS) compatibility: read -t returns 1 on timeout, same
        # as EOF — set -e would kill us on the first quiet second.  Disable
        # exit-on-error for the whole monitor subshell; we handle every exit
        # code explicitly below.
        set +e

        local current_priority=0
        local current_context=""
        local frame_counter=0
        local task_summary=""
        local clean_summary=""        # cached: recomputed only when task_summary changes
        local prev_display_context=""  # cached: title write skipped when unchanged
        local needs_title_update=false # gate: skip animate+compose on non-state-change lines
        local last_fifo_activity=$SECONDS
        local last_hook_check=$SECONDS # hook files polled at 1/sec regardless of tick rate
        # Hook data files (set by bin/ccp via environment exports)
        local status_file="${CCP_STATUS_FILE:-}"
        local context_file="${CCP_CONTEXT_FILE:-}"

        # Fast animation tick: bash 4+ supports fractional read -t values; bash 3.2
        # (macOS system bash) silently truncates 0.15 to 0, making read non-blocking
        # and spinning the CPU.  Also skip fast mode inside tmux — title writes there
        # cost a subprocess fork per frame.
        local read_timeout="1"
        if [[ "${BASH_VERSINFO[0]:-3}" -ge 4 && -z "${TMUX:-}" ]]; then
            read_timeout="0.15"  # ~6.7 fps — close to Claude Code's native 8.3 fps
        fi

        # Build the static title prefix: "project (branch) | "
        # Computed once — these env vars are exported by bin/ccp at launch.
        local title_prefix=""
        local _proj="${CCP_PROJECT_NAME:-}"
        local _branch="${CCP_BRANCH_NAME:-}"
        if [[ -n "${_proj}" ]]; then
            [[ "${#_proj}" -gt 15 ]] && _proj="${_proj:0:14}…"
            if [[ -n "${_branch}" ]]; then
                [[ "${#_branch}" -gt 12 ]] && _branch="${_branch:0:11}…"
                title_prefix="${_proj} (${_branch}) | "
            else
                title_prefix="${_proj} | "
            fi
        fi

        local esc
        esc=$(printf '\033')

        # Assert base title once before Claude Code starts its TUI
        update_title_with_context "${base_title}" ""

        while true; do
            local line read_status
            read_status=0
            IFS= read -r -t "${read_timeout}" line || read_status=$?

            if [[ ${read_status} -eq 0 ]]; then
                # ── Got a line ────────────────────────────────────────────
                # Strip carriage returns; ANSI colour codes are removed only
                # when we actually need the text content (see below).
                line="${line%$'\r'}"

                if [[ -n "${line}" ]]; then
                    # Any FIFO output means Claude is alive.  Update the
                    # activity timestamp so idle is suppressed as long as
                    # bytes are flowing — regardless of whether hooks are
                    # working or whether we recognise the content.
                    last_fifo_activity=$SECONDS

                    # If currently showing idle, lift to Thinking immediately.
                    # Hooks will supply the real named status on the next
                    # heartbeat tick when they are working correctly.
                    if [[ "${current_priority}" -le 10 ]]; then
                        current_context="💭 Thinking"
                        current_priority=70
                        needs_title_update=true  # state changed — write title now
                    fi

                    # Completion events (test pass/fail, git commits) are the
                    # only status we detect from PTY text — hooks don't cover
                    # these.  The sed+tr ANSI strip is expensive (~5 ms, a
                    # subprocess fork) so we gate it behind a cheap bash-native
                    # pre-filter: only lines that could plausibly be completion
                    # output (contain "pass", "fail", or "commit") pay the
                    # stripping cost.  Typically < 1 % of FIFO lines qualify.
                    if [[ "${line}" == *pass* || "${line}" == *fail* || \
                          "${line}" == *commit* ]]; then
                        local stripped
                        stripped=$(printf '%s' "${line}" \
                            | sed "s/${esc}\[[?0-9;]*[a-zA-Z]//g")
                        local result new_context
                        result=$(extract_context "${stripped}")
                        new_context="${result%|*}"
                        if [[ "${new_context}" =~ \
                              (Tests\ passed|Tests\ failed|Committed) ]]; then
                            current_context="${new_context}"
                            current_priority=0   # let the next event win
                            needs_title_update=true  # completion event — write title now
                        fi
                    fi
                fi

            elif [[ ${read_status} -gt 128 || ${read_status} -eq 1 ]]; then
                # ── Animation tick (every read_timeout interval) ───────────
                # bash 4+: read -t timeout returns >128
                # bash 3.2 (macOS): read -t timeout returns 1 (same as EOF;
                # indistinguishable).  We treat both as a tick and rely on
                # cleanup_monitor() to kill us when Claude Code exits.

                # Advance animation frame every tick for smooth pulse.
                [[ -n "${current_context}" ]] && frame_counter=$(( (frame_counter + 1) % 10 ))
                needs_title_update=true

                # ── Hook polling — 1× per second maximum ──────────────────
                # Decoupled from the animation tick rate: file reads and idle
                # logic run at most once per wall-clock second regardless of
                # how fast the animation is ticking.
                local current_time=$SECONDS
                if [[ $((current_time - last_hook_check)) -ge 1 ]]; then
                    last_hook_check=$current_time

                    # ── Read hook status file ──────────────────────────────
                    local hook_status=""
                    if [[ -n "${status_file}" && -f "${status_file}" ]]; then
                        hook_status=$(< "${status_file}") || hook_status=""
                    fi

                    if [[ -n "${hook_status}" && "${hook_status}" != "${current_context}" ]]; then
                        current_context="${hook_status}"
                        current_priority=$(status_to_priority "${hook_status}")
                    elif [[ -z "${hook_status}" && "${current_priority}" -gt 10 ]]; then
                        # Stop hook fired (empty status file).  Wait for the FIFO
                        # to drain before committing to idle — the last output
                        # bytes can lag the hook by 1-3 s.
                        if [[ $((current_time - last_fifo_activity)) -gt 3 ]]; then
                            current_priority=10
                            current_context="💤 Idle"
                        fi
                    fi

                    # Fallback idle: FIFO has been completely silent for 60 s.
                    # This fires when hooks are broken and Claude has genuinely
                    # stopped — FIFO silence is version-stable unlike text parsing.
                    if [[ $((current_time - last_fifo_activity)) -gt 60 ]] && \
                       [[ "${current_priority}" -gt 10 ]]; then
                        current_priority=10
                        current_context="💤 Idle"
                    fi

                    # ── Read context file (user prompt as task summary) ────
                    if [[ -n "${context_file}" && -f "${context_file}" ]]; then
                        local new_summary
                        new_summary=$(< "${context_file}") || new_summary=""
                        if [[ -n "${new_summary}" && "${new_summary}" != "${task_summary}" ]]; then
                            task_summary="${new_summary}"
                            # Recompute clean_summary once here (1/sec) rather
                            # than via 3× sed subprocess forks on every tick.
                            clean_summary="${task_summary}"
                            if [[ -n "${CCP_PROJECT_NAME:-}" ]]; then
                                clean_summary=$(printf '%s' "${clean_summary}" \
                                    | sed "s/ (${CCP_PROJECT_NAME})[^,]*,\{0,1\}[[:space:]]*//g" \
                                    | sed 's/^[[:space:]]*//' \
                                    | sed 's/[[:space:]]*$//')
                            fi
                        fi
                    fi
                fi
            else
                # EOF: write end of pipe closed (claude has exited)
                break
            fi

            # ── Re-assert title — only when state has actually changed ──────
            # display_context can only change on heartbeat ticks (frame_counter
            # advances there; hook status and task_summary are read there).
            # On normal FIFO line reads needs_title_update stays false, so the
            # animate+compose+write block is skipped entirely — zero $() forks,
            # zero OSC writes, zero tmux subprocesses on the hot path.
            if [[ "${needs_title_update}" == "true" ]]; then
                needs_title_update=false

                # Inline animation — no $() fork.
                # Spinner is extracted separately so it can be placed at the
                # FRONT of the title: "✳ project (branch) | summary | status"
                # rather than appended to the status text.
                local _spinner=""
                if is_active_status "${current_context}"; then
                    _spinner="$(spinner_frame "${frame_counter}")"
                fi

                # Compose body: [prefix][summary | ]status
                # clean_summary is pre-computed in the hook-poll section above.
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

                # Prepend spinner to body when active
                local display_context=""
                if [[ -n "${_spinner}" && -n "${_body}" ]]; then
                    display_context="${_spinner} ${_body}"
                else
                    display_context="${_body}"
                fi

                if [[ "${display_context}" != "${prev_display_context}" ]]; then
                    update_title_with_context "${base_title}" "${display_context}"
                    prev_display_context="${display_context}"
                fi
            fi
        done
    ) < "${pipe}" &

    local monitor_pid=$!
    echo "${monitor_pid}" > "${STATE_DIR}/monitor.$$.pid"

    # Run Claude Code in a PTY using Python's pty module.
    local claude_cmd python_cmd
    claude_cmd=$(get_claude_cmd)
    python_cmd=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")

    if [[ -n "${python_cmd}" ]]; then
        "${python_cmd}" "${_MONITOR_SCRIPT_DIR}/pty_wrapper.py" "${pipe}" "${claude_cmd}"
    else
        log_warning "python3 not found; dynamic title monitoring disabled"
        "${claude_cmd}"
    fi

    # Cleanup: kill the monitor, wait to suppress bash's "Terminated" message
    kill "${monitor_pid}" 2>/dev/null || true
    wait "${monitor_pid}" 2>/dev/null || true
    rm -f "${pipe}"
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

export -f extract_context
export -f monitor_claude_output
export -f cleanup_monitor
