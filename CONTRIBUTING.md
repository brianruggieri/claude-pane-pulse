# Contributing to Claude Pane Pulse

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
│   └── ccp              # Main executable
├── lib/
│   ├── core.sh          # Shared constants, logging, dependency checks
│   ├── title.sh         # Terminal title management
│   ├── session.sh       # Session persistence (jq-backed)
│   └── monitor.sh       # Dynamic monitoring, status detection, animation
├── docs/                # Documentation
├── tests/
│   └── test-suite.sh    # Test suite (bash)
├── examples/            # Example scripts
├── .github/             # CI, issue templates, PR template
├── install.sh           # Installer
├── uninstall.sh         # Uninstaller
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
- `extract_context` pattern matching in `lib/monitor.sh`
- `auto_detect_title` branch name parsing in `bin/ccp`
- `set_title` output in `lib/title.sh`
- Session save/load/cleanup in `lib/session.sh`

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
