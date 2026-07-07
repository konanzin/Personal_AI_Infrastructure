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
- Tools manifest: `PAI/TOOLS/manifest.json`, validated by `opencode/bin/validate-tools-manifest.js`

## Default PAI Behavior

Normal OpenCode prompts behave like PAI prompts without requiring `/pai`.

The port does this through two native surfaces:

- `agent.build.prompt` in `opencode.jsonc.template` makes the default primary agent a PAI-aware assistant.
- `experimental.chat.system.transform` in `pai-hooks.js` injects PAI runtime context, identity/TELOS excerpts, recent work, and mode/tier classification rules into the system context.

The port now uses a **two-tier classification approach**:

1. **Explicit Classifier** (`mode-classifier.lib.js`): runs on every top-level prompt via the `chat.message` hook, producing a structured `{ MODE, TIER, REASON, SOURCE }` result. This is persisted to session state and injected into the system context.
2. **Model self-selection**: the injected system context includes the mode rules and the classifier result as a **suggestion** — the model adopts it when it matches its own read of the request and overrides it (either direction) when it does not. Only an explicit user `/e1`–`/e5` override is binding, including its expanded slash-command form "Run PAI effort EN for: …" (drift register W1.2, Algorithm v6.3.3; thinking floor soft since v6.3.4, W2.8).

The classifier is **provider-agnostic** with two tiers:

1. **LLM classifier** (default): uses a model available via `opencode run`, matching original PAI's model-first classifier shape. Defaults to `PAI_CLASSIFIER_MODEL`, then the configured OpenCode bench model (`PAI_OPENCODE_PROVIDER/PAI_OPENCODE_MODEL`), then `opencode/deepseek-v4-flash-free`.
2. **Heuristic classifier** (offline/debug path): deterministic, zero cost, zero latency. Used only when the LLM classifier is explicitly disabled. LLM errors/timeouts fail-safe to `ALGORITHM E3`, matching original PAI.

Configuration via environment variables:
```bash
PAI_CLASSIFIER_USE_LLM=true              # Default. Set false only for offline/debug runs.
PAI_CLASSIFIER_MODEL=openai/gpt-5.5      # Optional dedicated classifier model.
PAI_CLASSIFIER_TIMEOUT_MS=25000          # Timeout (default: 25s, matching original PAI shape)
```

The LLM classifier uses `opencode run --pure --model <model>` internally and includes LRU caching (100 entries, 5min TTL) to avoid redundant calls for identical prompts. `--pure` prevents recursive plugin execution during classification.

**Fail-safe:** any LLM classifier error/timeout defaults to `ALGORITHM E3` (a failure means we know nothing — stay conservative). Distinct from that, when the classifier is *working but uncertain* between NATIVE and ALGORITHM it now prefers NATIVE (2026-07-04). Be precise about why, because there is **no mid-task re-classification** — a misroute is not auto-corrected in either direction. The asymmetry is in the cost: a complex task misrouted NATIVE still gets done by the same model, just without the ALGORITHM scaffolding (and the user can force it with `/e1`–`/e5` or `/pai`); a trivial task misrouted ALGORITHM pays the full ceremony tax every single time — which the first golden-eval measurement showed happening systematically. The under-escalation side of this trade is measured, not assumed: the golden set carries explicit escalation-risk probes (short vague imperatives that must stay ALGORITHM). Set `PAI_CLASSIFIER_USE_LLM=false` only for offline/debug runs.

`/pai` remains as an explicit manual shortcut, but it is not the primary path.

## Plugin Responsibilities

`pai-hooks.js` adapts PAI hook behavior to OpenCode events.

**Runtime reality (v2.13.0, verified against `@opencode-ai/plugin` 1.16 types):** `chat.message`, `tool.execute.*`, custom `tool` definitions, and the `experimental.*` hooks are real plugin hooks; **session lifecycle and message updates are bus events** delivered through the generic `event` hook, and the permission hook is `permission.ask`. The named handlers below remain the canonical implementations — a runtime adapter at the end of the plugin routes the bus events into them (message content is reconstructed from `message.part.updated`, since real payloads carry text in parts, not `message.content`). Final voice is intentionally **not** parsed from streamed text: agents call the native `pai_notify` tool with `message` and `language`.

- `session.created`: initialize PAI session state and summarize context availability
- `chat.message`: **classify mode/tier explicitly** AND **pre-sanitize blocked prompts before they reach the model** (replaces denied content with security warning)
- `experimental.chat.system.transform`: **inject full PAI runtime context, identity/TELOS excerpts, and mode-classification rules into every system prompt**
- `experimental.session.compacting`: **preserve PAI context and recent work across context window resets**
- `permission.asked`: rule-based SmartApprover surface for risky bash/read/write requests; denies zero-access reads and emits `permission_needed` notifications for approval-worthy operations
- `tool.execute.before`: inspect risky commands, sensitive reads, writes, egress, and high-confidence secret containment leaks; **AgentGuard** (agent spawn validation); **SkillGuard** (skill invocation validation)
- `tool.execute.after`: log tool activity, scan fetched content, sync ISA state, and record allowlist-only ISC checkpoints
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

### CheckpointPerISC (v2.13.0)

The port implements per-ISC durability inside the OpenCode plugin instead of a separate Claude Code hook:

- Trigger: `tool.execute.after` on write/edit/multiedit of `ISA.md` or legacy `PRD.md`
- Criteria parser: completed `ISC-*` lines are detected from the ISA body
- Opt-in: only repos listed in `PAI/checkpoint-repos.txt` are committed
- Idempotency: `MEMORY/WORK/{slug}/.checkpoint-state.json`
- Rollback: `PAI/TOOLS/Checkpoint.ts rollback <slug> <isc-id>` prints preview commands only

No repo outside the allowlist is committed, and no destructive rollback command is executed automatically.

### Runtime Tools

`PAI/TOOLS/manifest.json` is the active tools contract. The current core tool surface includes provider wrappers (`Inference`, `AnvilProgress`, `CrossVendorAudit`, `Arthur`), memory tools (`MemoryRetriever`, `KnowledgeGraph`, `SessionHarvester`, `KnowledgeHarvester`), and checkpoint inspection (`Checkpoint`). Optional skill-specific helpers remain optional and must be checked before use.

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

**Pulse Broker** (`PAI/broker/pulse-broker.ts`, optional runtime, port 31337) tails `notifications.jsonl` and fans events out over SSE to identified renderers (desktop renderer with Edge TTS by default and optional `PULSE_TTS_CMD`, mobile app) with per-subscriber routing decisions. Normal install prepares the managed Edge TTS venv at `~/.config/opencode/tts-venv`; `--no-bootstrap` skips all dependency bootstrap, while `--no-tts-bootstrap` skips only the optional desktop voice dependency for mobile-only remote bootstraps. `POST /notify` exists only as legacy compatibility for inherited startup/progress messages; speaking payloads require `language`. See `NOTIFICATIONS_STREAM.md` and `PAI/PULSE/README.md`.

**Schema conventions:**
- Every event has `timestamp` (ISO), `event` (type string), `session_id`
- Payloads are domain-specific and minimal
- `prompt_hash` is a truncated FNV-1a hash for correlation without content exposure
- No PII or full prompt text in observability streams (only truncated previews in classifier)
- Stable JSON Schema files ship in `opencode/schemas/` and install to `~/.config/opencode/PAI/schemas/`
- Consumer rules and stream/schema mapping are documented in `OBSERVABILITY_CONTRACTS.md`

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

- ~~Claude Code's Sonnet-based `UserPromptSubmit` classifier is not yet ported~~ — **RESTORED** as an OpenCode-native LLM-first classifier with provider/model selection and deterministic heuristic fallback.
- Claude Code's persistent statusline/sidebar is represented as commands and logs.
- Voice remains outside the core agent loop and is delivered by optional Pulse renderers; desktop voice defaults to the installer-prepared Edge TTS provider.
- The upstream desktop Pulse daemon remains out of scope. This branch ships a lean optional Pulse Broker on port 31337 (`PAI/broker/`) for notifications and renderer fan-out, but a running broker is not part of install success criteria.

## Validation

Three-tier validation:

**Structural** (112 checks) — file existence, config validity, agent/skill/plugin presence, observability schemas, tools manifest, Edge TTS dependency readiness, `/voice` helper readiness, and doc integrity:
```bash
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

**Behavioral** (109 checks) — grep-based + lightweight functional probes:
```bash
bash ~/.config/opencode/PAI/bin/test-behavioral.sh
```

**Runtime E2E** (11 scenarios) — real runtime flows beyond structural/grep:
```bash
bash ~/.config/opencode/PAI/bin/test-e2e-runtime.sh
```

Repository test suite: run `cd opencode && bun test` for the authoritative, current count — do **not** trust a hardcoded number in prose (several docs cite conflicting stale counts; that drift is itself tracked in `HARNESS_QUALITY.md`). Parity estimate: **~95% over the core scope** — see `REPO_MODEL.md` → "Out of Scope by Design" for what is deliberately excluded; note that this figure is a hand-graded estimate, not an executed cross-runtime comparison (also tracked in `HARNESS_QUALITY.md`).

### Quality model & health checks

`opencode/docs/HARNESS_QUALITY.md` is the north-star: what "better" means (five objectives), the proxies that have drifted, and the regression fences that catch drift. On-demand health tools:

```bash
bun opencode/bin/monitor-classifier-health.js   # LLM-classifier degradation: ok/warn/alert (exit 0/1/2)
bun opencode/bin/recall-feedback.js             # recall past low-rating feedback (read-only); also /feedback command
```

Regression fences worth knowing: `security-corpus.test.ts` (deny-floor catch-rate + false-positive-rate, with `test.failing` gaps that flip red when fixed), `floor-liveness.test.ts` (floor fires under both arg shapes — anti-`b6ec6a8f`), and `observability-schemas.test.ts` (strict emitter-vs-schema round-trip). The T1 sandbox is provisioned and confinement-verified by `install.sh` and re-checked by `install.sh --check`.
