# Installation Guide

## Prerequisites

| Requirement | Version | Notes |
|------------|---------|-------|
| macOS | Sonoma+ | May work on earlier versions |
| bash | 3.2+ | Pre-installed on macOS |
| jq | any | Required for session tracking |
| Claude Code CLI | any | Required to launch Claude |

### Install jq

```bash
brew install jq
```

### Install Claude Code CLI

See [claude.ai/code](https://claude.ai/code) for installation instructions.

## Install Claude Pane Pulse

### Quick install

```bash
git clone https://github.com/brianruggieri/claude-pane-pulse.git
cd claude-pane-pulse
./install.sh
```

The installer:
1. Copies files to `~/.local/share/ccp/`
2. Creates a symlink at `~/bin/ccp`
3. Adds `~/bin` to your PATH (in `~/.zshrc` or `~/.bashrc`)

### Reload your shell

```bash
source ~/.zshrc   # zsh users
source ~/.bashrc  # bash users
```

Or just open a new terminal window.

### Verify installation

```bash
ccp --version
# → ccp version 1.0.0
```

## Uninstall

```bash
./uninstall.sh
```

This removes the program files and the `~/bin/ccp` symlink. You'll be prompted about session data.

## Troubleshooting

### `ccp: command not found`

Your shell can't find `~/bin/ccp`. Check:

```bash
echo $PATH | tr ':' '\n' | grep -E 'bin$'
```

If `~/bin` isn't listed, add it to your shell profile:

```bash
echo 'export PATH="${HOME}/bin:${PATH}"' >> ~/.zshrc
source ~/.zshrc
```

### `jq: command not found`

```bash
brew install jq
```

### `claude: command not found` / `claude-code: command not found`

Install Claude Code CLI from [claude.ai/code](https://claude.ai/code).

### Title doesn't update in tmux

Make sure your tmux config allows title changes. Add to `~/.tmux.conf`:

```
set -g allow-rename on
```

Then reload: `tmux source-file ~/.tmux.conf`

### Title doesn't update in Terminal.app

Go to **Terminal → Preferences → Profiles → Window** and ensure "Active Process Name" is unchecked (otherwise Terminal.app overrides programmatic titles).

### Permission denied on install

The installer only touches `~/.local/share/ccp/` and `~/bin/` — no `sudo` required. If you get permission errors, check ownership of those directories.

## Manual Installation

If you prefer not to use the installer:

```bash
# 1. Clone the repo
git clone https://github.com/brianruggieri/claude-pane-pulse.git

# 2. Create directories
mkdir -p ~/.local/share/ccp/bin ~/.local/share/ccp/lib ~/bin

# 3. Copy files
cp claude-pane-pulse/bin/ccp ~/.local/share/ccp/bin/
cp claude-pane-pulse/lib/*.sh ~/.local/share/ccp/lib/
chmod +x ~/.local/share/ccp/bin/ccp

# 4. Create symlink
ln -s ~/.local/share/ccp/bin/ccp ~/bin/ccp

# 5. Add to PATH
echo 'export PATH="${HOME}/bin:${PATH}"' >> ~/.zshrc
```
