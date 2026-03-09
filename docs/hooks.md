# Claude Code Hooks Integration

`ccp` runs in a hooks-first architecture. When dynamic mode is enabled, it injects
hook commands into the project-local `.claude/settings.local.json` and removes
them on exit.

You usually do not need to configure hooks manually.

## Injected Hook Events

`ccp` injects handlers for:

- `PreToolUse`
- `PostToolUse`
- `PostToolUseFailure`
- `UserPromptSubmit`
- `Stop`
- `PermissionRequest`
- `Notification`
- `TaskCompleted`
- `SessionStart`
- `SessionEnd`
- `PreCompact`
- `SubagentStart`
- `SubagentStop`
- `TeammateIdle`
- `ConfigChange`

All handlers call `lib/hook_runner.sh` asynchronously with a 5000ms timeout and always return success.

> **Note:** `WorktreeCreate` and `WorktreeRemove` are **not** registered by `ccp`. These are lifecycle
> hooks that replace Claude Code's native git worktree operations — the hook must print the new worktree
> path to stdout. Registering them as async status-only handlers (with no stdout) breaks worktree
> isolation (`isolation: "worktree"` on Agent tool calls). Claude Code's built-in implementation handles
> both hooks correctly when no override is present.

## Welcome Status

On startup, `ccp` writes `👋 Welcome back, <FirstName>` to the status file, derived from
`git config user.name` with fallback to `$USER`. This welcome message is displayed in the
terminal title until it is replaced by a later status-writing hook event (for example,
a `PreToolUse` status update).

## Status Profiles

Use `--status-profile quiet|verbose` (or `CCP_STATUS_PROFILE`) to control what
events are surfaced in titles.

### Quiet (default)

High-signal statuses only:

- Existing tool/workflow statuses (`✏️ Editing`, `🧪 Testing`, `🔨 Building`, etc.)
- `⏸️ Awaiting approval` (`PermissionRequest`)
- `🙋 Input needed` (`Notification` when action/input is required)
- `🏁 Completed` (`TaskCompleted` and selected `SessionEnd` reasons)

### Verbose

Everything in quiet, plus lifecycle/internal events:

- `🚀 Session started`
- `🧠 Compacting`
- `🤖 Subagent started`
- `✅ Subagent finished`
- `👥 Teammate idle`
- `⚙️ Config changed`
- Generic notification/event fallbacks (`🔔 ...`)

## Notes

- Existing user hooks are preserved.
- `ccp` deduplicates its own hook entries on startup.
- Hook entries are tagged with the `ccp` process PID and removed on teardown.
- `hook_runner.sh` extends `PATH` to `/opt/homebrew/bin:/usr/local/bin:...` at startup,
  ensuring `jq` and other tools are found. (Claude Code runs hooks with minimal `PATH`.)
- `hook_runner.sh` reads hook JSON from stdin using a `read -r -t 1` loop to handle
  Claude Code's behavior of omitting the trailing newline on hook payloads.
