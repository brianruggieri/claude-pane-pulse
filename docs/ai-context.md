# AI Context Summarization (`--ai-context`)

> **This feature is opt-in.** It does nothing unless you explicitly pass `--ai-context`. Nothing is sent anywhere by default.

## What It Does

When enabled, ccp watches the first message you send to Claude in each session and generates a concise 3–5 word label for it. That label appears in the terminal title alongside the current status:

```
✳ my-project (main) | Fix Auth Bug | ✏️ Editing
                       ─────────────
                       This part. "Fix Auth Bug" instead of "fix the login crash wh..."
```

Without `--ai-context`, the title shows the first 5 words of your raw prompt verbatim:

```
✳ my-project (main) | fix the login crash whe | ✏️ Editing
```

With `--ai-context`, it's refined into a clean label:

```
✳ my-project (main) | Fix Login Crash | ✏️ Editing
```

## How It Works

When you send a prompt, `hook_runner.sh`'s UserPromptSubmit handler:

1. Writes the first 5 words of your prompt to the context file immediately (instant title update)
2. Fires a **detached background subprocess** with `claude --print --model claude-haiku-4-5-20251001`
3. Sends this exact prompt to Haiku:

```
Summarize this developer task in 3-5 words. Title-case. No punctuation. No quotes. Reply with only the words, nothing else. Task: <your prompt text>
```

4. When Haiku responds (~1–3 seconds), overwrites the context file with the summary
5. The title_updater picks it up on the next heartbeat

The subprocess is fully detached (`& disown`). It never blocks Claude, never delays your session, and never writes to the terminal.

## What Data Is Sent

**Exactly your prompt text** — the full message you typed into Claude Code, after stripping the project name if it appears in the title.

No other data is sent. No file contents, no tool outputs, no conversation history. Just the user-facing message you already typed.

## Subscription Usage

This feature calls `claude --print` once per user message. That's one Haiku API call per prompt you send.

- **Model:** `claude-haiku-4-5-20251001` (the most cost-effective model)
- **Call type:** Non-interactive, single-turn (`--print` flag)
- **Context sent:** Your prompt text only (one message, no history)
- **Response:** 3–5 words (minimal token usage)

If you use Claude via subscription (Claude.ai Pro/Max), this counts against your subscription usage. If you use API keys, this counts against your API bill. The per-call cost is minimal (Haiku is Anthropic's cheapest model), but it fires every time you send a message, so usage scales with how much you type.

**This is exactly why the feature is opt-in.** We don't think it's appropriate to silently consume your subscription on your behalf. You should choose to enable it knowing what it does.

## Privacy

The data flow is:

```
Your prompt text → claude CLI (your auth) → Anthropic API → 3-5 word summary
```

- Your prompt is processed under your own Claude account and credentials
- The summary request is subject to Anthropic's standard privacy policy — the same policy that applies to every message you send to Claude
- ccp does not see, log, or store the data — the call happens entirely through your local `claude` CLI binary

Nothing is routed through ccp's infrastructure (there isn't any). The subprocess calls the same `claude` binary you use interactively.

## How to Enable

```bash
# Flag (per session)
ccp --ai-context "My task"

# Environment variable (always-on — add to ~/.zshrc or ~/.bashrc)
export CCP_ENABLE_AI_CONTEXT=true
ccp "My task"  # AI context active without --ai-context flag
```

The flag and env var are equivalent. The env var is the recommended approach if you always want AI context active.

When enabled, ccp prints a disclosure at startup:

```
Dynamic titles: enabled
Status profile: quiet
AI context:     enabled (prompts summarized via claude-haiku — uses your subscription)
```

## How to Disable

Don't pass `--ai-context`. That's all.

If you had previously set `CCP_ENABLE_AI_CONTEXT=true` in your shell profile, remove that line.

## Without AI Context

Without `--ai-context`, the context area of the title shows the first 5 words of your raw prompt. This is:

- Instant (no network call)
- Free (no subscription usage)
- Slightly noisier (longer or incomplete phrases)

For most use cases — especially short, clear prompts — the raw first-5-words fallback is perfectly readable. The AI summarization adds the most value for long, detailed prompts where the first 5 words don't convey the actual task.

## Benefit

The title bar has limited space. A multi-pane terminal with 4 Claude sessions needs titles that are:

- Short enough to read at a glance
- Meaningful enough to distinguish sessions from each other
- Stable enough to not change mid-session as Claude responds

A raw prompt like `"Can you look at the authentication middleware and figure out why the JWT validation is failing for certain edge cases with malformed tokens"` truncates to `"Can you look at"` — useless. With AI context, it becomes `"Fix JWT Validation Bug"` — immediately useful.

<!-- screenshot: split pane showing 4 sessions with distinct AI-generated task labels in their titles -->

The feature is most valuable when:
- Running 4+ sessions simultaneously
- Using long, detailed prompts
- Working across multiple repositories or PRs
