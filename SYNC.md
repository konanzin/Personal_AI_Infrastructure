# Selective Upstream Sync

This document describes how to pull specific changes from upstream PAI into this repo. Sync is **selective and manual**, not automatic or wholesale.

## Philosophy

This repo is a self-contained product, not a live fork. We sync with upstream only when a specific change provides clear value. `main` holds a reference snapshot of upstream; `opencode` is the working branch.

## When to Sync

Consider syncing when:

- A new upstream skill is relevant to OpenCode users
- An Algorithm update changes behavior you want to preserve
- A documentation fix or security patch applies directly
- You want to refresh the `main` reference baseline

Do **not** sync habitually on every upstream commit. The `opencode` branch evolves independently.

## Workflow

### 1. Refresh the reference baseline (`main`)

```bash
# Add upstream remote once
git remote add upstream https://github.com/danielmiessler/PAI.git 2>/dev/null || true

# Fetch latest upstream
git fetch upstream

# Update main (reference only)
git checkout main
git merge upstream/main --no-edit
git push origin main
```

### 2. Evaluate what changed

```bash
# See what changed since last sync
git log --oneline main@{1}..main

# Diff a specific area
git diff main@{1}..main -- skills/
git diff main@{1}..main -- PAI/ALGORITHM/
```

### 3. Cherry-pick or manually port to `opencode`

For **inherited content** (`PAI/`, `skills/`):

```bash
git checkout opencode

# Option A: Cherry-pick a specific upstream commit
git cherry-pick <commit-hash>

# Option B: Copy specific files manually
git checkout main -- skills/NOVA_SKILL/
# Then adapt paths: sed -i 's|~/.claude/|~/.config/opencode/|g' skills/NOVA_SKILL/**/*
```

For **adapted content** (`opencode/plugins/`, `opencode/agents/`):

Do not cherry-pick upstream commits directly. Read the upstream change, then reimplement it for OpenCode's native surfaces.

### 4. Test

```bash
# Install updated content
./opencode/install.sh --update

# Validate
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
bash ~/.config/opencode/PAI/bin/test-behavioral.sh
bash ~/.config/opencode/PAI/bin/test-e2e-runtime.sh
```

### 5. Commit and push

```bash
git add -A
git commit -m "sync: upstream <description>"
git push origin opencode
```

## Common Scenarios

### New upstream skill

```bash
# Refresh main, then:
git checkout opencode
git checkout main -- skills/NOVA_SKILL/

# Check for Claude-specific paths
grep -r "\.claude/" skills/NOVA_SKILL/ -l || echo "No Claude paths found"

# Adapt if needed
find skills/NOVA_SKILL -type f -exec sed -i 's|~/.claude/|~/.config/opencode/|g' {} +

# Test
./opencode/install.sh --update
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

### Algorithm update

```bash
# Refresh main, then evaluate:
git diff main@{1}..main -- PAI/ALGORITHM/

# If behavior changed, update adapted code (plugin, agents) to match
git checkout opencode
# Manually apply relevant changes to opencode/ surface
```

### Documentation fixes

```bash
# Safe to cherry-pick if no Claude-specific references
git checkout opencode
git cherry-pick <doc-fix-commit>
```

## What NOT to Sync

- **Plugin implementation** — `opencode/plugins/` is native to OpenCode; upstream has no equivalent.
- **Agent files** — `opencode/agents/*.md` use OpenCode agent format, not Claude Code format.
- **Commands** — `opencode/commands/*.md` are OpenCode-specific.
- **Validation scripts** — `opencode/bin/test-*.sh` are native to this repo.
- **Guard rails / classifier** — AgentGuard, SkillGuard, and the mode classifier are native features.

## Automatization (Optional)

For convenience, a helper script can refresh `main` and list changed files:

```bash
#!/bin/bash
# refresh-main.sh — Update main reference and show changes

set -e
git fetch upstream
git checkout main
git merge upstream/main --no-edit
git push origin main

echo ""
echo "Changes since last sync:"
git log --oneline main@{1}..main

echo ""
echo "Changed files:"
git diff --name-only main@{1}..main
```

Do **not** automate rebasing `opencode` onto `main`. That decision is manual.
