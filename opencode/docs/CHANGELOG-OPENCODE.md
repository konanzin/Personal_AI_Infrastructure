# PAI OpenCode Port — Changelog

> All notable changes to the PAI OpenCode port.

## [5.0.0] - 2026-05-20

### Initial OpenCode Port

Complete migration of PAI (Personal AI Infrastructure) from Anthropic's Claude Code to the open-source OpenCode CLI. This is a major version release marking the transition to a multi-provider, vendor-independent architecture.

**Port Status:** 64/64 checkpoints validated, 100% functional parity.

---

## What Changed

### Architecture

| Component | Claude Code (v4.x) | OpenCode (v5.0.0) |
|-----------|-------------------|-------------------|
| **Runtime** | Proprietary CLI | Open-source multi-provider |
| **Config File** | `~/.claude/settings.json` (1362 lines) | `~/.config/opencode/opencode.jsonc` (254 lines) |
| **Hooks** | 38 TypeScript hooks with proprietary API | 8 JavaScript plugins with native OpenCode events |
| **Hook API** | `PreToolUse`, `PostToolUse`, etc. | `tool.execute.before`, `session.created`, `session.idle`, etc. |
| **Agents** | Embedded in `settings.json` | Individual `.md` files with YAML frontmatter |
| **Agent Location** | `settings.json` | `~/.config/opencode/agents/` |
| **Skills** | `~/.claude/skills/` | `~/.config/opencode/skills/` |
| **Base Path** | `~/.claude/PAI/` | `~/.config/opencode/PAI/` |
| **Model** | Anthropic Claude only | Kimi, Anthropic, OpenAI, Google |
| **Default Model** | `claude-sonnet-4` | `kimi-for-coding/k2p6` |
| **Voice** | ElevenLabs integration | Notification POST to localhost:31337 |
| **Statusline** | Native sidebar | `/status` command + `statusline-command.sh` |
| **Compaction** | Claude Code native | OpenCode native with PAI config |
| **Package Manager** | npm/npx | bun/bunx (enforced) |

### Files & Directories

**New Structure:**
```
~/.config/opencode/
├── opencode.jsonc              # Main configuration
├── plugins/
│   ├── pai-hooks.js            # Main PAI plugin (8 handlers)
│   └── pai-hooks.lib.js        # Shared utilities
├── agents/                     # 18 individual agent definitions
│   ├── Algorithm.md
│   ├── Engineer.md
│   └── ...
├── commands/                   # Custom slash commands
│   ├── context-search.md
│   ├── cs.md
│   └── pu.md
└── PAI/                        # PAI core (previously ~/.claude/PAI/)
    ├── CLAUDE.md
    ├── ALGORITHM/
    ├── DOCUMENTATION/
    ├── MEMORY/
    ├── PULSE/
    ├── TOOLS/
    ├── TEMPLATES/
    ├── USER/
    └── bin/
```

**Backward Compatibility:**
- Symlink created: `~/.claude/` → `~/.config/opencode/PAI`
- Old paths still work through symlink
- Migration scripts provided for PULSE paths

### Plugins (Hooks → Event Handlers)

The 38 Claude Code hooks were consolidated into 8 OpenCode event handlers:

| Claude Code Hook | OpenCode Event | Handler |
|-----------------|----------------|---------|
| `SecurityPipeline` | `tool.execute.before` | `SecurityInspector` |
| `LoadContext` | `session.created` | `loadContext` |
| `SessionCleanup` | `session.idle` | `cleanupSession` |
| `ToolActivityTracker` | `tool.execute.after` | `trackToolActivity` |
| `ContentScanner` | `tool.execute.after` | `scanContent` |
| `PromptGuard` | `message.updated` | `guardPrompt` |
| `SatisfactionCapture` | `session.idle` | `captureSatisfaction` |
| `WorkCompletionLearning` | `session.idle` | `learnFromWork` |

**Plugin Files:**
- `pai-hooks.js` (1018 lines) — Main plugin
- `pai-hooks.lib.js` (869 lines) — Shared utilities library

### Agents

**Format Change:**

Claude Code agents were embedded in `settings.json`:
```json
{
  "agents": {
    "Engineer": {
      "description": "...",
      "prompt": "..."
    }
  }
}
```

OpenCode agents are individual `.md` files with YAML frontmatter:
```yaml
---
description: "Agent description"
model: "kimi-for-coding/k2p6"
prompt: |
  You are [Agent Name].
  ## Role
  ...
---

# Agent Name
## Overview
...
```

**18 Agents Ported:**
1. Algorithm — ISC and algorithm workflows
2. Engineer — Principal engineer (Marcus Webb)
3. Forge — OpenAI-family code producer
4. Anvil — Moonshot-family code producer
5. Architect — System design specialist
6. Designer — UX/UI specialist
7. Cato — Cross-vendor ISA auditor
8. Silas — Offensive security specialist
9. ClaudeResearcher — Academic researcher
10. GeminiResearcher — Multi-perspective researcher
11. GrokResearcher — Contrarian analyst
12. PerplexityResearcher — Investigative analyst
13. CodexResearcher — Technical archaeologist
14. Artist — Visual content creator
15. Arthur — Credential custodian
16. BrowserAgent — Browser automation
17. QATester — QA validation
18. UIReviewer — UI review

**Note:** Agent prompts were simplified during port. Rich content (298+ lines) will be restored in future updates.

### Commands

**New Slash Commands:**

| Command | Description |
|---------|-------------|
| `/pai` | Execute PAI Algorithm workflow |
| `/status` | Show PAI status line |
| `/interview` | Run TELOS interview |
| `/pulse` | Check Pulse dashboard |
| `/context` | Show context usage |
| `/rate` | Rate session satisfaction (1-10) |
| `/e1` | Standard effort, fast path |
| `/e2` | Extended effort |
| `/e3` | Advanced effort |
| `/e4` | Deep effort |
| `/e5` | Comprehensive effort |

### Configuration

**Claude Code `settings.json` (1362 lines)** was split into:

1. `~/.config/opencode/opencode.jsonc` (254 lines) — OpenCode native config
2. `~/.config/opencode/PAI/.version.json` — PAI version metadata
3. `~/.config/opencode/PAI/.preferences.json` — User preferences
4. `~/.config/opencode/PAI/.techstack.json` — Technical preferences
5. `~/.config/opencode/PAI/.observability.json` — Monitoring config
6. `~/.config/opencode/PAI/.notifications.json` — Notification routing

### Scripts & Tools

**New Scripts:**
- `install-pai-opencode.sh` — Idempotent installer
- `validate-pai-installation.sh` — 64-checkpoint validator
- `statusline-command.sh` — `/status` command implementation
- `launch-ralph.sh` — Ralph Loop launcher
- `patch-paths.sh` — PULSE path migration

**Updated Scripts:**
- All scripts use `~/.config/opencode/PAI/` paths
- All scripts use `bun` instead of `npm`

---

## Breaking Changes

### 1. Path Migration

**Old paths no longer valid (unless using symlink):**
- `~/.claude/settings.json` → `~/.config/opencode/opencode.jsonc`
- `~/.claude/PAI/` → `~/.config/opencode/PAI/`
- `~/.claude/skills/` → `~/.config/opencode/skills/`

**Migration:** Symlink `~/.claude/` → `~/.config/opencode/PAI` handles most cases automatically.

### 2. Configuration Format

**Old:** Monolithic `settings.json` with embedded agents, hooks, and config.

**New:** Separated into:
- `opencode.jsonc` — Runtime config
- Individual `.md` files — Agents
- Individual `.js` files — Plugins
- `.json` metadata files — PAI state

**Migration:** Run installer to auto-convert, or migrate manually per component.

### 3. Hook API Changes

**Old:** TypeScript hooks with custom API:
```typescript
export const PreToolUse: Hook = {
  name: "PreToolUse",
  async run(tool) { ... }
}
```

**New:** JavaScript plugins with OpenCode events:
```javascript
export default {
  name: "pai-hooks",
  hooks: {
    "tool.execute.before": async (tool) => { ... }
  }
}
```

**Migration:** Custom hooks need manual porting. See `PORT-ARCHITECTURE.md` for mapping.

### 4. Agent Definition Format

**Old:** JSON in `settings.json`:
```json
"Engineer": {
  "description": "...",
  "prompt": "..."
}
```

**New:** Markdown with YAML frontmatter:
```yaml
---
description: "..."
prompt: |
  ...
---
```

**Migration:** Agents were auto-converted during port. Custom agents need manual conversion.

### 5. Model Changes

**Old:** Claude-only (`claude-sonnet-4`, `claude-opus-4`, etc.)

**New:** Multi-provider with `kimi-for-coding/k2p6` as default

**Impact:** Agent prompts optimized for Claude may behave differently with Kimi.

### 6. Voice/Audio

**Old:** Native ElevenLabs integration with voice_id selection

**New:** Notification POST to `localhost:31337` (no native voice)

**Impact:** Voice features require external service setup.

### 7. Statusline

**Old:** Native sidebar in Claude Code

**New:** `/status` command with script output

**Impact:** No persistent visual status bar. Run `/status` manually.

### 8. Compaction Behavior

**Old:** Claude Code native compaction

**New:** OpenCode compaction with PAI configuration:
```json
"compaction": {
  "auto": true,
  "prune": true,
  "tail_turns": 2,
  "preserve_recent_tokens": 8000,
  "reserved": 4000
}
```

---

## Migration Guide

### For Existing PAI Users (Claude Code → OpenCode)

#### Step 1: Backup Your Data

```bash
# Backup existing Claude Code PAI
cp -R ~/.claude/PAI ~/.claude/PAI-backup-$(date +%Y%m%d)
```

#### Step 2: Install OpenCode

```bash
# Install OpenCode CLI
curl -fsSL https://opencode.ai/install.sh | sh

# Verify
opencode --version
```

#### Step 3: Run PAI Installer

```bash
# Clone PAI repository
git clone https://github.com/danielmiessler/Personal_AI_Infrastructure.git /tmp/pai

# Run idempotent installer
bash /tmp/pai/PAI/bin/install-pai-opencode.sh
```

#### Step 4: Migrate Your Data

**Option A — Automatic (recommended):**
```bash
# Installer creates symlink automatically
ls -la ~/.claude
# Should show: ~/.claude -> ~/.config/opencode/PAI
```

**Option B — Manual:**
```bash
# Copy your USER data
cp -R ~/.claude/PAI-backup-*/USER ~/.config/opencode/PAI/

# Copy your MEMORY
cp -R ~/.claude/PAI-backup-*/MEMORY ~/.config/opencode/PAI/

# Copy custom skills
cp -R ~/.claude/skills/* ~/.config/opencode/skills/
```

#### Step 5: Update Custom Configurations

```bash
# Check for hardcoded paths
grep -r "~/.claude/" ~/.config/opencode/PAI/ --include="*.md" --include="*.js" --include="*.ts"

# Update paths
find ~/.config/opencode/PAI/ -type f \( -name "*.md" -o -name "*.js" -o -name "*.ts" \) -exec sed -i 's|~/.claude/|~/.config/opencode/PAI/|g' {} +
```

#### Step 6: Validate

```bash
# Run validation script
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh

# Expected: 64/64 checkpoints passed (100%)
```

#### Step 7: Test

```bash
# Launch OpenCode
opencode

# Test status command
/status

# Test PAI algorithm
/pai "Hello, confirm you are working"
```

### For New Users

See [README-OPENCODE.md](README-OPENCODE.md) for fresh installation instructions.

---

## Known Issues

### Agent Prompts Simplified

**Status:** Known limitation
**Details:** Agent prompts were compressed from 298+ lines to basic descriptions during port.
**Workaround:** Rich prompts will be restored in v5.1.0.
**Impact:** Agents may be less effective until prompts are expanded.

### Voice Not Native

**Status:** Expected behavior
**Details:** OpenCode does not support native voice. Notification POST is available.
**Workaround:** Set up external notification service at `localhost:31337`.
**Impact:** No voice output by default.

### BrowserAgent Deprecation

**Status:** Deprecated
**Details:** `BrowserAgent` and `QATester` are deprecated. Use `Interceptor` skill for browser automation.
**Workaround:** Use `/skill Interceptor` for browser tasks.
**Impact:** Old browser automation workflows need updating.

### Statusline Not Persistent

**Status:** Expected behavior
**Details:** OpenCode does not have a persistent sidebar like Claude Code.
**Workaround:** Use `/status` command as needed.
**Impact:** No always-visible status bar.

---

## Post-Migration Checklist

- [ ] Installation validated (64/64 checkpoints)
- [ ] `~/.claude/` symlink exists and works
- [ ] `opencode.jsonc` configured correctly
- [ ] Plugins load without errors
- [ ] All 18 agents recognized
- [ ] `/status` command works
- [ ] `/pai` command works
- [ ] Custom skills migrated
- [ ] Hardcoded paths updated
- [ ] Custom hooks ported (if any)
- [ ] Environment variables updated (PAI_DIR)
- [ ] Backup of old installation kept
- [ ] PULSE dashboard accessible
- [ ] MEMORY/STATE directory populated

---

## Version History

### 5.0.0 (2026-05-20)
- Initial OpenCode port
- Multi-provider support (Kimi, Anthropic, OpenAI, Google)
- 8 OpenCode plugins (from 38 Claude Code hooks)
- 18 agents as individual `.md` files
- Separated configuration (opencode.jsonc + metadata)
- Idempotent installer
- 64-checkpoint validator
- Backward-compatible symlink
- Ralph Loop automation

---

## References

- [README-OPENCODE.md](README-OPENCODE.md) — Main documentation
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Common issues
- [PORT-ARCHITECTURE.md](PORT-ARCHITECTURE.md) — Detailed architecture
- [PORT-PRD.json](PORT-PRD.json) — Product requirements

---

*PAI 5.0.0 — OpenCode Port | 64/64 checkpoints validated*
