# **C**laude **C**ode **P**ulse &nbsp;`ccp`

[![CI](https://github.com/brianruggieri/claude-code-pulse/actions/workflows/ci.yml/badge.svg)](https://github.com/brianruggieri/claude-code-pulse/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-Sonoma+-blue.svg)](https://www.apple.com/macos/)
[![Bash](https://img.shields.io/badge/bash-3.2+-green.svg)](https://www.gnu.org/software/bash/)

Running multiple Claude Code agents in split panes? Without ccp every pane shows a generic title — you have to read the terminal output to know what's happening in each one. With ccp, the title bar tells you.

![Four iTerm2 split panes with ccp — each title bar independently showing project, branch, task, and live status](docs/screenshots/demo-4pane.gif)

Each pane updates on its own schedule. When one agent finishes and commits, that pane flips to `💾 Committed`. The others keep going.

```
auth-service (feat/oauth2)      | Fix JWT expiry | ✅ Tests passed
dashboard-ui (fix/layout-shift) | Audit tests    | 🧪 Testing
data-pipeline (feat/embeddings) | Fix TS errors  | 🔨 Building
infra-tools (chore/tf-up)       | Plan Terraform | ⬆️ Pushing
```

### Before ccp

Generic titles. No idea what's happening in each pane.

![Before: four iTerm2 split panes showing generic "project — claude" titles with no task or status information](docs/screenshots/before.png)

### With ccp

Each pane title is independent — project, branch, task, and live status updated in real time.

![After: four iTerm2 split panes with ccp titles showing "project (branch) | task | status" — Editing, Testing, Building, Reading](docs/screenshots/after.png)

> **Per-pane titles:** ccp writes to OSC 1 (the per-pane icon title) so every split pane updates independently. No two panes share a title. See [Terminal Support](#terminal-support) for other terminals.

## Features

- **Auto-title from git**. `ccp` reads the current branch and generates a clean title automatically. `pr/89-fix-auth` becomes `PR #89 - fix auth`, `feature/new-login` becomes `Feature: new login`, and so on.
- **Live status updates**. The title updates as Claude works. Editing, testing, building, pushing, all of it. Branch name refreshes live too — if Claude runs `git checkout`, the title reflects the new branch within one polling cycle.
- **Idle phrase cycling**. 10 different idle phrases cycle on each conversation turn so you can see at a glance whether a pane just went idle or has been sitting for a while.
- **Welcome on startup**. Shows `👋 Welcome back, <name>` when you open a pane, before you've typed anything.
- **Priority-based display**. Errors always show first. Completions (tests passed, committed) immediately override whatever else is showing.
- **Hook-based**. Uses Claude Code's own hook events for status. No output parsing, no regex, just structured JSON.
- **Session tracking**. Save and re-open sessions by title with `--goto`.
- **AI task summaries**. `--ai-context` refines each turn into a clean 3-5 word label shown in the title. Uses claude-haiku to summarize after each turn completes. Opt-in only.
- **Git commit context**. When Claude commits, the commit subject line automatically appears as the task context — no flag needed.
- **Context sanitization**. Shell prompt prefixes (`$`, `%`, `user@host`, etc.) are automatically stripped from pasted terminal content before building the title.
- **Tested on iTerm2, Terminal.app, and tmux**. Detection logic for WezTerm, Ghostty, and Kitty is included but unverified.
- **Full Claude passthrough**. Every Claude Code flag works exactly as expected.

## Quick Start

```bash
# Install
git clone https://github.com/brianruggieri/claude-code-pulse.git
cd claude-code-pulse
./install.sh

# Auto-detect title from your current branch
ccp

# Or give it a custom title
ccp "fixing the login bug"

# Quick formats
ccp --pr 89 "Fix auth bug"
ccp --feature "New login flow"
ccp --bug "Fix crash on startup"

# Go back to a previous session
ccp --goto "PR #89"

# Claude flags pass straight through
ccp -c                                  # resume last conversation
ccp --model opus "My task"
ccp --permission-mode bypassPermissions

# AI-summarized task labels in the title (opt-in, uses your subscription)
ccp --ai-context "Fix the auth bug"

# Debug mode — structured JSONL logging + live Pulse Monitor (iTerm2: auto-opens in split pane)
ccp --debug-ccp "Fix the auth bug"
```

> See [AI Task Summaries](#ai-task-summaries) for the `--ai-context` flag.

## Installation

**Prerequisites:**
- macOS Sonoma or later
- bash 3.2+ (ships with macOS)
- jq: `brew install jq`
- Claude Code CLI: [claude.ai](https://claude.ai)

```bash
git clone https://github.com/brianruggieri/claude-code-pulse.git
cd claude-code-pulse
./install.sh
```

Installs to `~/.local/share/ccp/` and symlinks `~/bin/ccp` and `~/bin/ccp-watch`. If `~/bin` is not already in your `$PATH`, the installer prints the one line to add — it does not modify your shell profile. No sudo, no system-wide changes, no telemetry. Network calls only to Anthropic — and only if you opt in to `--ai-context`.

## Usage

### Auto-title (the default)

Run `ccp` with no arguments. It reads the branch name and builds a title:

| Branch | Title |
|--------|-------|
| `pr/89-fix-auth` | `PR #89 - fix auth` |
| `pull/89-fix-auth` | `PR #89 - fix auth` |
| `issue/12-refactor-api` | `Issue #12 - refactor api` |
| `fix/12-crash` | `Issue #12 - crash` |
| `bug/12-crash` | `Issue #12 - crash` |
| `feature/new-login` | `Feature: new login` |
| `main` or anything else | `project-name (branch)` |

No git repo? Falls back to the current directory name.

### Custom title

```bash
ccp "fixing the login bug"
```

### Quick format helpers

```bash
ccp --pr 89 "Fix memory leak"        # PR #89 - Fix memory leak
ccp --issue 12 "Refactor API"        # Issue #12 - Refactor API
ccp --feature "OAuth integration"    # Feature: OAuth integration
ccp --bug "Login crash on iOS"       # Bug: Login crash on iOS
ccp --refactor "Clean up auth"       # Refactor: Clean up auth
```

### Working directory

```bash
ccp "PR #89" ~/projects/my-app
```

`ccp` will `cd` into that directory before launching Claude.

## Title Lifecycle

```
Startup     my-app (main) | 👋 Welcome back, Brian
-> type     my-app (main) | fix the login bug | 💤 Idle
-> reading  my-app (main) | fix the login bug | 📖 Reading
-> editing  my-app (main) | fix the login bug | ✏️ Editing
-> testing  my-app (main) | fix the login bug | 🧪 Testing
-> passed   my-app (main) | fix the login bug | ✅ Tests passed
-> commit   my-app (main) | fix the login bug | 💾 Committed
-> pushing  my-app (main) | fix the login bug | ⬆️ Pushing
-> idle     my-app (main) | fix the login bug | ☕ Recharging
```

**Startup.** Before you send anything, the pane shows the welcome message.

**Task summary.** Appears as soon as you send a message. Shows the first words of your prompt right away, then updates to a cleaner 3-5 word summary if `--ai-context` is on.

**Status.** Updates based on what Claude is actually doing. When Claude finishes, the status clears to an idle phrase.

**Idle phrases.** Each time Claude finishes responding, the idle phrase advances. After seeing `☕ Recharging` you know the pane just went idle. After seeing `🫡 Standing by` you know it's been a while.

`💤 Idle` · `☕ Recharging` · `🧘 Centering` · `🎯 Ready` · `🫡 Standing by` · `💡 Listening` · `🌿 At rest` · `👀 Watching` · `🌊 Drifting` · `✨ Floating`

![Single pane cycling through ccp statuses — Editing, Testing, Tests passed, Committed, Pushing, Idle](docs/screenshots/status-lifecycle.apng)

## Status Reference

### Both profiles

| Icon | Status | What triggered it | Priority |
|------|--------|-------------------|----------|
| 🐛 | Error | Any tool fails | 100 |
| ❌ | Tests failed | Test command exits non-zero | 90 |
| ⏸️ | Awaiting approval | Permission request | 88 |
| 🙋 | Input needed | Notification requires action | 85 |
| 🔨 | Building | webpack, tsc, cargo build, make, gradle, etc. | 80 |
| 🧪 | Testing | jest, vitest, pytest, mocha, rspec, go test, etc. | 80 |
| 📦 | Installing | npm install, pip install, yarn add, cargo add | 80 |
| ⬆️ | Pushing | git push | 75 |
| ⬇️ | Pulling | git pull | 75 |
| 🔀 | Merging | git merge | 75 |
| 🔀 | Rebasing | git rebase | 75 |
| 🍒 | Cherry-picking | git cherry-pick | 75 |
| 🤖 | Delegating | Task or Agent tool use | 70 |
| 🐳 | Docker | Any docker command | 70 |
| ✏️ | Editing | Edit, Write, MultiEdit, NotebookEdit | 65 |
| ✅ | Tests passed | `N tests passed` in Bash output | 60 |
| 💾 | Committed | git commit output | 60 |
| 🏁 | Completed | TaskCompleted or terminal SessionEnd | 60 |
| 📖 | Reading | Read, Glob, Grep | 55 |
| 🌐 | Browsing | WebFetch, WebSearch | 55 |
| 🖥️ | Running | Any other Bash command | 55 |
| 📤 | Sending | SendMessage tool | 55 |
| 🔧 | Working | Skill tool or unclassified tool | 55 |
| 📡 | Monitoring | Background agents running while Claude is idle | 20 |

Higher priority always wins. The one exception: completion events (✅, 💾, 🏁, ❌, 🐛) override any active status immediately, regardless of priority.

### Verbose-only

With `--status-profile verbose`, lifecycle events also show up:

| Icon | Status | Event | Priority |
|------|--------|-------|----------|
| 🚀 | Session started | SessionStart | 52 |
| 🧠 | Compacting | PreCompact | 52 |
| 🤖 | Subagent started | SubagentStart | 52 |
| ✅ | Subagent finished | SubagentStop | 52 |
| 👥 | Teammate idle | TeammateIdle | 52 |
| ⚙️ | Config changed | ConfigChange | 52 |
| 🔔 | *EventName* | Any other event | 52 |

## Status Profiles

```bash
# Default: high-signal statuses only
ccp "PR #89"

# All events including lifecycle, subagents, worktrees, config
ccp --status-profile verbose "PR #89"

# Set a default in your shell
export CCP_STATUS_PROFILE=verbose
```

Precedence: `--status-profile` flag > `CCP_STATUS_PROFILE` env var > `quiet` default.

## AI Task Summaries

With `--ai-context`, ccp generates a clean 3-5 word label for each conversation turn. Without it, the first words of your prompt show as-is.

How it works: when Claude finishes responding, the Stop hook sends a truncated excerpt of the response to claude-haiku for a 3-5 word summary. The summary overwrites the first-5-words placeholder in the title.

```bash
# Enable AI summaries (opt-in, uses your subscription)
ccp --ai-context "PR #89 - Fix auth"

# Always on, via environment variable
export CCP_ENABLE_AI_CONTEXT=true
```

See [docs/ai-context.md](docs/ai-context.md) for the full details.

## Claude Flag Passthrough

Every Claude Code flag passes straight through to `claude`:

```bash
ccp -c                                      # resume last conversation
ccp -r abc-123                              # resume by session ID
ccp --model opus "My task"
ccp --model claude-sonnet-4-6 "My task"
ccp --permission-mode bypassPermissions
ccp --permission-mode acceptEdits
ccp --effort high "Big refactor"
ccp -w feat-login "Fix login"               # create git worktree
ccp --system-prompt "Be terse" "My task"
ccp --append-system-prompt "Use TypeScript"
ccp --add-dir ~/shared/lib
ccp --allowedTools Bash Edit Read
ccp --mcp-config ./mcp.json
ccp --dangerously-skip-permissions
ccp "My task" -- --resume abc123            # explicit passthrough with --
```

Any unrecognized `-*` flag is also forwarded, so new Claude flags just work.

### Full forwarded flag list

**No value:**
`-c` / `--continue`, `--dangerously-skip-permissions`, `--allow-dangerously-skip-permissions`, `--verbose`, `--ide`, `--no-ide`, `--fork-session`, `--chrome`, `--no-chrome`, `--no-session-persistence`, `--include-partial-messages`, `--replay-user-messages`, `--strict-mcp-config`, `--mcp-debug`

**Required value:**
`--model`, `--permission-mode`, `--effort`, `--system-prompt`, `--append-system-prompt`, `--debug-file`, `--session-id`, `--output-format`, `--input-format`, `--settings`, `--setting-sources`, `--fallback-model`, `--max-budget-usd`, `--json-schema`, `--agent`

**Optional value:**
`-r` / `--resume [ID]`, `--from-pr [VALUE]`, `-w` / `--worktree [NAME]`, `-d` / `--debug [FILTER]`

**One or more values:**
`--add-dir`, `--allowedTools` / `--allowed-tools`, `--disallowedTools` / `--disallowed-tools`, `--mcp-config`, `--tools`, `--betas`, `--plugin-dir`, `--file`, `--agents`

## Session Management

```bash
# List active sessions
ccp --list

# Jump back to a previous session's directory
ccp --goto "auth"           # substring match
ccp --goto "PR #89"
```

Sessions are saved to `~/.config/claude-code-pulse/sessions.json` and cleaned up on exit.

`--goto` jumps to the session's saved working directory and launches Claude there. It doesn't resume a conversation. For that, use Claude's own flags:

```bash
ccp -c                      # resume last conversation
ccp --resume abc-123        # resume by session ID
```

## Debugging & Diagnostics

### `--debug-ccp`

```bash
ccp --debug-ccp "PR #89 - Fix auth"

# Always on via environment variable
export CCP_DEBUG=true
```

Enables structured JSONL logging. Each hook event, status change, and AI summary is written as a JSON line to:

```
~/.config/claude-code-pulse/logs/debug.<timestamp>.<pid>.jsonl
```

Old log files from dead sessions are pruned automatically on startup.

**In iTerm2**, `--debug-ccp` also auto-opens the Pulse Monitor in a horizontal split pane. You don't need to run `ccp-watch` manually — it launches automatically and connects to the session log.

### `ccp-watch` — Pulse Monitor

`ccp-watch` is a live debug monitor that streams events from a JSONL log and flags issues in real time.

```bash
# Watch the latest debug log (auto-detects)
ccp-watch

# Watch a specific log file
ccp-watch ~/.config/claude-code-pulse/logs/debug.20260301-120000.12345.jsonl

# List all available debug logs
ccp-watch --list
```

What it monitors:

| Check | What it catches |
|-------|----------------|
| **Status changes** | Every status transition as it happens |
| **AI summaries** | Delivery confirmation (`N/N delivered`) |
| **Stuck detection** | Status held >45s before changing |
| **Event gaps** | Silence between events >120s |
| **Status mismatches** | Tool fired but wrong status was set |
| **System messages** | `<task-notification>` and `<context>` payloads filtered from title |
| **Title anomalies** | Malformed title strings |
| **Session summary** | Total events, errors, and summary delivery rate at session end |

The pane title updates to `🩺 Pulse Monitor — <project>` when a session connects.

### JSONL event format

Each line in the debug log is a JSON object:

```json
{"ts":"2026-03-01T12:00:00.000Z","src":"session","pid":"12345","event":"session_start","title":"PR #89 - Fix auth","dir":"/my/project","profile":"quiet","ai_context":"false"}
{"ts":"2026-03-01T12:00:01.000Z","src":"hook","mode":"pre-tool","pid":"12345","event":"status_set","status":"✏️ Editing","tool":"Edit"}
{"ts":"2026-03-01T12:00:02.000Z","src":"hook","mode":"post-tool","pid":"12345","event":"status_set","status":"✅ Tests passed"}
{"ts":"2026-03-01T12:00:03.000Z","src":"session","pid":"12345","event":"session_end"}
```

Key fields: `ts` (ISO 8601), `src` (`session` or `hook`), `mode` (hook mode), `pid`, `event`, `status`, `tool`, `summary`.

## Terminal Support

Tested on:

| Terminal | Notes |
|----------|-------|
| **iTerm2** | Per-pane title (OSC 1). Each split pane updates independently. The primary target. |
| **Terminal.app** | Window title (OSC 2). |
| **tmux 2.9+** | Per-pane title via `select-pane -T` plus OSC 1 passthrough. |
| **tmux < 2.9** | Window rename via `rename-window`. No per-pane title API. |

Detection logic for WezTerm, Ghostty, and Kitty exists in `lib/title.sh` but these have not been verified. If you use one of these terminals, feedback is welcome.

## Multi-Pane Workflow

Open four panes, run a session in each:

```bash
ccp --pr 89 "Fix auth"
ccp --issue 12 "API tests"
ccp --feature "OAuth"
ccp --bug "Login crash"
```

Each pane title updates on its own:

```
my-app (pr/89-fix-auth)      | fix auth   | ✏️ Editing
my-app (issue/12-api-tests)  | api tests  | 🧪 Testing
my-app (feat-oauth)          | oauth      | ✅ Tests passed
my-app (bug/login-crash)     | login bug  | ⬆️ Pushing
```

![iTerm2 4-pane split with ccp — each pane showing its own live project, branch, task, and status](docs/screenshots/after.png)

## Options Reference

### ccp options

| Option | Description |
|--------|-------------|
| `TITLE` | Task title (first positional arg) |
| `DIRECTORY` | Working directory (second positional arg, must be an existing path) |
| `--pr N DESC` | Quick format: `PR #N - DESC` |
| `--issue N DESC` | Quick format: `Issue #N - DESC` |
| `--feature DESC` | Quick format: `Feature: DESC` |
| `--bug DESC` | Quick format: `Bug: DESC` |
| `--refactor DESC` | Quick format: `Refactor: DESC` |
| `--auto-title` | Auto-detect title from git branch (this is the default) |
| `--no-dynamic` | Static title only, no live updates |
| `--status-profile quiet\|verbose` | Which events to surface (default: `quiet`) |
| `--ai-context` | Summarize each turn into a 3-5 word title label (opt-in, uses your subscription) |
| `--debug-ccp` | Structured JSONL debug logging to `~/.config/claude-code-pulse/logs/`; auto-opens Pulse Monitor in iTerm2 |
| `--goto TITLE` | Re-open a previous session by title |
| `--list`, `-l` | List active ccp sessions |
| `--help`, `-h` | Show help |
| `--version`, `-v` | Show version |
| `--` | Everything after this goes directly to Claude |
| any `-*` flag | Unknown flags are forwarded to Claude |

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CCP_STATUS_PROFILE` | `quiet` | Default status profile |
| `CCP_ENABLE_AI_CONTEXT` | `false` | Always-on AI context summarization |
| `CCP_DEBUG` | `false` | Always-on structured JSONL debug logging |

## Documentation

- [Usage Guide](docs/usage.md)
- [Dynamic Titles](docs/dynamic-titles.md)
- [Hook Integration](docs/hooks.md)
- [AI Context Summarization](docs/ai-context.md)
- [Debugging & Diagnostics](#debugging--diagnostics)
- [Installation Guide](docs/installation.md)
- [Contributing](CONTRIBUTING.md)

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and guidelines.

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/claude-code-pulse.git

# Create feature branch
git checkout -b feature/amazing-feature
git commit -m 'feat: add amazing feature'
git push origin feature/amazing-feature
```

## License

MIT © Brian Ruggieri. See [LICENSE](LICENSE).

## Acknowledgments

Built for [Claude Code](https://code.claude.com/) by Anthropic. Inspired by the need to keep track of what's happening across multiple concurrent agents.

---

**Star ⭐ this repo if you find it useful!**
