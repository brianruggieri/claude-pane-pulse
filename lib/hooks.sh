#!/usr/bin/env bash
# lib/hooks.sh - Claude Code hooks integration for ccp
# Injects Claude Code hooks (tool, prompt, lifecycle, notification, session)
# into .claude/settings.local.json so ccp receives structured event data
# instead of parsing terminal output.

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
    # our runner path. This handles both clean teardown (entries have _ccp_pid)
    # and crash/legacy cases (entries lack _ccp_pid tag). Entries whose command
    # does NOT reference our runner are left untouched (user hooks).
    local pre_cmd prompt_cmd stop_cmd post_cmd post_fail_cmd
    local permission_cmd notification_cmd task_completed_cmd
    local session_start_cmd session_end_cmd pre_compact_cmd
    local subagent_start_cmd subagent_stop_cmd teammate_idle_cmd
    local config_change_cmd worktree_create_cmd worktree_remove_cmd
    pre_cmd="bash \"${hook_runner_path}\" pre-tool"
    prompt_cmd="bash \"${hook_runner_path}\" user-prompt"
    stop_cmd="bash \"${hook_runner_path}\" stop"
    post_cmd="bash \"${hook_runner_path}\" post-tool"
    post_fail_cmd="bash \"${hook_runner_path}\" post-tool-failure"
    permission_cmd="bash \"${hook_runner_path}\" event PermissionRequest"
    notification_cmd="bash \"${hook_runner_path}\" event Notification"
    task_completed_cmd="bash \"${hook_runner_path}\" event TaskCompleted"
    session_start_cmd="bash \"${hook_runner_path}\" event SessionStart"
    session_end_cmd="bash \"${hook_runner_path}\" event SessionEnd"
    pre_compact_cmd="bash \"${hook_runner_path}\" event PreCompact"
    subagent_start_cmd="bash \"${hook_runner_path}\" event SubagentStart"
    subagent_stop_cmd="bash \"${hook_runner_path}\" event SubagentStop"
    teammate_idle_cmd="bash \"${hook_runner_path}\" event TeammateIdle"
    config_change_cmd="bash \"${hook_runner_path}\" event ConfigChange"
    worktree_create_cmd="bash \"${hook_runner_path}\" event WorktreeCreate"
    worktree_remove_cmd="bash \"${hook_runner_path}\" event WorktreeRemove"
    local deduped
    deduped=$(printf '%s' "${existing_json}" | jq \
        --arg pre       "${pre_cmd}" \
        --arg prompt    "${prompt_cmd}" \
        --arg stop      "${stop_cmd}" \
        --arg post      "${post_cmd}" \
        --arg post_fail "${post_fail_cmd}" \
        --arg permission      "${permission_cmd}" \
        --arg notification    "${notification_cmd}" \
        --arg task_completed  "${task_completed_cmd}" \
        --arg session_start   "${session_start_cmd}" \
        --arg session_end     "${session_end_cmd}" \
        --arg pre_compact     "${pre_compact_cmd}" \
        --arg subagent_start  "${subagent_start_cmd}" \
        --arg subagent_stop   "${subagent_stop_cmd}" \
        --arg teammate_idle   "${teammate_idle_cmd}" \
        --arg config_change   "${config_change_cmd}" \
        --arg worktree_create "${worktree_create_cmd}" \
        --arg worktree_remove "${worktree_remove_cmd}" '
        # Match any hook_runner.sh entry with the same mode argument, regardless of path.
        # This cleans up stale entries left from the source repo, old installs, or crashes.
        def not_ccp(cmd):
            (cmd | gsub("^bash \"[^\"]+hook_runner\\.sh\" "; "")) as $suffix |
            (.hooks // []) | map(.command | test("hook_runner\\.sh\" " + $suffix + "$")) | any | not;
        .hooks.PreToolUse          = [(.hooks.PreToolUse          // [])[] | select(not_ccp($pre))]       |
        .hooks.UserPromptSubmit    = [(.hooks.UserPromptSubmit    // [])[] | select(not_ccp($prompt))]    |
        .hooks.Stop                = [(.hooks.Stop                // [])[] | select(not_ccp($stop))]      |
        .hooks.PostToolUse         = [(.hooks.PostToolUse         // [])[] | select(not_ccp($post))]      |
        .hooks.PostToolUseFailure  = [(.hooks.PostToolUseFailure  // [])[] | select(not_ccp($post_fail))] |
        .hooks.PermissionRequest   = [(.hooks.PermissionRequest   // [])[] | select(not_ccp($permission))] |
        .hooks.Notification        = [(.hooks.Notification        // [])[] | select(not_ccp($notification))] |
        .hooks.TaskCompleted       = [(.hooks.TaskCompleted       // [])[] | select(not_ccp($task_completed))] |
        .hooks.SessionStart        = [(.hooks.SessionStart        // [])[] | select(not_ccp($session_start))] |
        .hooks.SessionEnd          = [(.hooks.SessionEnd          // [])[] | select(not_ccp($session_end))] |
        .hooks.PreCompact          = [(.hooks.PreCompact          // [])[] | select(not_ccp($pre_compact))] |
        .hooks.SubagentStart       = [(.hooks.SubagentStart       // [])[] | select(not_ccp($subagent_start))] |
        .hooks.SubagentStop        = [(.hooks.SubagentStop        // [])[] | select(not_ccp($subagent_stop))] |
        .hooks.TeammateIdle        = [(.hooks.TeammateIdle        // [])[] | select(not_ccp($teammate_idle))] |
        .hooks.ConfigChange        = [(.hooks.ConfigChange        // [])[] | select(not_ccp($config_change))] |
        .hooks.WorktreeCreate      = [(.hooks.WorktreeCreate      // [])[] | select(not_ccp($worktree_create))] |
        .hooks.WorktreeRemove      = [(.hooks.WorktreeRemove      // [])[] | select(not_ccp($worktree_remove))] |
        if (.hooks.PreToolUse         | length) == 0 then del(.hooks.PreToolUse)         else . end |
        if (.hooks.UserPromptSubmit   | length) == 0 then del(.hooks.UserPromptSubmit)   else . end |
        if (.hooks.Stop               | length) == 0 then del(.hooks.Stop)               else . end |
        if (.hooks.PostToolUse        | length) == 0 then del(.hooks.PostToolUse)        else . end |
        if (.hooks.PostToolUseFailure | length) == 0 then del(.hooks.PostToolUseFailure) else . end |
        if (.hooks.PermissionRequest  | length) == 0 then del(.hooks.PermissionRequest)  else . end |
        if (.hooks.Notification       | length) == 0 then del(.hooks.Notification)       else . end |
        if (.hooks.TaskCompleted      | length) == 0 then del(.hooks.TaskCompleted)      else . end |
        if (.hooks.SessionStart       | length) == 0 then del(.hooks.SessionStart)       else . end |
        if (.hooks.SessionEnd         | length) == 0 then del(.hooks.SessionEnd)         else . end |
        if (.hooks.PreCompact         | length) == 0 then del(.hooks.PreCompact)         else . end |
        if (.hooks.SubagentStart      | length) == 0 then del(.hooks.SubagentStart)      else . end |
        if (.hooks.SubagentStop       | length) == 0 then del(.hooks.SubagentStop)       else . end |
        if (.hooks.TeammateIdle       | length) == 0 then del(.hooks.TeammateIdle)       else . end |
        if (.hooks.ConfigChange       | length) == 0 then del(.hooks.ConfigChange)       else . end |
        if (.hooks.WorktreeCreate     | length) == 0 then del(.hooks.WorktreeCreate)     else . end |
        if (.hooks.WorktreeRemove     | length) == 0 then del(.hooks.WorktreeRemove)     else . end |
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
         ]) |
         .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [
             {"_ccp_pid": $pid, "matcher": ".*", "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" post-tool"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) + [
             {"_ccp_pid": $pid, "matcher": ".*", "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" post-tool-failure"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.PermissionRequest = ((.hooks.PermissionRequest // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" event PermissionRequest"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.Notification = ((.hooks.Notification // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" event Notification"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.TaskCompleted = ((.hooks.TaskCompleted // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" event TaskCompleted"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.SessionStart = ((.hooks.SessionStart // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" event SessionStart"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.SessionEnd = ((.hooks.SessionEnd // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" event SessionEnd"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.PreCompact = ((.hooks.PreCompact // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" event PreCompact"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.SubagentStart = ((.hooks.SubagentStart // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" event SubagentStart"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.SubagentStop = ((.hooks.SubagentStop // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" event SubagentStop"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.TeammateIdle = ((.hooks.TeammateIdle // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" event TeammateIdle"), "timeout": 5000, "async": true}
             ]}
         ]) |
         .hooks.ConfigChange = ((.hooks.ConfigChange // []) + [
             {"_ccp_pid": $pid, "hooks": [
                 {"type": "command", "command": ("bash \"" + $runner + "\" event ConfigChange"), "timeout": 5000, "async": true}
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
        .hooks.PreToolUse         = [(.hooks.PreToolUse         // [])[] | select(._ccp_pid != $pid)] |
        .hooks.UserPromptSubmit   = [(.hooks.UserPromptSubmit   // [])[] | select(._ccp_pid != $pid)] |
        .hooks.Stop               = [(.hooks.Stop               // [])[] | select(._ccp_pid != $pid)] |
        .hooks.PostToolUse        = [(.hooks.PostToolUse        // [])[] | select(._ccp_pid != $pid)] |
        .hooks.PostToolUseFailure = [(.hooks.PostToolUseFailure // [])[] | select(._ccp_pid != $pid)] |
        .hooks.PermissionRequest  = [(.hooks.PermissionRequest  // [])[] | select(._ccp_pid != $pid)] |
        .hooks.Notification       = [(.hooks.Notification       // [])[] | select(._ccp_pid != $pid)] |
        .hooks.TaskCompleted      = [(.hooks.TaskCompleted      // [])[] | select(._ccp_pid != $pid)] |
        .hooks.SessionStart       = [(.hooks.SessionStart       // [])[] | select(._ccp_pid != $pid)] |
        .hooks.SessionEnd         = [(.hooks.SessionEnd         // [])[] | select(._ccp_pid != $pid)] |
        .hooks.PreCompact         = [(.hooks.PreCompact         // [])[] | select(._ccp_pid != $pid)] |
        .hooks.SubagentStart      = [(.hooks.SubagentStart      // [])[] | select(._ccp_pid != $pid)] |
        .hooks.SubagentStop       = [(.hooks.SubagentStop       // [])[] | select(._ccp_pid != $pid)] |
        .hooks.TeammateIdle       = [(.hooks.TeammateIdle       // [])[] | select(._ccp_pid != $pid)] |
        .hooks.ConfigChange       = [(.hooks.ConfigChange       // [])[] | select(._ccp_pid != $pid)] |
        .hooks.WorktreeCreate     = [(.hooks.WorktreeCreate     // [])[] | select(._ccp_pid != $pid)] |
        .hooks.WorktreeRemove     = [(.hooks.WorktreeRemove     // [])[] | select(._ccp_pid != $pid)] |
        if (.hooks.PreToolUse         | length) == 0 then del(.hooks.PreToolUse)         else . end |
        if (.hooks.UserPromptSubmit   | length) == 0 then del(.hooks.UserPromptSubmit)   else . end |
        if (.hooks.Stop               | length) == 0 then del(.hooks.Stop)               else . end |
        if (.hooks.PostToolUse        | length) == 0 then del(.hooks.PostToolUse)        else . end |
        if (.hooks.PostToolUseFailure | length) == 0 then del(.hooks.PostToolUseFailure) else . end |
        if (.hooks.PermissionRequest  | length) == 0 then del(.hooks.PermissionRequest)  else . end |
        if (.hooks.Notification       | length) == 0 then del(.hooks.Notification)       else . end |
        if (.hooks.TaskCompleted      | length) == 0 then del(.hooks.TaskCompleted)      else . end |
        if (.hooks.SessionStart       | length) == 0 then del(.hooks.SessionStart)       else . end |
        if (.hooks.SessionEnd         | length) == 0 then del(.hooks.SessionEnd)         else . end |
        if (.hooks.PreCompact         | length) == 0 then del(.hooks.PreCompact)         else . end |
        if (.hooks.SubagentStart      | length) == 0 then del(.hooks.SubagentStart)      else . end |
        if (.hooks.SubagentStop       | length) == 0 then del(.hooks.SubagentStop)       else . end |
        if (.hooks.TeammateIdle       | length) == 0 then del(.hooks.TeammateIdle)       else . end |
        if (.hooks.ConfigChange       | length) == 0 then del(.hooks.ConfigChange)       else . end |
        if (.hooks.WorktreeCreate     | length) == 0 then del(.hooks.WorktreeCreate)     else . end |
        if (.hooks.WorktreeRemove     | length) == 0 then del(.hooks.WorktreeRemove)     else . end |
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
