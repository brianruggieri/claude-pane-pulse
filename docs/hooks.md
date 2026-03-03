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
- `WorktreeCreate`
- `WorktreeRemove`

All handlers call `lib/hook_runner.sh` asynchronously and always return success.

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
- `🌿 Worktree created`
- `🧹 Worktree removed`
- Generic notification/event fallbacks (`🔔 ...`)

## Notes

- Existing user hooks are preserved.
- `ccp` deduplicates its own hook entries on startup.
- Hook entries are tagged with the `ccp` process PID and removed on teardown.
