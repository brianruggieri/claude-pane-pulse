# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Claude flag passthrough: `ccp` now forwards any Claude flag directly to the `claude` CLI.
  Common flags supported: `-c/--continue`, `-r/--resume [ID]`, `--model`, `--permission-mode`,
  `--effort`, `--dangerously-skip-permissions`, `--worktree`, `--from-pr`, `--add-dir`,
  `--allowedTools`, `--disallowedTools`, `--mcp-config`, `--ide`, `--debug`, `--verbose`.
  Unknown `-*` flags are also forwarded. Use `--` for explicit passthrough.
- Welcome status: on startup, the title bar shows `👋 Welcome back, <FirstName>` (from
  `git config user.name`, fallback `$USER`) until the first user prompt fires.
- `--goto TITLE` flag: resume a previous `ccp` session by jumping to its saved working directory.
  (Renamed from `--continue` to avoid conflict with Claude's own `-c/--continue`.)

### Changed
- `--continue TITLE` renamed to `--goto TITLE` (session directory restore).
- `extract_context()` removed from `lib/monitor.sh` — status detection now handled entirely
  by `hook_runner.sh` via structured Claude Code hook events.
- 12 legacy kebab-case mode aliases removed from `hook_runner.sh` (never invoked in production;
  all events route via `event <EventName>`).

## [1.0.0] - 2026-03-01

### Added
- Initial release of Claude Code Pulse
- `ccp` command-line tool for dynamic terminal title management
- Dynamic status updates with animated progress indicators (`.`, `..`, `...`)
- Priority-based status system — errors always bubble to top
- Status icons: 🔨 Building, 🧪 Testing, ✅ Tests passed, ❌ Tests failed,
  💾 Committed, ⬆️ Pushing, 📦 Installing, 💭 Thinking, 🐛 Error, 💤 Idle,
  🐳 Docker, 🔀 Merging
- Auto-detection of title from git branch patterns:
  - `pr/89-fix-auth` → `PR #89 - fix auth`
  - `issue/12-refactor-api` → `Issue #12 - refactor api`
  - `feature/new-login` → `Feature: new login`
- Quick format helpers: `--pr`, `--issue`, `--feature`, `--bug`, `--refactor`
- Session tracking with `jq` — save and resume by title
- `--list` to view active sessions
- `--continue TITLE` to resume a previous session
- `--no-dynamic` flag for static title (no monitoring)
- Support for iTerm2, Terminal.app, tmux, WezTerm
- `install.sh` — interactive installer with PATH setup
- `uninstall.sh` — clean removal tool
- Comprehensive documentation in `docs/`
- GitHub Actions CI (shellcheck + tests)
- Issue templates and PR template

[Unreleased]: https://github.com/brianruggieri/claude-code-pulse/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/brianruggieri/claude-code-pulse/releases/tag/v1.0.0
