# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Claude Code Pulse, please report it responsibly — **do not open a public GitHub issue**.

**Contact:** brianruggieri@gmail.com
**Subject prefix:** `[SECURITY] claude-code-pulse`

I will acknowledge receipt within 48 hours and provide a fix timeline.

## Scope

This policy covers:
- `bin/ccp` — the main CLI executable
- `lib/hook_runner.sh` — hook event handler (runs as a Claude Code hook subprocess)
- `lib/hooks.sh` — hook injection into `.claude/settings.local.json`
- `install.sh` / `uninstall.sh` — installer scripts

## What ccp Does

For context when evaluating security:

- **Hook injection**: On startup, ccp writes entries to `.claude/settings.local.json` in the project directory. These entries register `hook_runner.sh` as a Claude Code hook handler. Entries are PID-tagged and removed on exit.
- **No network access**: ccp itself makes no network calls. The optional `--ai-context` feature runs `claude --print` (your local Claude CLI binary) — all network activity goes through your existing Claude account.
- **No elevated privileges**: ccp runs entirely as your user. The installer copies files to `~/.local/share/ccp/` and symlinks to `~/bin/ccp` — no `sudo` required.
- **State files**: Status and context are written to `~/.config/claude-code-pulse/` (flat text files, no executable content).

## Supported Versions

| Version | Supported |
|---------|-----------|
| latest (`main`) | Yes |
| older releases | No — please update |
