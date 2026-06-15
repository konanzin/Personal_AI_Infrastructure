# PAIUpgrade — Example Report

Reference example only. NOT loaded into the workflow at runtime. Consult when uncertain about the canonical output shape.

---

```
User: "check for upgrades"

[Agents run in parallel...]

# PAI Upgrade Report
**Generated:** 2026-01-15 19:45:00 PST
**Sources Processed:** 20 release notes parsed | 5 videos checked | 30 docs analyzed
**Findings:** 3 techniques extracted | 4 content items skipped

---

## ✨ Discoveries

Everything interesting we found, ranked by how cool it is.

| # | Discovery | Source | Why It's Interesting | PAI Relevance |
|---|-----------|--------|---------------------|---------------|
| 1 | OpenCode permission hooks expose a deterministic allow/deny boundary | OpenCode runtime audit | `permission.ask` and `tool.execute.before` let the plugin enforce command policy before execution | SecurityValidator can stay deterministic while still emitting auditable denial reasons |
| 2 | Runtime constitution injection is separated from the user-facing agent file | Local PAI plugin audit | `experimental.chat.system.transform` can load `RUNTIME_CONSTITUTION.md` before `CLAUDE.md` | Keeps the OpenCode port honest without stuffing all doctrine into one file |
| 3 | Commands require explicit config registration | OpenCode config audit | Markdown command files do not matter unless registered in `opencode.jsonc` | Validator can catch stale command promises before install |

---

## 🔥 Recommendations

### 🔴 CRITICAL — Integrate immediately

| # | Recommendation | Prior Status | Evidence | PAI Relevance | Effort | Files Affected |
|---|---------------|-------------|----------|---------------|--------|----------------|
| 1 | Add richer denial reasons to the OpenCode permission adapter | 🆕 NEW | `plugins/pai-hooks.js:permission.asked` currently returns terse denials | Security decisions remain deterministic, but the user gets better audit context | Low | `opencode/plugins/pai-hooks.js` |

### 🟠 HIGH — Integrate this week

| # | Recommendation | Prior Status | Evidence | PAI Relevance | Effort | Files Affected |
|---|---------------|-------------|----------|---------------|--------|----------------|
| 2 | Keep command registration validated against `opencode.jsonc` | 🔶 PARTIAL | `opencode/bin/validate-promise-integrity.sh` checks registered commands | Prevents a markdown command from being documented but unreachable at runtime | Low | `opencode/bin/validate-promise-integrity.sh` |

(MEDIUM and LOW tiers omitted — no items.)

---

## 🎯 Technique Details

### From Release Notes

#### 1. Permission Hook Denial Reasons
**Source:** OpenCode runtime audit
**Priority:** 🔴 CRITICAL

**What It Is:** OpenCode permission hooks can return structured allow/deny behavior before a tool executes.

**How It Helps PAI:** PAI can keep deterministic command enforcement while making the reason for a denial visible and auditable.

**The Technique:**
```typescript
return { behavior: "deny", message: "Protected PAI user file" };
```

**Applies To:** `opencode/plugins/pai-hooks.js`

---

#### 2. Command Registration Validation
**Source:** OpenCode config audit
**Priority:** 🟠 HIGH

**What It Is:** Command markdown files are only executable when registered in the OpenCode config.

**How It Helps PAI:** The port can fail validation when a command is copied but not exposed to the runtime.

**The Technique:**
```bash
bash opencode/bin/validate-promise-integrity.sh --repo
```

**Applies To:** `opencode/bin/validate-promise-integrity.sh`

---

## 📊 Summary

| # | Technique | Source | Priority | PAI Component | Effort |
|---|-----------|--------|----------|---------------|--------|
| 1 | PreToolUse Additional Context | claude-code v2.1.16 | 🔴 | SecurityValidator hook | Low |
| 2 | Session ID Substitution | claude-code v2.1.16 | 🟠 | DocumentSession workflow | Low |

**Totals:** 1 Critical | 1 High | 0 Medium | 0 Low | 4 Skipped

## ⏭️ Skipped Content

| Content | Source | Why Skipped | Evidence |
|---------|--------|-------------|----------|
| MCP auto mode | claude-code v2.1.16 | ✅ DONE — already enabled by default | `settings.json:18` |
| Gemini 3 videos | YouTube | Not relevant to Claude-centric stack | — |
| Agent Experts video | YouTube | No concrete technique identified | — |
| SDK update v0.78 | GitHub | PAI uses CLI, not raw SDK | `CLAUDE.md:12` |

## 🔍 Sources Processed
30 Anthropic sources, 5 YouTube videos, 0 custom → 2 relevant findings
```
