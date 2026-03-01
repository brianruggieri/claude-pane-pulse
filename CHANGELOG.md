# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-03-01

### Added
- Initial release of Claude Pane Pulse
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

[Unreleased]: https://github.com/brianruggieri/claude-pane-pulse/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/brianruggieri/claude-pane-pulse/releases/tag/v1.0.0
