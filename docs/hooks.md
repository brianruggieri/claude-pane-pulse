# Claude Code Hook Integration (Optional)

By default, **C**laude **C**ode **P**ane-Pulse detects status by monitoring Claude Code's stdout through a PTY. This works well but has two limitations:

- Updates arrive up to 1 second late (the heartbeat interval)
- Events that produce no output — like permission prompts — aren't visible until the 2-minute silence timeout triggers `⏳ Waiting`

Adding Claude Code hooks gives `ccp` a direct signal channel for sub-second updates on the three key state transitions.

## Setup

Add the following to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "type": "command",
        "command": "ccp --hook-state running"
      }
    ],
    "PermissionRequest": [
      {
        "type": "command",
        "command": "ccp --hook-state needs-input"
      }
    ],
    "Stop": [
      {
        "type": "command",
        "command": "ccp --hook-state done"
      }
    ]
  }
}
```

If you already have hooks configured, merge the entries rather than replacing the whole object.

## What each hook does

| Hook | State | Effect |
|------|-------|--------|
| `UserPromptSubmit` | `running` | Clears any stale `⏳ Waiting` or `💤 Idle` state immediately when you send a new message |
| `PermissionRequest` | `needs-input` | Shows `⏳ Waiting` instantly when Claude needs to ask for a tool permission, without waiting 2 minutes |
| `Stop` | `done` | Shows `💤 Idle` the moment Claude finishes responding |

## How it works

`ccp --hook-state <state>` writes a small signal file to `~/.config/claude-pane-pulse/`. The running `ccp` monitor reads and deletes that file on its next heartbeat tick (within 1 second), then applies the state.

The hook command runs as a child of Claude Code, which runs inside the PTY that `ccp` created. It shares the same `$TMUX_PANE` (in tmux) or TTY, which is how the signal file is routed to the correct running session.

## Without hooks

Everything still works. The output-monitoring path handles all the same transitions — it just relies on regex pattern matching against stdout rather than explicit hook signals. The `⏳ Waiting` state appears after 2 minutes of silence from an active operation rather than immediately on a `PermissionRequest`.
