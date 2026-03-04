# Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) in the project root for the full contributing guide.

## Quick Links

- [Development Setup](../CONTRIBUTING.md#development-setup)
- [Code Style](../CONTRIBUTING.md#code-style)
- [Testing](../CONTRIBUTING.md#testing)
- [Submitting Changes](../CONTRIBUTING.md#submitting-changes)
- [Reporting Bugs](../CONTRIBUTING.md#reporting-bugs)

## Architecture Overview

```
bin/ccp          Entry point — argument parsing, Claude Code launcher
lib/core.sh      Constants, colors, logging, dependency checks
lib/title.sh     set_title() and update_title_with_context()
lib/session.sh   Session persistence (JSON via jq)
lib/monitor.sh   Output parser, status extractor, title updater
```

Each `lib/*.sh` file is independently sourceable (guarded against double-sourcing) but is designed to be loaded together by `bin/ccp`.

## Key Design Decisions

**Named pipe for output routing**: Claude Code output is routed through a mkfifo pipe so it can be both displayed to the terminal (via `tee`) and scanned by the background monitor without interrupting Claude's interactivity.

**No `declare -A`**: Bash 3.2 compatibility (macOS default) means no associative arrays. Status priorities are expressed as hardcoded `if/elif` chains in `extract_context()`.

**Source guards**: Each lib file checks `_CCP_*_SOURCED` before executing to prevent issues when files source each other.

**Session file format**: Flat JSON array (`[]`) in `~/.config/claude-pane-pulse/sessions.json`, managed entirely via `jq`.
