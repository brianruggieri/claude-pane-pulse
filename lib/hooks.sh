#!/usr/bin/env bash
# lib/hooks.sh - Claude Code hooks integration for ccp
# Injects PreToolUse/UserPromptSubmit/Stop hooks into .claude/settings.local.json
# so the monitor receives structured tool data instead of parsing PTY output.

# Prevent double-sourcing
[[ -n "${_CCP_HOOKS_SOURCED:-}" ]] && return
_CCP_HOOKS_SOURCED=1

_HOOKS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# setup_ccp_hooks: inject CCP hooks into directory's .claude/settings.local.json
# Args: $1=directory (project dir), $2=hook_runner_path
# Prints the settings file path on stdout (capture for use with teardown_ccp_hooks)
setup_ccp_hooks() {
    local directory="$1"
    local hook_runner_path="$2"
    local settings_dir="${directory}/.claude"
    local settings_file="${settings_dir}/settings.local.json"
    local session_pid="$$"

    mkdir -p "${settings_dir}"

    # Read existing JSON, reset to {} if missing or invalid
    local existing_json
    if [[ -f "${settings_file}" ]]; then
        existing_json=$(jq '.' "${settings_file}" 2>/dev/null) || existing_json="{}"
    else
        existing_json="{}"
    fi

    # Deduplicate: remove any existing hook entries whose inner command matches
    # our runner path.  This handles both clean teardown (entries have _ccp_pid)
    # and crash/legacy cases (entries lack _ccp_pid tag).  Entries whose command
    # does NOT reference our runner are left untouched (user's own hooks).
    local pre_cmd prompt_cmd stop_cmd
    pre_cmd="bash \"${hook_runner_path}\" pre-tool"
    prompt_cmd="bash \"${hook_runner_path}\" user-prompt"
    stop_cmd="bash \"${hook_runner_path}\" stop"
    local deduped
    deduped=$(printf '%s' "${existing_json}" | jq \
        --arg pre    "${pre_cmd}" \
        --arg prompt "${prompt_cmd}" \
        --arg stop   "${stop_cmd}" '
        def not_ccp(cmd): (.hooks // []) | map(.command == cmd) | any | not;
        .hooks.PreToolUse       = [(.hooks.PreToolUse       // [])[] | select(not_ccp($pre))]    |
        .hooks.UserPromptSubmit = [(.hooks.UserPromptSubmit // [])[] | select(not_ccp($prompt))] |
        .hooks.Stop             = [(.hooks.Stop             // [])[] | select(not_ccp($stop))]   |
        if (.hooks.PreToolUse     | length) == 0 then del(.hooks.PreToolUse)     else . end |
        if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end |
        if (.hooks.Stop           | length) == 0 then del(.hooks.Stop)           else . end |
        if ((.hooks // {}) == {}) then del(.hooks) else . end
    ' 2>/dev/null) && existing_json="${deduped}" || true

    # Build merged JSON: append CCP hook entries to existing arrays
    local merged
    merged=$(jq -n \
        --argjson existing "${existing_json}" \
        --arg runner "${hook_runner_path}" \
        --arg pid "${session_pid}" \
        '$existing |
         .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [
             {"_ccp_pid": $pid, "matcher": ".*", "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" pre-tool"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" user-prompt"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.Stop = ((.hooks.Stop // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" stop"), "timeout": 5000, "async": true}
             ]}
         ])
        ') || return 0

    # Atomic write
    local tmp_file
    tmp_file="${settings_file}.tmp.$$"
    printf '%s\n' "${merged}" > "${tmp_file}" && mv "${tmp_file}" "${settings_file}" || return 0

    printf '%s' "${settings_file}"
}

# teardown_ccp_hooks: remove CCP hooks tagged with current PID from settings.local.json
# Deletes the file entirely if no hooks remain.
# Args: $1=settings_file path (output of setup_ccp_hooks)
teardown_ccp_hooks() {
    local settings_file="$1"
    local session_pid="$$"

    [[ -n "${settings_file}" ]] || return 0
    [[ -f "${settings_file}" ]] || return 0

    # Filter out our hook entries from each hook type array
    local cleaned
    cleaned=$(jq --arg pid "${session_pid}" '
        .hooks.PreToolUse = [(.hooks.PreToolUse // [])[] | select(._ccp_pid != $pid)] |
        .hooks.UserPromptSubmit = [(.hooks.UserPromptSubmit // [])[] | select(._ccp_pid != $pid)] |
        .hooks.Stop = [(.hooks.Stop // [])[] | select(._ccp_pid != $pid)] |
        if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end |
        if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end |
        if (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end |
        if ((.hooks // {}) == {}) then del(.hooks) else . end
        ' "${settings_file}" 2>/dev/null) || return 0

    # If result is empty object {}, remove the file
    local key_count
    key_count=$(printf '%s' "${cleaned}" | jq 'keys | length' 2>/dev/null) || key_count=0
    if [[ "${key_count}" -eq 0 ]]; then
        rm -f "${settings_file}"
        return 0
    fi

    # Atomic write back
    local tmp_file
    tmp_file="${settings_file}.tmp.$$"
    printf '%s\n' "${cleaned}" > "${tmp_file}" && mv "${tmp_file}" "${settings_file}" || true
}

export -f setup_ccp_hooks
export -f teardown_ccp_hooks
