# PAI for OpenCode Architecture

PAI for OpenCode installs PAI into OpenCode's native extension points instead of depending on Claude Code paths or settings.

## Layout

```text
~/.config/opencode/
├── opencode.jsonc
├── plugins/
│   ├── pai-hooks.js
│   └── lib/
│       └── pai-hooks.lib.js
├── agents/
│   └── *.md
├── commands/
│   └── *.md
├── skills/
│   └── */SKILL.md
└── PAI/
    ├── ALGORITHM/
    ├── DOCUMENTATION/
    ├── MEMORY/
    ├── PULSE/
    ├── TOOLS/
    ├── TEMPLATES/
    ├── USER/
    └── bin/
```

## Native OpenCode Surfaces

- Config: `opencode/config/opencode.jsonc.template`
- Plugin: `opencode/plugins/pai-hooks.js`
- Plugin library: `opencode/plugins/lib/pai-hooks.lib.js`
- Agents: `opencode/agents/*.md`
- Commands: `opencode/commands/*.md` plus command entries in config
- Validator: `opencode/bin/validate-pai-installation.sh`

## Default PAI Behavior

Normal OpenCode prompts behave like PAI prompts without requiring `/pai`.

The port does this through two native surfaces:

- `agent.build.prompt` in `opencode.jsonc.template` makes the default primary agent a PAI-aware assistant.
- `experimental.chat.system.transform` in `pai-hooks.js` injects PAI runtime context, identity/TELOS excerpts, recent work, and mode/tier classification rules into the system context.

The port now uses a **two-tier classification approach**:

1. **Explicit Classifier** (`mode-classifier.lib.js`): runs on every top-level prompt via the `chat.message` hook, producing a structured `{ MODE, TIER, REASON, SOURCE }` result. This is persisted to session state and injected into the system context.
2. **Model-native fallback**: the injected system context still includes mode rules, but the model is instructed to honor the explicit classification when present. Self-selection is now fallback/backup behavior, not the primary path.

The classifier is **provider-agnostic** with two tiers:

1. **Heuristic classifier** (default): deterministic, zero cost, zero latency. Runs locally without external dependencies.
2. **LLM classifier** (optional): can be enabled via environment variables to use any model available via `opencode run`. Default target model is `opencode/deepseek-v4-flash-free` (free tier, ~4-5s response). Falls back to heuristic on any error or timeout.

Configuration via environment variables:
```bash
PAI_CLASSIFIER_USE_LLM=true              # Enable LLM classifier
PAI_CLASSIFIER_MODEL=opencode/deepseek-v4-flash-free  # Model name (default)
PAI_CLASSIFIER_TIMEOUT_MS=8000           # Timeout (default: 8s)
```

The LLM classifier uses `opencode run --model <model>` internally and includes LRU caching (100 entries, 5min TTL) to avoid redundant calls for identical prompts. Default model is `opencode/deepseek-v4-flash-free` (~4-5s response time).

**Fail-safe:** any classifier error or low-confidence result defaults to `ALGORITHM E3`. Under-escalation is worse than over-escalation in PAI doctrine.

`/pai` remains as an explicit manual shortcut, but it is not the primary path.

## Plugin Responsibilities

`pai-hooks.js` adapts PAI hook behavior to OpenCode events.

**Runtime reality (v2.12.0, verified against `@opencode-ai/plugin` 1.16 types):** `chat.message`, `tool.execute.*` and the `experimental.*` hooks are real plugin hooks; **session lifecycle and message updates are bus events** delivered through the generic `event` hook, and the permission hook is `permission.ask`. The named handlers below remain the canonical implementations — a runtime adapter at the end of the plugin routes the bus events into them (message content is reconstructed from `message.part.updated`, since real payloads carry text in parts, not `message.content`).

- `session.created`: initialize PAI session state and summarize context availability
- `chat.message`: **classify mode/tier explicitly** AND **pre-sanitize blocked prompts before they reach the model** (replaces denied content with security warning)
- `experimental.chat.system.transform`: **inject full PAI runtime context, identity/TELOS excerpts, and mode-classification rules into every system prompt**
- `experimental.session.compacting`: **preserve PAI context and recent work across context window resets**
- `permission.asked`: block dangerous commands at the permission level with explicit notification
- `tool.execute.before`: inspect risky commands, writes, and egress; **AgentGuard** (agent spawn validation); **SkillGuard** (skill invocation validation)
- `tool.execute.after`: log tool activity and scan fetched content
- `message.updated`: capture ratings/praise and run post-message prompt checks
- `session.idle`: update idle timestamp only
- `session.deleted`: run cleanup, archive, and work-learning behavior where metadata exists

### ISA ↔ Work-State Sync (v2.7.0)

The plugin now maintains stronger parity between ISA frontmatter and `work.json`:

- **Source of truth:** ISA frontmatter (`MEMORY/WORK/**/ISA.md` or legacy `PRD.md`)
- **Derived state:** `work.json` registry
- **Sync trigger:** Any `write`/`edit`/`multiedit` touching an ISA artifact
- **Synced fields:** `phase`, `progress`, `updated`, `effort`, `mode`, `task`/`title`, `status` (`work.json.updatedAt` records sync time)
- **Behavior:**
  - Upserts existing sessions by slug (never duplicates)
  - Falls back to parent directory name when path is outside `MEMORY/WORK`
  - Gracefully handles partial or missing frontmatter
  - Non-ISA writes do not trigger sync
  - Initial sync runs on `session.created` if an ISA already exists for the work directory

This is a **backend-only state sync** with no dashboard, visual, or voice dependency. It works headlessly on VPS and is deployment-agnostic.

### Observability Streams (v2.9.1)

All observability is **file-first, JSONL-only, backend-first** — designed for headless/VPS deployment and future mobile/backend consumers. No dashboards, no visual UI, no voice.

**Storage:** `~/.config/opencode/PAI/MEMORY/OBSERVABILITY/`

| Stream | File | Description |
|--------|------|-------------|
| Mode Classifier | `mode-classifier.jsonl` | Every prompt classification: mode, tier, source, confidence, latency, prompt hash, fallback flag |
| Agent Guard | `agent-guard.jsonl` | Every agent spawn guard decision: decision (allow/warn/deny), rationale, metadata |
| Skill Guard | `skill-guard.jsonl` | Every skill invocation guard decision: decision, rationale, metadata |
| Session Events | `session-events.jsonl` | Session lifecycle transitions: created, idle, archived, deleted, state sync |
| Tool Failures | `tool-failures.jsonl` | Tool execution failures: failure mode, error message, security/permission involvement |
| Subagent Traces | `subagent-trace.jsonl` | Agent/skill execution traces: spawned/invoked events with success/duration |
| **Notifications (contract v1)** | `notifications.jsonl` | Human-relevant events with a deterministic speakable `speak` field — the producer side of the presence layer. Stable contract: `NOTIFICATIONS_STREAM.md` |

**Pulse Broker** (`PAI/broker/pulse-broker.ts`, optional runtime, port 31337) tails `notifications.jsonl` and fans events out over SSE to identified renderers (desktop renderer with Kokoro TTS, mobile app) with per-subscriber routing decisions; `POST /notify` accepts the upstream Pulse payload so inherited agent curls join the same stream. See INSTALL.md and `PULSE_MOBILE_PLAN.md`.

**Schema conventions:**
- Every event has `timestamp` (ISO), `event` (type string), `session_id`
- Payloads are domain-specific and minimal
- `prompt_hash` is a truncated FNV-1a hash for correlation without content exposure
- No PII or full prompt text in observability streams (only truncated previews in classifier)

**Existing streams (pre-v2.9.1):**
- `MEMORY/STATE/tool-activity.jsonl` — all tool usage (success and failure)
- `MEMORY/STATE/security-events.jsonl` — security pipeline blocks and alerts
- `MEMORY/LEARNING/SIGNALS/ratings.jsonl` — explicit ratings and praise
- `MEMORY/LEARNING/signals.jsonl` — learning signals

### AgentGuard / SkillGuard (v2.8.0)

Pre-execution guard rails that reduce bad orchestration decisions:

**AgentGuard** (`tool.execute.before` on `agent`/`task` tools):
- **Trivial lookup detection**: warns when native tools (glob/read/grep) would suffice
- **Fan-out threshold**: warns when session exceeds configured agent count (default: 3)
- **Vague delegation**: warns on underspecified prompts
- **Expensive agent mismatch**: warns when research/deep agents used for trivial tasks
- Decision: `allow` / `warn` / `deny` with logged rationale
- Warn-first; deny only on unambiguous high-confidence misfires

**SkillGuard** (`tool.execute.before` on `skill` tools):
- **Obvious misfire**: denies when high-specificity skill invoked in wrong context (e.g., ArXiv for restaurant search)
- **Trivial request**: warns when native tools would suffice
- **High-cost on trivial**: warns when expensive skills used for simple lookups
- Decision: `allow` / `warn` / `deny` with logged rationale
- Warn-first; deny only on unambiguous misfires

**Observability:**
- `MEMORY/OBSERVABILITY/agent-guard.jsonl`
- `MEMORY/OBSERVABILITY/skill-guard.jsonl`

**Configuration:**
```bash
PAI_AGENTGUARD_FANOUT_MAX=3              # Max agents before warning
PAI_AGENTGUARD_DENY_CONFIDENCE=true      # Enable deny on high-confidence agent misfires
```

## Known Platform Gaps

- ~~Claude Code's Sonnet-based `UserPromptSubmit` classifier is not yet ported~~ — **RESTORED in v2.6.0** via explicit heuristic classifier with provider-agnostic interface. LLM-backed classification is a future enhancement.
- Claude Code's persistent statusline/sidebar is represented as commands and logs.
- Voice remains external-only via Pulse notifications.
- **Pulse runtime remains out of scope for this branch.** The repo ships Pulse configuration scaffolding (`PULSE.toml`, docs, directory layout), but a supported always-on daemon serving `localhost:31337` is not part of current install success criteria.

## Validation

Three-tier validation:

**Structural** (75 checks) — file existence, config validity, agent/skill/plugin presence:
```bash
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

**Behavioral** (57 checks) — grep-based + lightweight functional probes:
```bash
bash ~/.config/opencode/PAI/bin/test-behavioral.sh
```

**Runtime E2E** (10 scenarios) — real runtime flows beyond structural/grep:
```bash
bash ~/.config/opencode/PAI/bin/test-e2e-runtime.sh
```

Current score: **162/162 passing** (81 structural + 70 behavioral + 11 E2E). Parity estimate: **~90-95% over the core scope** — see `REPO_MODEL.md` → "Out of Scope by Design" for what is deliberately excluded.
