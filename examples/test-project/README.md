# test-project

Demo project for testing `claude-pane-pulse` title monitoring.

## What's Here

- `src/math.js` — math utilities with a **deliberate bug** in `add()`
- `src/auth.js` — auth token helpers (all passing)
- `tests/math.test.js` — will **fail** until the bug is fixed
- `tests/auth.test.js` — always passes

## Try It

```bash
# Start ccp in this directory — title updates as Claude works
cd examples/test-project
ccp --feature "Fix math bug"

# In the Claude Code session, ask:
# "Run the tests and fix whatever is failing"
#
# Watch the pane title cycle through:
#   Feature: Fix math bug | 🧪 Testing...
#   Feature: Fix math bug | ❌ Tests failed
#   Feature: Fix math bug | 🔨 Building
#   Feature: Fix math bug | 🧪 Testing...
#   Feature: Fix math bug | ✅ Tests passed
#   Feature: Fix math bug | 💾 Committed
```

## Running Tests Manually

Requires Node.js 18+ (uses built-in test runner, no npm install needed):

```bash
node --test tests/math.test.js tests/auth.test.js
```
