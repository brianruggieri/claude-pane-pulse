# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-03-05

### Added
- **`--ai-context-strategy haiku|inline`** — choose how AI task summaries are generated.
  - `haiku` (default): fires a detached `claude-haiku` call in the background. Fully
    invisible to the user. Uses your subscription (one Haiku call per prompt).
  - `inline`: piggybacks on the already-outgoing Claude session via `--append-system-prompt`.
    Zero extra API calls, zero extra subscription cost. Claude emits one `echo` as its first
    tool use per session — a visible but minor trade-off for cost-conscious users.
- **`CCP_AI_CONTEXT_STRATEGY`** env var — set default strategy in your shell profile
  (`haiku` or `inline`). CLI flag takes precedence.
- **12 new tests** — marker extraction, whitespace/quote handling, strategy gating (positive
  and negative cases), CLI validation for both strategies.

### Fixed
- Inline summary extraction is now correctly gated on `CCP_AI_CONTEXT_STRATEGY=inline`.
  Previously the `CCP_TASK_SUMMARY:` marker was detected unconditionally, meaning a
  `grep` or `cat` of any file containing that string could silently overwrite the title.

### Docs
- `docs/ai-context.md` — per-strategy sections for cost, privacy, and data flow.
- `docs/inline-context-spec.md` — full architecture spec, data flow diagram, failure modes,
  and trade-off matrix.

## [1.0.0] - 2026-03-04

### Added
- **Hooks-only architecture** — all status detection goes through Claude Code's official
  hook system (PreToolUse, PostToolUse, UserPromptSubmit, Stop). No PTY output parsing.
- **15+ granular status states** with emoji indicators and priority system:
  - 🐛 Error (100), ❌ Tests failed (90), ⏸️ Awaiting approval (88), 🙋 Input needed (85)
  - 🔨 Building, 🧪 Testing, 📦 Installing (80), ⬆️ Pushing, ⬇️ Pulling, 🔀 Merging (75)
  - 💭 Thinking, 🐳 Docker, 🤖 Delegating (70), ✏️ Editing (65)
  - ✅ Tests passed, 💾 Committed, 🏁 Completed (60 — always override active states)
  - 📖 Reading, 🌐 Browsing, 🖥️ Running (55), 💤 Idle (10)
- **Animated spinner** — Claude Code's native 10-frame ping-pong sequence
  (`·✻✽✶✳✢✳✶✽✻`) prepended to the title string; 0.15s/frame on bash 4+, 1s on bash 3.2/tmux.
- **Title format**: `<spinner> <project> (<branch>) | <task-summary> | <status>`
- **Session tracking** — `jq`-backed session persistence in
  `~/.config/claude-code-pulse/sessions.json`; `--list` to view active sessions.
- **`--goto TITLE`** — resume a previous session by jumping to its saved working directory.
- **Welcome status** — on startup shows `👋 Welcome back, <FirstName>` (from
  `git config user.name`, fallback `$USER`) until the first user prompt fires.
- **Personable idle rotation** — when idle, cycles through
  `💤 Idle`, `☕ Recharging`, `🧘 Centering`, `🎯 Ready`, `🫡 Standing by`,
  `💡 Listening`, `🌿 At rest`, `👀 Watching`, `🌊 Drifting`, `✨ Floating`.
- **Claude flag passthrough** — any Claude CLI flag passed to `ccp` is forwarded directly.
  Supported: `-c/--continue`, `-r/--resume`, `--model`, `--permission-mode`, `--effort`,
  `--dangerously-skip-permissions`, `--worktree`, `--from-pr`, `--add-dir`,
  `--allowedTools`, `--disallowedTools`, `--mcp-config`, `--ide`, `--debug`, `--verbose`.
  Use `--` for explicit passthrough of unknown flags.
- **`--ai-context`** (opt-in) — background prompt summarization via `claude-haiku` distills
  user prompts into a 3–5 word title label. Also enabled via `CCP_ENABLE_AI_CONTEXT=true`.
- **Size-aware title truncation** — title bar adapts to actual pane width, prioritizing
  branch name when space is tight.
- **Fast animation pulse** — hook polling decoupled from animation tick rate.
  Animation runs at 0.15s intervals; file reads gated to 1/sec via `$SECONDS` builtin
  (no subprocess forks). Total overhead ~0.3% of a core.
- **Non-blocking FIFO** — `O_NONBLOCK` on the monitor FIFO prevents PTY write delays from
  causing iTerm2 escape-sequence rendering artifacts.
- **PID-keyed hooks** — hook entries in `.claude/settings.local.json` are tagged with the
  session PID so multiple `ccp` sessions coexist cleanly. Stale entries (dead PIDs) are
  purged on each new launch.
- **FIFO liveness idle suppression** — if FIFO has data, idle is suppressed; idle only
  declared after 60s of FIFO silence (fallback when hooks are unavailable).
- **Bash 3.2 compatibility** — no `declare -A`, no `${var,,}`, no `mapfile`.
  Works on stock macOS bash without Homebrew upgrade.
- **iTerm2 split-pane support** — writes OSC 1 (per-pane title) for iTerm2,
  OSC 2 (window title) for Terminal.app; clears OSC 2 in iTerm2 to avoid shared-title
  conflicts across panes.
- **tmux support** — `tmux rename-window` integration; fast ticks excluded from tmux
  (avoids 7 subprocess forks/sec).
- **`install.sh`** — installs to `~/.local/share/ccp/`, symlinks `~/bin/ccp`.
- **`uninstall.sh`** — clean removal with optional session data purge.
- **Comprehensive test suite** — 114 tests covering spinner frames, title escapes,
  session lifecycle, hook injection/teardown, status priority, and event routing.
- **GitHub Actions CI** — shellcheck + unit tests + e2e + install smoke test.
- **Docs** — `docs/` directory with `usage.md`, `hooks.md`, `dynamic-titles.md`,
  `ai-context.md`, `CONTRIBUTING.md`.
- **SECURITY.md** — responsible disclosure policy.
- **Issue templates** (bug report + feature request) and PR template.

[1.1.0]: https://github.com/brianruggieri/claude-code-pulse/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/brianruggieri/claude-code-pulse/releases/tag/v1.0.0
