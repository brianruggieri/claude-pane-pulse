# Inline AI Context: Specification

> **Status:** Implemented  
> **Feature flag:** `--ai-context-strategy inline` / `CCP_AI_CONTEXT_STRATEGY=inline`

## Problem

The existing `--ai-context` feature sends a **separate** `claude --print --model claude-haiku` API call to summarize each user prompt. This works, but has trade-offs:

- **Extra cost** — one Haiku call per prompt (subscription or API credits).
- **Extra latency** — 1–3 seconds for the background call to return.
- **Reduced context** — Haiku only sees the raw prompt text, not the codebase or conversation history.
- **Duplicate data** — the prompt is sent to Anthropic twice (once for the main session, once for summarization).

## Solution: Inline Context Strategy

Piggyback on the **already-outgoing** Claude request. Instead of a separate API call, CCP injects a lightweight system prompt instruction into the main Claude session via `--append-system-prompt`. Claude generates a task summary as part of its normal first-turn processing, and CCP captures it through the existing PostToolUse hook.

### How It Works

```
┌──────────────────────────────────────────────────────────────────┐
│  User types prompt → goes to Claude (as always)                  │
│                                                                  │
│  CCP adds --append-system-prompt with a one-line instruction:    │
│  "echo 'CCP_TASK_SUMMARY:Brief Title' as your first action"     │
│                                                                  │
│  Claude reads user prompt + full codebase context                │
│  Claude echoes: CCP_TASK_SUMMARY:Fix JWT Auth Bug                │
│  Claude proceeds with normal work                                │
│                                                                  │
│  PostToolUse hook sees the echo output                           │
│  hook_runner.sh extracts the summary after the marker            │
│  Writes to CCP_CONTEXT_FILE                                     │
│  Monitor picks it up → title updates                             │
└──────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
User prompt ──→ Claude (with appended system prompt)
                    │
                    ├─→ echo 'CCP_TASK_SUMMARY:Fix JWT Auth'  (first action)
                    │       │
                    │       └─→ PostToolUse hook → hook_runner.sh
                    │               │
                    │               └─→ extract summary → CCP_CONTEXT_FILE
                    │                       │
                    │                       └─→ monitor → terminal title
                    │
                    └─→ normal Claude work continues
```

## System Prompt Instruction

The injected instruction is deliberately minimal to avoid wasting context window space:

```
[CCP Terminal Title] As your very first action, run: echo 'CCP_TASK_SUMMARY:' followed by
a 3-5 word title-case summary of the user's task. Example: echo 'CCP_TASK_SUMMARY:Fix JWT
Validation Bug'. Do this once, then proceed normally.
```

**Key design choices:**

1. **Structured marker** (`CCP_TASK_SUMMARY:`) — unambiguous prefix for reliable parsing. Not a plausible substring of any real command output.
2. **Bash echo** — the simplest possible tool use. No file writes, no permissions, no side effects. The echo goes to stdout and is captured by the PostToolUse hook's `tool_response` field.
3. **One-shot** — "Do this once" prevents repeated summaries on follow-up prompts.
4. **Minimal instruction** — under 250 characters. Negligible context window impact.

## Comparison: Haiku vs. Inline

| Aspect | Haiku (`haiku`) | Inline (`inline`) |
|---|---|---|
| **API calls** | +1 Haiku call per prompt | Zero extra calls |
| **Cost** | Haiku tokens (small but nonzero) | Zero additional cost |
| **Latency** | 1–3s background call | ~0s (part of main response) |
| **Summary quality** | Haiku-quality (good) | Main-model quality (better — full context) |
| **Context available** | Prompt text only | Full codebase + conversation history |
| **User visibility** | Invisible (detached subprocess) | One brief `echo` in Claude's output |
| **Privacy** | Prompt sent twice to Anthropic | Prompt sent once (already going) |
| **Reliability** | High (dedicated call) | Model-dependent (Claude may skip it) |
| **Fallback** | First 5 words if Haiku fails | First 5 words if echo is skipped |

## Configuration

```bash
# Enable inline strategy (per session)
ccp --ai-context --ai-context-strategy inline "My task"

# Enable inline strategy (always-on via env vars)
export CCP_ENABLE_AI_CONTEXT=true
export CCP_AI_CONTEXT_STRATEGY=inline
ccp "My task"
```

The strategy setting only matters when `--ai-context` is enabled. Without `--ai-context`, both strategies are inactive and the title shows the raw first-5-words fallback.

## Privacy & Security

### What changes

- **Haiku strategy**: prompt text is sent to Anthropic twice (main session + Haiku call).
- **Inline strategy**: prompt text is sent to Anthropic once (main session only). A ~250-character system prompt instruction is appended.

### What doesn't change

- No data is sent to any third party (all calls go through your local `claude` CLI).
- No data is logged, stored, or transmitted by CCP.
- The summary stays local (written to a temp file in `~/.config/claude-code-pulse/`).
- The feature is opt-in (requires `--ai-context`).

### Transparency

When the inline strategy is active, CCP prints at startup:

```
AI context:     enabled (inline — summary via system prompt, no extra API calls)
```

The system prompt instruction is visible in Claude's conversation context (Claude Code shows system prompt contents when asked).

## Terms & Convention Compliance

1. **`--append-system-prompt`** is Claude Code's official mechanism for extending the system prompt. CCP uses it as documented.
2. **PostToolUse hooks** are Claude Code's official mechanism for observing tool outputs. CCP reads, never modifies.
3. **The appended instruction does not override or conflict** with the user's own `--system-prompt` or `--append-system-prompt` flags. Claude Code concatenates multiple `--append-system-prompt` values.
4. **Claude's behavior is not silently altered** — the system prompt is part of the visible configuration, and the echo output appears in Claude's tool use history.

## Failure Modes

| Scenario | Behavior |
|---|---|
| Claude ignores the instruction | First-5-words fallback remains in the title (same as no AI context) |
| Claude includes extra text in the echo | Marker prefix parsing extracts only the summary portion |
| Claude echoes on every prompt | Only the latest summary is used (atomic overwrite) |
| User also passes `--append-system-prompt` | Both are applied (Claude Code concatenates) |
| Inline + Haiku both enabled | Inline takes precedence (Haiku subprocess is skipped) |

## Implementation Summary

### `bin/ccp`
- Parses `--ai-context-strategy` flag and `CCP_AI_CONTEXT_STRATEGY` env var
- When inline: injects `--append-system-prompt` with the summary instruction into `claude_args`
- Exports `CCP_AI_CONTEXT_STRATEGY` for `hook_runner.sh`

### `lib/hook_runner.sh`
- `post-tool` handler: detects `CCP_TASK_SUMMARY:` in Bash tool_response, extracts summary, writes to `CCP_CONTEXT_FILE`
- `user-prompt` handler: skips Haiku subprocess when strategy is `inline` (summary will come from the main session)

### `docs/ai-context.md`
- Documents both strategies with clear comparison
- Explains when to use each one
