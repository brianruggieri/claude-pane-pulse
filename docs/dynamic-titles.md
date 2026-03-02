# Dynamic Title System

**C**laude **C**ode **P**ane-Pulse monitors Claude Code's output in real time and updates your terminal title to reflect what's happening.

## How It Works

When dynamic mode is active (the default), `ccp`:

1. Launches Claude Code with its output piped through a named FIFO (`/tmp/ccp-<pid>/pipe`)
2. Starts a background reader process that scans each output line
3. The reader calls `extract_context()` on each line to detect a status keyword
4. If a higher-priority status is detected (or 60s have passed), the title updates
5. The output is simultaneously `tee`'d to your terminal so you see it normally

```
Claude Code output
     │
     ▼
 named FIFO
     │
     ├──► tee → your terminal (unchanged)
     │
     └──► background reader → extract_context() → set_title()
```

## Status Detection Patterns

The monitor scans each output line with regex patterns:

| Pattern matched | Status shown | Priority |
|----------------|-------------|---------|
| `Error`, `Failed`, `Exception`, `Traceback`, `FAILED` | 🐛 Error | 100 |
| `N tests failed`, `N specs failing` | ❌ Tests failed | 90 |
| `Building`, `Compiling`, `Bundling` | 🔨 Building | 80 |
| `npm test`, `yarn test`, `pytest`, `jest` | 🧪 Testing | 80 |
| `npm install`, `yarn add`, `yarn ci` | 📦 Installing | 80 |
| `git push` | ⬆️ Pushing | 75 |
| `git pull` | ⬇️ Pulling | 75 |
| `git merge` | 🔀 Merging | 75 |
| `docker build/run/push` | 🐳 Docker | 70 |
| `Let me think`, `Planning`, `Analyzing`, `I'll` | 💭 Thinking | 70 |
| `N tests passed`, `N specs passed` | ✅ Tests passed | 60 |
| `git commit` | 💾 Committed | 60 |
| (60s of no significant activity) | 💤 Idle | 10 |

## Priority System

Higher-priority statuses always win. If Claude is both building (priority 80) and hits an error (priority 100), the title immediately switches to 🐛 Error and stays there until something higher-priority or a 60s timeout resets it.

This ensures that **errors are never hidden** by lower-priority activity.

## Animation

Active in-progress operations (Building, Testing, Installing, Pushing, etc.) get animated dots to show they're still running:

```
PR #89 | 🔨 Building
PR #89 | 🔨 Building.
PR #89 | 🔨 Building..
PR #89 | 🔨 Building...
PR #89 | 🔨 Building     (loops back)
```

The animation cycles every ~0.8 seconds (tied to output processing).

Completion statuses (✅ Tests passed, 💾 Committed, 🐛 Error) are **static** — they don't animate.

## Idle Detection

If no significant status has been detected for 60 seconds, the title resets to:

```
PR #89 - Fix auth | 💤 Idle
```

The base title is always preserved — only the status suffix changes.

## Disabling Dynamic Mode

```bash
ccp --no-dynamic "PR #89 - Fix auth"
```

Title is set once at startup and never changes. Useful for clean screenshots or when you don't need real-time updates.

## Customizing Patterns

The detection logic lives in `lib/monitor.sh` in the `extract_context()` function. It's plain `if/elif` bash with regex patterns — easy to extend:

```bash
# Example: detect Rust cargo build
elif [[ "${line}" =~ cargo[[:space:]]+(build|test|run) ]]; then
    context="🦀 Cargo"
    priority=80
```

After editing, reinstall with `./install.sh` to update the files in `~/.local/share/ccp/lib/`.
