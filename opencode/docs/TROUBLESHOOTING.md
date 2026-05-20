# PAI for OpenCode — Troubleshooting Guide

> Common issues and solutions for the PAI OpenCode port.

## Quick Diagnostic

Run the validation script first:

```bash
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

Expected output: `64/64 checkpoints passed (100%)`

If you see failures, match the section below to find your issue.

---

## Installation Issues

### "Missing prerequisites: git opencode"

**Cause:** The installer cannot find `git` or `opencode` in your PATH.

**Solution:**
```bash
# Install git (macOS)
brew install git

# Install git (Ubuntu/Debian)
sudo apt-get install git

# Install opencode
curl -fsSL https://opencode.ai/install.sh | sh
```

### "PAI directory exists but is empty"

**Cause:** Clone failed or was interrupted.

**Solution:**
```bash
# Remove and re-run installer
rm -rf ~/.config/opencode/PAI
bash ~/.config/opencode/PAI/bin/install-pai-opencode.sh
```

### Backup creation fails

**Cause:** Insufficient disk space or permissions.

**Solution:**
```bash
# Check disk space
df -h ~/.config/

# Check permissions
ls -ld ~/.config/

# Fix permissions
chmod 755 ~/.config/
```

---

## Path Issues

### Code still references `~/.claude/`

**Cause:** Legacy code or skills use the old Claude Code path.

**Solution 1 — Check symlink:**
```bash
# Verify symlink exists
ls -la ~/.claude

# Should show: ~/.claude -> ~/.config/opencode/PAI

# If missing, create it:
ln -s ~/.config/opencode/PAI ~/.claude
```

**Solution 2 — Update hardcoded paths:**
```bash
# Find files referencing old path
grep -r "~/.claude/" ~/.config/opencode/PAI/ --include="*.md" --include="*.js" --include="*.ts" --include="*.json"

# Replace with new path (review before running)
find ~/.config/opencode/PAI/ -type f \( -name "*.md" -o -name "*.js" -o -name "*.ts" -o -name "*.json" \) -exec sed -i 's|~/.claude/|~/.config/opencode/PAI/|g' {} +
```

**Solution 3 — Check PULSE paths:**
```bash
# Run PULSE path patcher
bash ~/.config/opencode/PAI/PULSE/patch-paths.sh
```

### "PAI_DIR not set"

**Cause:** Plugin failed to set environment variable.

**Solution:**
```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
export PAI_DIR="$HOME/.config/opencode/PAI"
```

---

## Plugin Loading Issues

### "Plugin not found" or "Cannot load plugin"

**Cause:** Plugin file missing or opencode.jsonc misconfigured.

**Solution:**
```bash
# Check plugin exists
ls -la ~/.config/opencode/plugins/pai-hooks.js

# Check opencode.jsonc configuration
cat ~/.config/opencode/opencode.jsonc | grep -A 2 "plugin"

# Should show:
# "plugin": ["./plugins/pai-hooks.js"]

# If missing, add it:
cat >> ~/.config/opencode/opencode.jsonc << 'EOF'
{
  "plugin": ["./plugins/pai-hooks.js"]
}
EOF
```

### Plugin errors on startup

**Cause:** Plugin JavaScript error or incompatible OpenCode version.

**Solution:**
```bash
# Check OpenCode version
opencode --version

# Check plugin syntax
node --check ~/.config/opencode/plugins/pai-hooks.js

# View plugin logs
tail -f ~/.config/opencode/PAI/logs/tool-activity.jsonl

# Reinstall plugin
cp ~/.config/opencode/PAI/plugins/pai-hooks.js ~/.config/opencode/plugins/
```

### "pai-hooks.lib.js not found"

**Cause:** Library file missing or wrong location.

**Solution:**
```bash
# Check library exists
ls -la ~/.config/opencode/plugins/pai-hooks.lib.js

# If missing, copy from PAI directory
cp ~/.config/opencode/PAI/plugins/pai-hooks.lib.js ~/.config/opencode/plugins/
```

---

## Agent Issues

### "Agent not found" or "No such agent"

**Cause:** Agent files missing or wrong location.

**Solution:**
```bash
# Check agents exist
ls -la ~/.config/opencode/agents/*.md

# Should show 18+ agent files

# If missing, check if they exist in PAI directory
ls ~/.config/opencode/PAI/agents/

# Copy if needed
cp ~/.config/opencode/PAI/agents/*.md ~/.config/opencode/agents/
```

### Agent uses wrong model

**Cause:** Agent file specifies unavailable model.

**Solution:**
```bash
# Check agent frontmatter
cat ~/.config/opencode/agents/Engineer.md | head -5

# Edit to use available model
# Valid models: kimi-for-coding/k2p6, claude-sonnet-4, gpt-4, etc.
```

---

## Command Issues

### "/status not found"

**Cause:** Command file missing or not registered.

**Solution:**
```bash
# Check command file exists
ls -la ~/.config/opencode/commands/status.md

# If missing, create it
cat > ~/.config/opencode/commands/status.md << 'EOF'
---
name: status
description: Show PAI status
---

Run: bash ~/.config/opencode/PAI/bin/statusline-command.sh
EOF
```

### "/pai not found"

**Cause:** PAI Algorithm command not registered.

**Solution:**
```bash
# Check command file
ls -la ~/.config/opencode/commands/pai.md

# Alternative: Run algorithm directly
opencode /algorithm "Your task here"
```

---

## Configuration Issues

### "opencode.jsonc invalid"

**Cause:** Syntax error in configuration file.

**Solution:**
```bash
# Validate JSON syntax
node -e "JSON.parse(require('fs').readFileSync('~/.config/opencode/opencode.jsonc', 'utf8').replace(/\\/\\/.*/g, ''))" && echo "Valid JSON"

# Check for trailing commas
# JSONC allows comments but not trailing commas in some versions

# Reset to default
cat > ~/.config/opencode/opencode.jsonc << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "kimi-for-coding/k2p6",
  "default_agent": "build",
  "plugin": ["./plugins/pai-hooks.js"],
  "skills": {
    "paths": ["~/.config/opencode/skills"]
  }
}
EOF
```

### Skills not loading

**Cause:** Wrong path in opencode.jsonc or skills directory missing.

**Solution:**
```bash
# Check skills path
ls -la ~/.config/opencode/skills/

# Check opencode.jsonc skills config
grep -A 3 '"skills"' ~/.config/opencode/opencode.jsonc

# Should show paths pointing to ~/.config/opencode/skills
```

---

## Verification Steps

### Verify Complete Installation

```bash
# 1. Check directory structure
ls -la ~/.config/opencode/PAI/

# 2. Check version
cat ~/.config/opencode/PAI/.version.json

# 3. Run validation
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh

# 4. Check opencode config
cat ~/.config/opencode/opencode.jsonc

# 5. Test plugin loading
opencode --version
# Should show PAI initialization messages
```

### Verify Plugin is Active

```bash
# Check tool activity log
tail ~/.config/opencode/PAI/logs/tool-activity.jsonl

# Should show entries with [PAI] prefix
```

---

## Reset / Clean Install

### Nuclear Option — Complete Reset

**WARNING:** This removes all PAI data including MEMORY, WORK, and customizations.

```bash
# 1. Backup your data first
cp -R ~/.config/opencode/PAI ~/.config/opencode/PAI-backup-$(date +%Y%m%d)

# 2. Remove PAI directory
rm -rf ~/.config/opencode/PAI

# 3. Remove plugins
rm -f ~/.config/opencode/plugins/pai-hooks.js
rm -f ~/.config/opencode/plugins/pai-hooks.lib.js

# 4. Remove agents (optional — they can stay)
rm -rf ~/.config/opencode/agents

# 5. Re-run installer
bash /tmp/pai/PAI/bin/install-pai-opencode.sh
```

### Soft Reset — Keep Data

```bash
# 1. Backup
mv ~/.config/opencode/PAI ~/.config/opencode/PAI-old

# 2. Reinstall core files only
mkdir -p ~/.config/opencode/PAI
cp -R ~/.config/opencode/PAI-old/{USER,MEMORY} ~/.config/opencode/PAI/ 2>/dev/null || true
bash ~/.config/opencode/PAI-old/bin/install-pai-opencode.sh
```

---

## Update PAI

### Update to Latest Version

```bash
# 1. Navigate to PAI directory
cd ~/.config/opencode/PAI

# 2. Pull latest changes
git pull origin main 2>/dev/null || git pull origin master 2>/dev/null

# 3. Re-run installer to update plugins/agents
bash bin/install-pai-opencode.sh

# 4. Validate
bash bin/validate-pai-installation.sh
```

### Update Checklist

- [ ] Backup existing installation
- [ ] Pull latest PAI code
- [ ] Re-run installer
- [ ] Run validation script
- [ ] Check for new breaking changes in CHANGELOG
- [ ] Update custom configurations if needed

---

## Getting Help

### Diagnostic Information to Include

When reporting issues, include:

```bash
# Run diagnostic script and copy output
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh 2>&1

# OpenCode version
opencode --version

# OS info
uname -a

# Plugin logs (last 20 lines)
tail -20 ~/.config/opencode/PAI/logs/tool-activity.jsonl
```

### Support Channels

- **Issues**: [github.com/anomalyco/opencode/issues](https://github.com/anomalyco/opencode/issues)
- **Documentation**: `PAI/DOCUMENTATION/`
- **Algorithm Help**: Run `/pai "How do I troubleshoot..."` in OpenCode

---

*PAI 5.0.0 — OpenCode Port | Troubleshooting Guide*
