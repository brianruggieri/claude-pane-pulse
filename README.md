# **C**laude **C**ode **P**ane-Pulse &nbsp;`ccp`

> Dynamic terminal titles for Claude Code — see what each agent is actually doing at a glance

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/macOS-Sonoma+-blue.svg)](https://www.apple.com/macos/)
[![Bash](https://img.shields.io/badge/bash-3.2+-green.svg)](https://www.gnu.org/software/bash/)

**C**laude **C**ode **P**ane-Pulse (`ccp`) automatically updates your terminal pane titles to show real-time status of your Claude Code sessions — building, testing, pushing, and more — so you always know what each agent is working on at a glance.

## ✨ Features

- **🎬 Animated Status Updates** - Building..., Testing..., Pushing... with live progress dots
- **📊 Priority-Based Display** - Errors always show first, then active work, then completions
- **🔍 Auto-Detection** - Reads git branch names to auto-generate titles (PR #89, Issue #12, etc.)
- **💾 Session Tracking** - Resume previous sessions with `--continue`
- **⚡ Zero Config** - Works out of the box on iTerm2 and Terminal.app
- **🎯 Smart Context** - Shows what matters: tests passing, builds failing, commits pushed

## 🚀 Quick Start

```bash
# Install
git clone https://github.com/brianruggieri/claude-pane-pulse.git
cd claude-pane-pulse
./install.sh

# Use with auto-detection
ccp --auto-title

# Or specify manually
ccp "PR #89 - Fix auth bug"

# Quick formats
ccp --pr 89 "Fix auth bug"
ccp --feature "New login flow"
ccp --bug "Fix crash on startup"
```

## 📦 Installation

### Prerequisites

- **macOS** Sonoma or later (may work on earlier versions)
- **bash** 3.2+ (pre-installed on macOS)
- **jq** - Install with: `brew install jq`
- **Claude Code CLI** - See [claude.ai](https://claude.ai)

### Install

```bash
git clone https://github.com/brianruggieri/claude-pane-pulse.git
cd claude-pane-pulse
./install.sh
```

This installs `ccp` to `~/bin/` and adds it to your PATH.

## 📖 Usage

### Basic Commands

```bash
# Auto-detect from git branch
ccp --auto-title

# Manual title
ccp "Working on authentication"

# With directory
ccp "PR #89" ~/projects/my-app

# List active sessions
ccp --list

# Resume previous session
ccp --continue "PR #89"
```

### Quick Formats

```bash
ccp --pr 89 "Fix memory leak"       # → PR #89 - Fix memory leak
ccp --issue 12 "Refactor API"       # → Issue #12 - Refactor API
ccp --feature "OAuth integration"   # → Feature: OAuth integration
ccp --bug "Login crash"             # → Bug: Login crash
ccp --refactor "Clean up code"      # → Refactor: Clean up code
```

### Dynamic Status Updates

The title automatically updates to show what Claude Code is doing:

```
Initial:     "PR #89 - Fix auth bug"
Building:    "PR #89 | 🔨 Building..."
Testing:     "PR #89 | 🧪 Testing..."
Passed:      "PR #89 | ✅ Tests passed"
Committing:  "PR #89 | 💾 Committed"
Pushing:     "PR #89 | ⬆️ Pushing..."
Idle:        "PR #89 | 💤 Idle"
```

Status surface profiles:

- `quiet` (default): high-signal statuses only
- `verbose`: full lifecycle surface (session/worktree/subagent/config events)

```bash
# Default (quiet)
ccp "PR #89 - Fix auth bug"

# Full lifecycle statuses
ccp --status-profile verbose "PR #89 - Fix auth bug"
```

### Status Icons

| Icon | Status | Priority |
|------|--------|----------|
| 🐛 | Error | Highest |
| ❌ | Tests failed | High |
| ⏸️ | Awaiting approval | High |
| 🙋 | Input needed | High |
| 🔨 | Building | Active |
| 🧪 | Testing | Active |
| 📦 | Installing | Active |
| ⬆️ | Pushing | Active |
| ⬇️ | Pulling | Active |
| 🔀 | Merging | Active |
| ✅ | Tests passed | Complete |
| 💾 | Committed | Complete |
| 🏁 | Completed | Complete |
| 💭 | Thinking | Background |
| 💤 | Idle | Lowest |

Verbose-only examples: `🚀 Session started`, `🧠 Compacting`, `🤖 Subagent started`, `👥 Teammate idle`, `⚙️ Config changed`, `🌿 Worktree created`.

## 🎯 Multi-Pane Workflow

Perfect for running multiple Claude Code instances:

Launch multiple sessions:
```bash
# Pane 1
ccp --pr 89 "Fix auth"

# Pane 2  
ccp --issue 12 "Refactor"

# Pane 3
ccp --feature "OAuth"

# Pane 4
ccp --bug "Login crash"
```

## 🛠️ Configuration

### Disable Dynamic Updates

```bash
ccp --no-dynamic "PR #89"
```

### Session Management

```bash
# List all active sessions
ccp --list

# Resume a previous session
ccp --continue "PR #89"
```

### Git Integration

Auto-detection works with these branch patterns:

```
pr/89-fix-auth          → PR #89 - fix auth
pull/89-fix-auth        → PR #89 - fix auth
issue/12-refactor-api   → Issue #12 - refactor api
fix/12-refactor-api     → Issue #12 - refactor api
bug/12-refactor-api     → Issue #12 - refactor api
feature/new-login       → Feature: new login
main                    → Branch: main
```

## 📚 Documentation

- [Installation Guide](docs/installation.md)
- [Usage Guide](docs/usage.md)
- [Dynamic Titles](docs/dynamic-titles.md)
- [Contributing](CONTRIBUTING.md)

## 🤝 Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/claude-pane-pulse.git

# Create feature branch
git checkout -b feature/amazing-feature

# Commit changes
git commit -m 'feat: add amazing feature'

# Push and create PR
git push origin feature/amazing-feature
```

## 📝 License

MIT © Brian Ruggieri - see [LICENSE](LICENSE)

## 🙏 Acknowledgments

- Built for [Claude Code](https://code.claude.com/) by Anthropic
- Inspired by the need for better multi-agent visibility
- Thanks to the shell scripting community

## 📮 Contact

- **Issues**: [GitHub Issues](https://github.com/brianruggieri/claude-pane-pulse/issues)
- **Email**: brianruggieri@gmail.com

---

**Star ⭐ this repo if you find it useful!**
