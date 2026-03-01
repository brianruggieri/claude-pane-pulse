# VHS tape: claude-pane-pulse title bar animation
# Run from repo root: vhs demo-assets/sources/demo-animate.tape

Output demo-assets/hero-animated.gif
Output demo-assets/hero-animated.mp4

Set FontSize 14
Set Width 820
Set Height 380
Set Theme "Dracula"
Set Padding 20
Set PlaybackSpeed 1.0
Set TypingSpeed 0ms

# ── Setup: minimal prompt, no command echo, source helpers ───────────────────
Hide
Type "export PS1=''; stty -echo" Enter
Type "source demo-assets/sources/states.sh" Enter
Ctrl+L
Show

# ── Idle (1.2s) ───────────────────────────────────────────────────────────────
Hide
Type "state_idle" Enter
Show
Sleep 1.2s

# ── Thinking (2s) ─────────────────────────────────────────────────────────────
Hide
Ctrl+L
Type "state_thinking" Enter
Show
Sleep 2s

# ── Building (2s) ─────────────────────────────────────────────────────────────
Hide
Ctrl+L
Type "state_building" Enter
Show
Sleep 2s

# ── Testing — results appear line-by-line ─────────────────────────────────────
Hide
Ctrl+L
Type "state_testing" Enter
Show
Sleep 800ms

Hide
Ctrl+L
Type "state_tests_appearing" Enter
Show
Sleep 600ms

Hide
Ctrl+L
Type "state_tests_more" Enter
Show
Sleep 1s

# ── Tests passed (2.5s) ───────────────────────────────────────────────────────
Hide
Ctrl+L
Type "state_passed" Enter
Show
Sleep 2.5s

# ── Pushing (2s) ──────────────────────────────────────────────────────────────
Hide
Ctrl+L
Type "state_pushing" Enter
Show
Sleep 2s

# ── Committed (3s) ────────────────────────────────────────────────────────────
Hide
Ctrl+L
Type "state_committed" Enter
Show
Sleep 3s
