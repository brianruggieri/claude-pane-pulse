#!/usr/bin/env bash
# lib/hook_runner.sh - Standalone hook runner for ccp
# Called by Claude Code's PreToolUse/UserPromptSubmit/Stop hooks.
# Reads hook JSON from stdin, writes status/context to CCP files.
#
# Usage: bash hook_runner.sh <pre-tool|user-prompt|stop>
# Env:   CCP_STATUS_FILE  - path to write current status
#        CCP_CONTEXT_FILE - path to write task context (user prompt)
#        CCP_DEBUG_LOG    - optional path for debug output
#
# Always exits 0 — must never block or fail Claude Code.

set -uo pipefail

# Extend PATH so jq and standard tools are always reachable.
# Claude Code may invoke hooks with a minimal PATH (e.g. /usr/bin:/bin only).
PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
export PATH

# Debug helper — writes to CCP_DEBUG_LOG if set, otherwise silent.
_dbg() {
    [[ -n "${CCP_DEBUG_LOG:-}" ]] || return 0
    printf '[hook_runner %s %s] %s\n' "${mode:-?}" "$$" "$1" >> "${CCP_DEBUG_LOG}" 2>/dev/null || true
}

mode="${1:-}"

_dbg "START path=${PATH} status_file=${CCP_STATUS_FILE:-} context_file=${CCP_CONTEXT_FILE:-}"

# Guard: nothing to do if CCP files are not configured
if [[ -z "${CCP_STATUS_FILE:-}" && -z "${CCP_CONTEXT_FILE:-}" ]]; then
    exit 0
fi

# Read JSON from stdin with a per-line timeout so async hooks that receive
# JSON but whose stdin is never closed (a Claude Code async-hook quirk) still
# exit cleanly rather than being killed by the hook timeout.  When stdin IS
# closed (normal piped input, tests), the loop exits immediately on EOF.
json_input=""
while IFS= read -r -t 1 line 2>/dev/null; do
    [[ -n "${json_input}" ]] && json_input="${json_input}"$'\n'
    json_input="${json_input}${line}"
done 2>/dev/null || true
[[ -z "${json_input}" ]] && json_input="{}"

_dbg "json=$(printf '%s' "${json_input}" | head -c 120 | tr '\n' ' ')"

# atomic_write: write content to a file via a temp file + mv
atomic_write() {
    local file="$1"
    local content="$2"
    local tmp="${file}.tmp.$$"
    printf '%s' "${content}" > "${tmp}" && mv "${tmp}" "${file}" || true
}

case "${mode}" in
    pre-tool)
        [[ -z "${CCP_STATUS_FILE:-}" ]] && exit 0

        tool=""
        tool=$(printf '%s' "${json_input}" | jq -r '.tool_name // ""' 2>/dev/null) || true

        command_str=""
        command_str=$(printf '%s' "${json_input}" | jq -r '.tool_input.command // ""' 2>/dev/null) || true

        status=""
        case "${tool}" in
            Edit|Write|MultiEdit|NotebookEdit)
                status="✏️ Editing"
                ;;
            Read|Glob|Grep)
                status="📖 Reading"
                ;;
            WebFetch|WebSearch)
                status="🌐 Browsing"
                ;;
            Task|Agent)
                status="🤖 Delegating"
                ;;
            Bash)
                if [[ "${command_str}" =~ (jest|vitest|pytest|mocha|rspec|go[[:space:]]test|cargo[[:space:]]test|phpunit|bun[[:space:]]test|npm[[:space:]]test|yarn[[:space:]]test) ]]; then
                    status="🧪 Testing"
                elif [[ "${command_str}" =~ (webpack|esbuild|tsc[[:space:]]|vite.*build|cargo[[:space:]]build|make[[:space:]]|cmake|gradle|mvn[[:space:]]package|npm[[:space:]]run.*build|yarn.*build) ]]; then
                    status="🔨 Building"
                elif [[ "${command_str}" =~ (npm[[:space:]]+(install|add|ci)|yarn[[:space:]]+(install|add)|pip[[:space:]]install|cargo[[:space:]]add) ]]; then
                    status="📦 Installing"
                elif [[ "${command_str}" =~ git[[:space:]]+push ]]; then
                    status="⬆️ Pushing"
                elif [[ "${command_str}" =~ git[[:space:]]+pull ]]; then
                    status="⬇️ Pulling"
                elif [[ "${command_str}" =~ git[[:space:]]+merge ]]; then
                    status="🔀 Merging"
                elif [[ "${command_str}" =~ docker ]]; then
                    status="🐳 Docker"
                else
                    status="🖥️ Running"
                fi
                ;;
            *)
                if [[ -n "${tool}" ]]; then
                    status="🔧 ${tool}"
                fi
                ;;
        esac

        _dbg "tool=${tool} status=${status}"
        [[ -n "${status}" ]] && atomic_write "${CCP_STATUS_FILE}" "${status}"
        ;;

    user-prompt)
        [[ -z "${CCP_CONTEXT_FILE:-}" ]] && exit 0

        raw_prompt=""
        raw_prompt=$(printf '%s' "${json_input}" | jq -r '.prompt // ""' 2>/dev/null \
            | tr '\n' ' ' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//') || true

        [[ -z "${raw_prompt}" ]] && exit 0
        _dbg "raw_prompt=${raw_prompt}"

        # Clear idle immediately: write 💭 Thinking to status file so the monitor
        # transitions out of idle the moment the user submits a new prompt.
        # (PreToolUse will overwrite this with a more specific status when the
        # first tool call fires.)
        if [[ -n "${CCP_STATUS_FILE:-}" ]]; then
            atomic_write "${CCP_STATUS_FILE}" "💭 Thinking"
        fi

        # Write first-5-words placeholder immediately so the title updates at once
        initial=""
        initial=$(printf '%s' "${raw_prompt}" \
            | awk '{n=(NF<5?NF:5); for(i=1;i<=n;i++) printf "%s%s",$i,(i<n?" ":""); print ""}')
        [[ -n "${initial}" ]] && atomic_write "${CCP_CONTEXT_FILE}" "${initial}"

        # Background AI distillation — rewrites the context file with a proper
        # 3-5 word semantic summary once the haiku call completes (~1-3s).
        # CCP vars are unset inside the subshell so any hooks fired by the child
        # claude process become no-ops (hook_runner exits early when vars unset).
        _ccp_ctx="${CCP_CONTEXT_FILE}"
        _ccp_proj="${CCP_PROJECT_NAME:-}"
        _ccp_raw="${raw_prompt}"
        (
            set +e
            unset CCP_STATUS_FILE CCP_CONTEXT_FILE

            claude_bin=$(command -v claude 2>/dev/null \
                || command -v claude-code 2>/dev/null || echo "")
            [[ -z "${claude_bin}" ]] && exit 0

            # Strip project name from prompt so the summary doesn't repeat it
            task_text="${_ccp_raw}"
            if [[ -n "${_ccp_proj}" ]]; then
                task_text=$(printf '%s' "${task_text}" \
                    | sed "s/ (${_ccp_proj})[^,]*,\{0,1\}[[:space:]]*/  /g" \
                    | sed "s/${_ccp_proj}//g" \
                    | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            fi

            summary=$(printf 'Summarize this developer task in 3-5 words. Title-case. No punctuation. No quotes. Reply with only the words, nothing else. Task: %s' \
                    "${task_text}" \
                | "${claude_bin}" --print --model claude-haiku-4-5-20251001 \
                2>/dev/null | head -1 \
                | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//') || true

            [[ -n "${summary}" ]] && atomic_write "${_ccp_ctx}" "${summary}"
            _dbg "distilled: ${summary}"
        ) &
        disown 2>/dev/null || true
        ;;

    stop)
        [[ -z "${CCP_STATUS_FILE:-}" ]] && exit 0
        _dbg "clearing status file"
        # Empty status signals idle to the monitor on the next heartbeat
        atomic_write "${CCP_STATUS_FILE}" ""
        ;;
esac

exit 0
