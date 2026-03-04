# Dynamic Title System

**claude-pane-pulse** updates your terminal pane title in real time to show what Claude Code is doing — building, testing, editing, thinking, and more.

## How It Works

The system is entirely **hook-based**. No output parsing. No PTY tee. Just structured events.

```
Claude Code execution
        │
        ▼
   Hook fires
        │
        ▼
hook_runner.sh reads JSON
        │
        ▼
   status.<pid>.txt written to disk
        │
        ▼
title_updater polls file every 1s
        │
        ▼
OSC escape sequence updates terminal title
```

### Initialization

On startup, `ccp` calls `setup_ccp_hooks()` which:
1. Reads the project's `.claude/settings.local.json`
2. Removes any stale ccp hook entries from previous sessions (dead PIDs)
3. Injects fresh hook entries tagged with the current session's PID
4. Writes the updated settings back to disk

Claude Code parses the settings file and registers the hooks. As events fire (PreToolUse, PostToolUse, UserPromptSubmit, Stop, etc.), Claude Code invokes `lib/hook_runner.sh <mode>` with the event JSON on stdin.

### Hook Processing

Each hook event triggers `hook_runner.sh`, which:
1. Receives the event JSON on stdin (contains tool name, command, response, etc.)
2. Inspects the JSON to determine the status
3. Writes the status string to `~/.config/claude-pane-pulse/status.<pid>.txt`
4. Optionally writes a context summary to `~/.config/claude-pane-pulse/context.<pid>.txt`

### Background Monitor

A bash subshell (`title_updater`) runs in the background for the duration of the session:
1. Polls the status file every 1 second
2. Detects when the status changes
3. Reads the context file (if present)
4. Writes a title update using the method appropriate for the detected terminal backend

**Terminal backends** (detected automatically from `$TMUX`, `$TERM_PROGRAM`, `$KITTY_PID`):

| Terminal | Backend | Title target | Independent split-pane titles |
|----------|---------|--------------|-------------------------------|
| iTerm2 | `iterm2` | OSC 1 (icon name / per-pane) | ✅ Yes — each split pane has its own title bar |
| WezTerm | `wezterm` | OSC 1 (per-pane) | ✅ Yes |
| tmux ≥ 2.9 | `tmux-pane` | `select-pane -T` + OSC 1 DCS passthrough | ✅ Yes — per-pane via `TMUX_PANE` |
| tmux < 2.9 | `tmux-window` | `rename-window` + OSC passthrough | ❌ Whole window only |
| Kitty | `kitty` | `kitty @ set-window-title` IPC | ❌ Active window only |
| Apple Terminal | `apple-terminal` | OSC 2 (window title) | ❌ No split panes |
| Ghostty | `ghostty` | OSC 2 (window title) | ❌ No per-pane title API |
| Other / fallback | `osc2` | OSC 2 (window title) | ❌ |

**OSC 1 vs OSC 2** — the key distinction for split-pane use:
- **OSC 1** (`\033]1;`) sets the *icon name* / *per-pane* title. In iTerm2 and WezTerm, this is the title shown in each individual split pane's title bar — completely independent between panes.
- **OSC 2** (`\033]2;`) sets the *window* title — shared across the whole app window. Not useful in split-pane layouts since every pane would overwrite the same title.

ccp writes to OSC 1 for terminals that support it and clears OSC 2 to keep the app-level title bar clean. For terminals that only render OSC 2 (Apple Terminal, Ghostty), ccp falls back to OSC 2.

The **tmux-pane** backend (tmux ≥ 2.9) additionally calls `tmux select-pane -T` to set the pane's native title in tmux's status bar, and then wraps OSC 1 in DCS passthrough so the inner terminal also gets the update. The `rename-window` path was deliberately not used for per-pane mode because it renames the whole tmux window, not just the active pane.

### Cleanup

On exit (EXIT trap), `teardown_ccp_hooks()`:
1. Reads `.claude/settings.local.json`
2. Removes only the entries tagged with the current session's PID
3. Deletes the settings file entirely if it becomes empty
4. Leaves other sessions' hooks and user-defined hooks untouched

## Status Signals

### PreToolUse — Detect the tool before it runs

The hook fires when Claude Code is about to invoke a tool. We examine the tool name and arguments:

| Tool | Status |
|------|--------|
| Edit, Write, MultiEdit, NotebookEdit | `✏️ Editing` |
| Read, Glob, Grep | `📖 Reading` |
| WebFetch, WebSearch | `🌐 Browsing` |
| Task, Agent | `🤖 Delegating` |
| Bash(jest/vitest/pytest/mocha/etc.) | `🧪 Testing` |
| Bash(webpack/tsc/vite build/esbuild/etc.) | `🔨 Building` |
| Bash(npm install/pip install/yarn/etc.) | `📦 Installing` |
| Bash(git push) | `⬆️ Pushing` |
| Bash(git pull) | `⬇️ Pulling` |
| Bash(git merge) | `🔀 Merging` |
| Bash(docker) | `🐳 Docker` |
| Any other Bash | `🖥️ Running` |
| Unknown tool | `🔧 ToolName` |

### PostToolUse — Detect completions

Fired when a Bash tool finishes. We inspect the output for completion keywords:

| Completion | Status |
|-----------|--------|
| `N tests passed` / `N specs passed` | `✅ Tests passed` |
| `N tests failed` / `N specs failing` | `❌ Tests failed` |
| git output starts with `[` (commit hash) | `💾 Committed` |

**Completion events always win**, regardless of current priority. A `✅ Tests passed` (priority 60) immediately overrides any active status like `🧪 Testing` (priority 80).

### PostToolUseFailure — Tool errors

Fired when a tool fails:

| Failure Type | Status |
|-------------|--------|
| Bash test command fails | `❌ Tests failed` |
| Any other tool fails | `🐛 Error` |

### UserPromptSubmit — User sends a message

1. Clears the status file (removes any stale status such as the startup welcome message)
2. Writes the first 5 words of the user's prompt to the context file as a placeholder
3. If `--ai-context` is enabled: spawns a background call to `claude --print` with model `claude-haiku-4-5-20251001`
4. Haiku distills the full prompt into a 3–5 word summary (opt-in only — uses your subscription)
5. Summary overwrites the context file when ready (~1–3 seconds)

### Stop — Claude finishes responding

Clears the status file. The monitor shows `💤 Idle`.

### Event Hooks (Verbose Mode)

Additional hooks fire for lifecycle and permission events. These are only surfaced if `--status-profile verbose` is set:

| Event | Status |
|-------|--------|
| PermissionRequest | `⏸️ Awaiting approval` |
| Notification (with action keywords) | `🙋 Input needed` |
| TaskCompleted | `🏁 Completed` |
| SessionEnd | `🏁 Completed` |
| SessionStart | `🚀 Starting` |
| PreCompact | `📦 Compacting` |
| SubagentStart | `🤖 Delegating` |
| SubagentStop | `✅ Complete` |
| TeammateIdle | `⏸️ Teammate idle` |
| ConfigChange | `⚙️ Configuring` |
| WorktreeCreate | `🌳 Creating branch` |
| WorktreeRemove | `🗑️ Removing branch` |

## Title Format

```
<project> (<branch>) | <task-summary> | <status>
```

Example:
```
my-project (main) | Fix Auth Bug | ✏️ Editing
```

### Components

**Project & branch** (base title)
- Taken from `.git/config` or as passed to `ccp`
- Always preserved

**Task summary**
- First 5 words of your prompt (always); refined to 3–5 word semantic summary if `--ai-context` is enabled
- Only appears after the first UserPromptSubmit
- Before that, the "Welcome" status is shown instead

**Status**
- The current emoji + status text
- Updates every 1–3 seconds as operations progress

<!-- screenshot: Terminal pane title bar showing "✳ claude-pane-pulse (feat-cleanup) | Update docs | ✏️ Editing" -->

## Idle Detection

The monitor shows `💤 Idle` when the Stop hook fires and clears the status file.

## Welcome Status

On startup, before the user sends any prompt, the title shows:

```
👋 Welcome back, <name>
```

Where `<name>` is the first word of `git config user.name`, with fallback to `$USER`.

This status is replaced by `💭 Thinking` as soon as the first UserPromptSubmit hook fires.

## Status Profiles

Two profiles control which events surface as title statuses:

### `--status-profile quiet` (default)

Shows only high-signal events:
- PreToolUse (tool detection)
- PostToolUse/PostToolUseFailure (completions and errors)
- UserPromptSubmit (thinking)
- Stop (idle)
- PermissionRequest (always shown, regardless of profile)

### `--status-profile verbose`

Shows all events, including:
- Lifecycle events (SessionStart, SessionEnd, PreCompact)
- Subagent events (SubagentStart, SubagentStop, TeammateIdle)
- Configuration events (ConfigChange, WorktreeCreate, WorktreeRemove)
- Generic notifications with action keywords (Input needed)
- Task completion events (TaskCompleted)

**Set via:**
- CLI flag: `ccp --status-profile verbose`
- Environment variable: `export CCP_STATUS_PROFILE=verbose`
- CLI flag takes precedence over environment variable

## Hook Lifecycle

### Setup

When `ccp` starts:
1. `setup_ccp_hooks()` reads `.claude/settings.local.json` (created if missing)
2. Deduplicates stale ccp hook entries (from dead sessions)
3. Adds new hook entries pointing to `lib/hook_runner.sh`
4. Tags each entry with the current session's PID
5. Writes the updated settings back to disk

Claude Code then reads the updated settings file and registers the hooks.

### During Session

As Claude Code runs:
- PreToolUse fires → hook_runner sets PreToolUse status
- PostToolUse fires → hook_runner sets PostToolUse/completion status
- UserPromptSubmit fires → hook_runner sets Thinking; spawns distillation only if `--ai-context` enabled
- Stop fires → hook_runner clears status (monitor shows Idle)

### Teardown

On exit (EXIT trap):
1. `teardown_ccp_hooks()` reads `.claude/settings.local.json`
2. Removes only entries tagged with the current session's PID
3. Writes the updated settings back (or deletes file if now empty)
4. Kills the title_updater background subshell

Other sessions' hooks and any user-defined hooks remain untouched.

## Architecture Notes

### Why hooks, not output parsing?

The old system scanned Claude Code's PTY output line-by-line, looking for keywords like "Building" or "Testing". This was fragile:
- Claude Code's output format changes between versions
- Keyword matching is ambiguous (does "Building" mean building or just mentioned in text?)
- Race conditions between status detection and tool completion
- High CPU cost polling PTY output every ~100ms

The hook-based system is:
- **Declarative:** Claude Code tells us exactly what it's doing
- **Reliable:** structured JSON, not regex parsing
- **Efficient:** fires only when events occur, no polling
- **Version-agnostic:** doesn't depend on output format

### Why a background subshell?

The `title_updater` subshell needs to:
- Run for the full duration of the session
- Update the title every 1–3 seconds (heartbeat)
- Poll the status and context files
- Not block or interfere with Claude Code's execution

A separate subshell keeps this work isolated and allows the main session to return control to the user immediately.

### Why Haiku distillation?

User prompts can be long and wandering. When `--ai-context` is enabled, after each user message we run `claude --print` (non-interactive, one turn) with the full prompt to generate a 3–5 word summary. This summary fits neatly in the terminal title and gives context at a glance ("Fix Auth Bug", "Refactor Logging", etc.).

This feature is **opt-in** and explicitly uses your Claude subscription. See [docs/ai-context.md](ai-context.md) for the full details, privacy implications, and how to enable it.

## Implementation

- **Setup & teardown:** `lib/hooks.sh` (setup_ccp_hooks, teardown_ccp_hooks)
- **Hook runner:** `lib/hook_runner.sh` (reads JSON, updates status/context files)
- **Background monitor:** `lib/monitor.sh` (title_updater subshell, polling logic, animation)
- **Title primitives:** `lib/title.sh` (set_title, OSC escape sequences, tmux integration)
