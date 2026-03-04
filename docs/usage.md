# Usage Guide

## How ccp Works

ccp wraps the Claude Code CLI to provide dynamic terminal pane titles. It injects hooks into `.claude/settings.local.json` that report what Claude is doing—editing, testing, thinking, etc. A background monitor converts these signals into live title updates.

**Title format:** `spinner project(branch) | task summary | status`

**Example:** `✳ my-project (main) | Fix Auth Bug | 🧪 Testing`

On startup, you see `👋 Welcome back, Brian` (from your git config). After you send your first message, the title shows the AI's task summary and updates in real time as Claude works.

## Basic Usage

### Start with a title

```bash
ccp "PR #89 - Fix authentication bug"
```

Sets your terminal title and launches Claude Code with dynamic monitoring enabled.

### Auto-detect from git branch

```bash
ccp --auto-title
```

Or just `ccp` with no arguments—auto-detection is the default.

Reads the current git branch and constructs a title:

| Branch | Title |
|--------|-------|
| `pr/89-fix-auth` | `PR #89 - fix auth` |
| `issue/12-refactor-api` | `Issue #12 - refactor api` |
| `feature/new-login` | `Feature: new login` |
| `fix/12-crash` | `Issue #12 - crash` |
| `main` | `Branch: main` |

If no git repo is found, title is the directory name.

## Quick Format Helpers

These shortcuts build consistently-formatted titles:

```bash
ccp --pr 89 "Fix memory leak"        # → PR #89 - Fix memory leak
ccp --issue 12 "Refactor API"        # → Issue #12 - Refactor API
ccp --feature "OAuth integration"    # → Feature: OAuth integration
ccp --bug "Login crash on iOS"       # → Bug: Login crash on iOS
ccp --refactor "Clean up auth code"  # → Refactor: Clean up auth code
```

## Working Directory

Specify a directory as the second positional argument:

```bash
ccp "PR #89" ~/projects/my-app
```

ccp will `cd` into that directory before launching Claude Code.

## Session Management

### List active sessions

```bash
ccp --list
# Active Sessions:
#
#   • PR #89 - Fix auth
#     Dir: /Users/you/projects/my-app
#     Started: 2026-03-01T10:00:00Z
```

Sessions are stored in `~/.config/claude-pane-pulse/sessions.json` and cleaned up automatically when ccp exits.

### Re-open a previous session

```bash
ccp --goto "auth"
```

Searches saved sessions by title and `cd`'s into that project directory before launching Claude. This restores your **working directory**, not your conversation history.

To resume a Claude **conversation** (e.g., picking up where you left off in chat), use Claude's own flags:

```bash
ccp -c                              # resume last conversation
ccp --resume abc-123                # resume by session ID
```

These are forwarded directly to Claude Code and work just like running `claude -c` or `claude --resume` manually.

## Claude Flag Passthrough

ccp forwards unrecognized flags directly to Claude Code. Any Claude flag works:

```bash
ccp --model sonnet "Fix auth"                    # specify model
ccp --permission-mode acceptEdits "Refactor"    # permission mode
ccp --effort high "Big refactor"                 # effort level
ccp --worktree "Add feature"                     # create a git worktree
ccp "My task" -- --from-pr 89                   # use -- for ambiguous flags
```

ccp explicitly handles: `--model`, `--permission-mode`, `--effort`, `-c`/`--continue`, `-r`/`--resume`, `--debug`, `--verbose`, `--worktree`, `--from-pr`, `--add-dir`, `--allowedTools`, `--disallowedTools`, `--mcp-config`, `--ide`, `--dangerously-skip-permissions`, and a few others.

Any unrecognized `-*` flag is also forwarded, so you can pass new Claude flags without waiting for a ccp update.

## Options Reference

| Option | Description |
|--------|-------------|
| `TITLE` | Set the pane title (positional) |
| `DIRECTORY` | Working directory for Claude Code (positional) |
| `--pr N DESC` | Quick format: `PR #N - DESC` |
| `--issue N DESC` | Quick format: `Issue #N - DESC` |
| `--feature DESC` | Quick format: `Feature: DESC` |
| `--bug DESC` | Quick format: `Bug: DESC` |
| `--refactor DESC` | Quick format: `Refactor: DESC` |
| `--auto-title` | Detect title from git branch (default behavior) |
| `--no-dynamic` | Static title only — disable monitoring |
| `--status-profile quiet\|verbose` | Status surface (default: quiet) |
| `--ai-context` | Summarize prompts via claude-haiku (opt-in, uses your subscription) |
| `--goto TITLE` | Re-open previous session by title search |
| `--list`, `-l` | List all active ccp sessions |
| `--help`, `-h` | Show help |
| `--version`, `-v` | Show version |
| `-c`, `--continue` | (forwarded to Claude) Resume last conversation |
| `-r`, `--resume [ID]` | (forwarded to Claude) Resume by session ID |
| `--model MODEL` | (forwarded to Claude) Model to use |
| `--permission-mode MODE` | (forwarded to Claude) Permission mode |
| `--effort LEVEL` | (forwarded to Claude) Effort level |
| `--` | Everything after is passed directly to Claude |
| any `-*` flag | Unknown flags forwarded to Claude |

## Status Profile

Use tiered status visibility depending on how much title detail you want:

```bash
# Default: high-signal statuses only
ccp --status-profile quiet "PR #89"

# Full lifecycle statuses (session/worktree/subagent/config)
ccp --status-profile verbose "PR #89"
```

You can also set an environment default:

```bash
export CCP_STATUS_PROFILE=verbose
ccp "PR #89"
```

Precedence: CLI flag `--status-profile` overrides `CCP_STATUS_PROFILE`; default is `quiet`.

## Multi-Pane Workflow

The primary use case—running multiple Claude Code sessions in parallel:

<!-- screenshot: iTerm2 split pane with four Claude sessions, each showing different titles and status indicators -->

```
┌─────────────────────────┬─────────────────────────┐
│  ✳ PR #89 - Fix auth    │  ✳ Issue #12 - API      │
│  🧪 Testing             │  ✅ Tests passed        │
├─────────────────────────┼─────────────────────────┤
│  ✳ Feature: OAuth       │  ✳ Bug: Login crash     │
│  💭 Thinking            │  🐛 Error               │
└─────────────────────────┴─────────────────────────┘
```

Open four terminal panes and run:

```bash
# Pane 1
ccp --pr 89 "Fix auth"

# Pane 2
ccp --issue 12 "API tests"

# Pane 3
ccp --feature "OAuth"

# Pane 4
ccp --bug "Login crash"
```

Each pane now shows:
- Your pane title (project name, branch, task summary, current status)
- Live updates as Claude edits, tests, builds, or thinks
- Clear visual distinction between active work and idle waiting

<!-- screenshot: same panes after 30 seconds, showing status transitions (Testing → Tests passed, Building → Running) -->

## Tips

- Use `--no-dynamic` for a clean, unmoving title (e.g., for screenshots or when you want a quiet terminal)
- Session titles are searchable—keep them descriptive
- Keep branch names in your title for quick context (auto-title does this automatically)
- If a title has spaces, quote it: `ccp "My feature work"`
