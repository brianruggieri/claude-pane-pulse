# Contributing to **C**laude **C**ode **P**ane-Pulse

Thank you for your interest in contributing! This guide covers everything you need to get started.

## Table of Contents

- [Development Setup](#development-setup)
- [Code Style](#code-style)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Reporting Bugs](#reporting-bugs)

## Development Setup

### Prerequisites

- macOS (Sonoma+ recommended)
- bash 3.2+ (pre-installed on macOS)
- jq: `brew install jq`
- shellcheck: `brew install shellcheck`
- Claude Code CLI: [claude.ai/code](https://claude.ai/code)

### Clone and run locally

```bash
git clone https://github.com/brianruggieri/claude-pane-pulse.git
cd claude-pane-pulse

# Run directly from source (no install needed for dev)
bash bin/ccp --help

# Or install for end-to-end testing
./install.sh
```

### Project structure

```
claude-pane-pulse/
├── bin/
│   └── ccp                  # Main executable
├── lib/
│   ├── core.sh              # Shared constants, logging, dependency checks
│   ├── title.sh             # Terminal title management
│   ├── session.sh           # Session persistence (jq-backed)
│   ├── monitor.sh           # Dynamic monitoring, animation, idle detection
│   ├── hooks.sh             # Hook setup/teardown lifecycle
│   ├── hook_runner.sh       # Hook event dispatch and status mapping
│   └── pty_wrapper.py       # Python PTY wrapper with SIGWINCH propagation
├── docs/                    # Documentation
├── tests/
│   └── test-suite.sh        # Test suite (bash)
├── .github/                 # CI, issue templates, PR template
├── install.sh               # Installer
├── uninstall.sh             # Uninstaller
├── CHANGELOG.md
├── LICENSE
└── README.md
```

## Code Style

This project follows the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) with a few additions:

- **Indentation:** 4 spaces (no tabs)
- **Quoting:** Always double-quote variable expansions: `"${var}"`, `"$var"`
- **Conditionals:** Use `[[ ]]` over `[ ]`
- **Functions:** Add a one-line comment describing each function
- **Compatibility:** Target bash 3.2+ (no `declare -A`, no `${var,,}`)
- **Shebang:** `#!/usr/bin/env bash`
- **Error handling:** `set -euo pipefail` in executable scripts
- **Exception:** `hook_runner.sh` uses `set -uo pipefail` (intentionally, no `-e`)
  because it must never exit early and block Claude Code's event dispatch

### ShellCheck

All shell files must pass shellcheck with no errors:

```bash
shellcheck bin/ccp lib/*.sh install.sh uninstall.sh
```

To disable a check (only when truly necessary), add an inline comment:
```bash
# shellcheck disable=SC2034
```

## Testing

Run the test suite:

```bash
bash tests/test-suite.sh
```

Tests cover:
- `hook_runner.sh` event dispatch and status mapping
- `animate_status` spinner sequence in `lib/monitor.sh`
- `set_title` escape sequence output in `lib/title.sh`
- Session save/find/cleanup lifecycle in `lib/session.sh`
- `setup_ccp_hooks` / `teardown_ccp_hooks` lifecycle in `lib/hooks.sh`

Set `CCP_DISABLE_PROMPT_DISTILL=1` when running tests to skip the claude-haiku
context summarization subprocess.

Add tests for any new features or bug fixes.

## Submitting Changes

1. Fork the repo and create a feature branch:
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. Make your changes and ensure:
   - `shellcheck bin/ccp lib/*.sh install.sh uninstall.sh` passes
   - `bash tests/test-suite.sh` passes
   - Documentation is updated if behavior changed

3. Commit using [Conventional Commits](https://www.conventionalcommits.org/):
   ```
   feat: add support for WezTerm title updates
   fix: handle empty branch name in auto-detect
   docs: clarify session tracking behavior
   test: add tests for git push detection
   ```

4. Push and open a pull request against `main`.

## Reporting Bugs

Use the [GitHub issue tracker](https://github.com/brianruggieri/claude-pane-pulse/issues).

Please include:
- macOS version
- Terminal (iTerm2, Terminal.app, tmux, etc.)
- bash version: `bash --version`
- Steps to reproduce
- Expected vs. actual behavior
- Any relevant output or screenshots
