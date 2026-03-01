# demo-assets

Production-ready screenshots and animations for claude-pane-pulse.

## Files

| File | Size | Format | Use |
|------|------|--------|-----|
| `screenshot-before.png` | 1400×840 | PNG | README before-state hero |
| `screenshot-after.png` | 1400×840 | PNG | README after-state hero |
| `comparison-sidebyside.png` | 1400×900 | PNG | Blog, portfolio, talks |
| `hero-social.png` | 1200×630 | PNG | LinkedIn / Twitter / OG image |
| `hero-animated.gif` | 820×380 | GIF | README animation, LinkedIn |
| `hero-animated.mp4` | 820×380 | MP4 | Video embeds, portfolio |

## Usage

### GitHub README

```markdown
![claude-pane-pulse demo](demo-assets/hero-animated.gif)

<table>
  <tr>
    <td><b>Before</b></td>
    <td><b>After</b></td>
  </tr>
  <tr>
    <td><img src="demo-assets/screenshot-before.png" width="700"></td>
    <td><img src="demo-assets/screenshot-after.png" width="700"></td>
  </tr>
</table>
```

Or use the comparison image directly:

```markdown
![Before vs After](demo-assets/comparison-sidebyside.png)
```

### LinkedIn

Upload `hero-social.png` as the post image (1200×630 is optimal for LinkedIn's
feed crop), or upload `hero-animated.gif` as an animated image (< 5 MB).

### Blog post (Dev.to / Hashnode)

- Header image → `hero-social.png`
- Inline before/after → `screenshot-before.png` + `screenshot-after.png`
- Animated section → `hero-animated.gif`

### Portfolio / case study

Use `comparison-sidebyside.png` as the hero — it tells the full story in one frame.

---

## Regenerating

All assets are reproducible from source templates in `sources/`.

```bash
# PNG screenshots (requires Playwright MCP or a browser)
# Re-run the screenshot commands against sources/before.html etc.

# Animated GIF + MP4
cd /path/to/claude-pane-pulse
vhs demo-assets/sources/demo-animate.tape

# Optimize GIF (optional)
gifsicle -O3 --colors 256 demo-assets/hero-animated.gif -o demo-assets/hero-animated.gif
```

## Source templates

| File | Produces |
|------|----------|
| `sources/before.html` | `screenshot-before.png` |
| `sources/after.html` | `screenshot-after.png` |
| `sources/comparison.html` | `comparison-sidebyside.png` |
| `sources/social.html` | `hero-social.png` |
| `sources/animate.sh` | (used by VHS tape) |
| `sources/demo-animate.tape` | `hero-animated.gif` + `.mp4` |
