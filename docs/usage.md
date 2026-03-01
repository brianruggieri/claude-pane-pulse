# Usage Guide

## Basic Usage

### Start with a title

```bash
ccp "PR #89 - Fix authentication bug"
```

This sets your terminal title to `PR #89 - Fix authentication bug`, then launches Claude Code with dynamic title monitoring enabled.

### Auto-detect from git branch

```bash
ccp --auto-title
```

Reads the current git branch and constructs a title automatically:

| Branch | Title |
|--------|-------|
| `pr/89-fix-auth` | `PR #89 - fix auth` |
| `issue/12-refactor-api` | `Issue #12 - refactor api` |
| `feature/new-login` | `Feature: new login` |
| `fix/12-crash` | `Issue #12 - crash` |
| `main` | `Branch: main` |

If no git repo is found: `Dev: <directory-name>`

### Let ccp prompt you

Run `ccp` with no arguments — it auto-detects a title and lets you accept or override it:

```
Auto-detected: Branch: main
Press Enter to use this, or type custom title: PR #89 - Fix auth
```

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

### Resume a session

```bash
ccp --continue "PR #89"
```

Searches for a session whose title contains `"PR #89"` and resumes in that directory.

## Options Reference

| Option | Description |
|--------|-------------|
| `TITLE` | Set the pane title manually |
| `DIRECTORY` | Working directory for Claude Code |
| `--pr N DESC` | Quick format: `PR #N - DESC` |
| `--issue N DESC` | Quick format: `Issue #N - DESC` |
| `--feature DESC` | Quick format: `Feature: DESC` |
| `--bug DESC` | Quick format: `Bug: DESC` |
| `--refactor DESC` | Quick format: `Refactor: DESC` |
| `--auto-title` | Detect title from git branch |
| `--no-dynamic` | Static title only — disable monitoring |
| `--continue TITLE` | Resume session by title search |
| `--list`, `-l` | List all saved sessions |
| `--help`, `-h` | Show help |
| `--version`, `-v` | Show version |

## Multi-Pane Workflow

The primary use case — running multiple Claude Code sessions in parallel:

```
┌─────────────────────────┬─────────────────────────┐
│  PR #89 - Fix auth      │  Issue #12 - API tests  │
│  🧪 Testing...          │  ✅ Tests passed         │
├─────────────────────────┼─────────────────────────┤
│  Feature: OAuth         │  Bug: Login crash        │
│  💭 Thinking            │  🐛 Error                │
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

See `examples/multi-pane-setup.sh` for an iTerm2 automation script.

## Tips

- Use `--no-dynamic` when you want a clean, unmoving title (e.g., for screenshots)
- Session titles are searchable — keep them descriptive
- Branch names with numbers trigger PR/issue formatting automatically
- If a title has spaces, quote it: `ccp "My feature work"`
