# Update Workflow

## Voice Notification

```bash
(curl -s --max-time 2 -X POST http://localhost:31337/notify \
  -H "Content-Type: application/json" \
  -d '{"message": "Running the Update workflow in the Browser skill to sync capabilities", "language": "en-US"}' \
  > /dev/null 2>&1 || true) &
```

Running **Update** in **Browser**...

---

Verify browser tools are current and working.

## When to Use

- After agent-browser releases new version
- If browser tools fail unexpectedly
- Periodic capability check

## Steps

### 1. Check Versions

```bash
agent-browser --version
```

### 2. Verify Headless agent-browser

```bash
agent-browser --session update-test open https://example.com
agent-browser --session update-test snapshot
agent-browser --session update-test screenshot /tmp/update-test.png
```

### 3. Verify One-Shot Screenshot

```bash
agent-browser open https://example.com && agent-browser screenshot /tmp/oneshot-test.png
```

### 4. Verify Parallel Worker Pattern

```
Agent(subagent_type="general-purpose", prompt="Use agent-browser --session update-worker to navigate to https://example.com. Take a snapshot. Report page title.")
```

### 5. Verify Stories and Recipes

```bash
ls ~/.config/opencode/skills/Browser/Stories/*.yaml
ls ~/.config/opencode/skills/Browser/Recipes/*.md
```

## Version Tracking

```
# Last sync: 2026-04-04
# Version: 8.0.0
# Headless: agent-browser (Rust CLI daemon, headless default)
# One-shot: agent-browser open <url> && agent-browser screenshot <path>
# Agents: general-purpose workers with agent-browser instructions
# Orchestration: ReviewStories, Automate
# Custom code: NONE
```
