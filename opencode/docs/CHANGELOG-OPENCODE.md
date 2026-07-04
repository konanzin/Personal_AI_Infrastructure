# PAI OpenCode Port Changelog

This file is an append-only history of notable port changes. It is not the
source of truth for current install status, validation counts, or roadmap
state. Use `README.md`, `REPO_MODEL.md`, `INSTALL.md`, and
`opencode/docs/README-OPENCODE.md` for the current operational picture.

## [Unreleased] — Port Coherence Pass + Mobile Lean Profile

### Added

- **Harness quality baseline + proxy-drift register** (`opencode/docs/HARNESS_QUALITY.md`) — defines what "better" means for the harness as five real objectives (O1–O5), each with the metric that actually measures it vs. the proxy that was being watched, and a register of confirmed drift (each row verified by executing the real code). Start here to understand the quality model. Authoritative test count lives in `bun test`, not in prose.
- **Security deny-floor corpus** (`tests/security-corpus.test.ts`) — a golden must-block/must-allow corpus over the real inspectors, printing catch-rate and false-positive-rate every run. The must-allow set is seeded from real `tool-activity.jsonl` history. Confirmed gaps are pinned with Bun `test.failing` so the suite stays green today but turns **red the moment the gap is fixed**, forcing promotion to a permanent fence. Documents live floor gaps: root/home glob wipes (`rm -rf /*`) only alert; `find -delete`/`shred`/`git clean` unmodeled; `/etc/ssl/private/*.key` readable; `~/.ssh/authorized_keys` writable; `.env` guard over-blocks `app.env.example`.
- **Floor-liveness matrix** (`tests/floor-liveness.test.ts`) — the anti-`b6ec6a8f` fence generalized: drives the real `tool.execute.before` hook with **both** arg shapes (`input.args` and `output.args`) for every dangerous tool, so an arg-shape change can never silently disable the floor through a tool a point-fix forgot. Pins the fail-open-on-inspector-crash behavior as a known gap.
- **T1 sandbox guaranteed at install** — `install.sh` now `install_bwrap()` (bootstraps bubblewrap across apt/pacman/dnf/zypper/apk; Linux-only; warns, never aborts — fail-open by design) and `verify_sandbox()` (post-install confinement probe: a write to `$HOME` from `/tmp` must be refused → `CONFINED`, else `LEAK`/degraded). Reports a `T1 sandbox:` status; `install.sh --check` re-asserts it on every drift check; `installer-hygiene.test.ts` pins the wiring so it can't regress out of the installer.
- **Classifier health monitor** (`opencode/bin/monitor-classifier-health.js` + `plugins/lib/classifier-health.lib.js`, tested in `classifier-health.test.ts`) — reads `mode-classifier.jsonl` and returns ok/warn/alert on the share of classifications that degraded off the intended (LLM) path; exit 0/1/2 for cron/`/loop`/CI. The first live consumer of a previously write-only stream — catches the production LLM classifier silently degrading to heuristic/fail-safe.
- **Observability emitter-vs-schema round-trip** — `observability-schemas.test.ts` rewritten to drive the **real** emitters/hooks in a subprocess (`tests/helpers/emit-observability-events.mjs`, `PAI_DIR`→tmp) and validate what actually lands on disk with a **strict** validator that flags any undeclared key. All six streams round-trip; guard-the-guard tests prove strict mode catches a renamed or dropped field. Schema and emitter can no longer drift silently.
- **On-demand low-rating feedback recall** (`opencode/bin/recall-feedback.js` + `plugins/lib/feedback-recall.lib.js`, tested in `feedback-recall.test.ts`) — reads the low-rating archive back and surfaces recent comments + recurring themes. Exposed as the **`/feedback`** command. Deliberately **read-only and on-demand**: it never auto-injects into a prompt and never mutates config/rules/memory (auto-injection and self-modifying-harness options were considered and rejected as Goodhart risks). Closes the last write-only observability loop.
- **Quality-harness review hardening** (addressing a review that the fences were themselves partly proxies):
  - `security-corpus.test.ts`: added a **ratchet** — each known-gap case with a better-than-worst state carries a real (non-`test.failing`) assertion that it hasn't dropped below its documented `floor`, so a gap degrading (e.g. `rm -rf /*` from `alert`→`allow`) fails the suite *now*, not only when fully fixed. Corpus paths use `homedir()` instead of a hardcoded home, so the suite is portable.
  - `floor-liveness.test.ts`: the fail-closed check is now **real fault injection** (a throwing getter on `args.command` raises a non-`BLOCKED` error inside the hook) instead of a placeholder constant, and the arg-shape matrix now covers `edit`/`multiedit` — every tool the real write floor routes.
  - `mode-classifier.jsonl` now records **`use_llm` per event** — emitted by both the main and fail-safe classifier paths (`classifierConfig` hoisted so the catch can see it) and marked **required** in the schema, so the strict round-trip goes red if a future refactor drops it (closing the silent-fallback regression a review flagged); `monitor-classifier-health.js` / the analyzer resolve intent per row and still tolerate the field's absence on legacy rows.
  - `install.sh --check` now runs the **real confinement probe** (`verify_sandbox`) rather than checking bwrap presence only, so a present-but-degraded sandbox (e.g. user namespaces disabled) is caught; `PAI_SANDBOX=off` is reported as an operator override.
- **Deny-floor gaps FIXED + corpus fences promoted (2026-07-04)** — all 13 gaps the corpus had pinned are closed in the policy (bundled default in `pai-hooks.lib.js` **and** `PAI/DOCUMENTATION/Security/Patterns.example.yaml`; the installed user copy was refreshed from the template — it had gone stale, see below): root/home **glob wipes** (`rm -rf /*`, `/home/*`, `~/*`, `$HOME/*`, quoted/`bash -c` variants) now deny; **top-level system dirs** (`rm -rf /etc`, `/usr/*`, …) deny; **`find -delete`** rooted at `/`, `~`, `$HOME` or a whole home deny (deeper roots stay legitimate cleanup); **`shred`** denies; **`git clean` with `-x`+force** denies (plain `git clean -fd` gets a new alert-tier audit line); `/etc/ssl/private/**` added to zeroAccess; `~/.ssh/authorized_keys*` added to readOnly (SSH-backdoor write). The **`.env` shell-read guard was narrowed**: `foo.env`, `app.env.example`, `.env.sample` and other template/basename false positives now pass while `.env`, `.env.local`, `config/.env.production` still deny. All 13 `test.failing` fences flipped red on cue and were promoted to permanent; the corpus gained 11 adversarial phrasings (sudo/quoting/`bash -c`/split flags) and 11 near-miss must-not-block cases. Scoreboard: **33/35 catch (2 documented shell-state gaps at alert floor: cwd indirection, pipe-fed targets — the T1 bwrap layer's job), 0/29 false positives**. The must-not-block suite now asserts O2 precisely: `deny`/`require_approval` fail, `alert` passes (it logs and runs).
- **Stale-policy drift discovered AND fenced**: the installed `PATTERNS.yaml` predated the curated miner/reverse-shell additions — `install.sh` seeds it only when absent, so template improvements never propagate to existing installs. Now the policy `version:` line (`3.2-opencode`) is the drift signal: `install.sh --check` compares installed vs `Patterns.example.yaml` and fails with "Security policy STALE" on mismatch (customized installs keep edits and merge). Red-path test in `installer-hygiene.test.ts`; the fixture seeds the real template. Live copy refreshed (backup kept).
- **Review fixes on the gap-fix round** (second-pass review caught three real holes): (1) the `.env` fix only covered the bash guard — the Read/Write path tier still zero-accessed `**/.env.*`; path globs now support **`!` exemptions** and zeroAccess exempts `.env` template suffixes, with corpus fences both ways — and a third-round review caught that the first exemption implementation nullified the whole tier (letting `/etc/ssl/private/.env.example` bypass zeroAccess); exemptions now pierce only floating `**/` globs while directory-anchored protections stay absolute, with anti-bypass fences pinning both protected-dir cases; (2) `git clean -n -xfd` / `--dry-run -xfd` previews were denied — the deny pattern now exempts dry-runs (they land on the alert tier); (3) `eval-classifier-golden.js` no longer overrides `fallback` — it inherits production's `PAI_CLASSIFIER_FALLBACK` resolution so the eval measures what the running config would actually do.
- **Classifier golden eval — O3 correctness finally measured** (`opencode/bin/eval-classifier-golden.js` + `plugins/lib/classifier-golden.lib.js`, tested in `classifier-golden.test.ts`) — the health monitor proves the LLM path is *alive*; this proves it is *right*. A 22-case golden set (clear-cut prompts only; mode graded strictly, tier as accepted-set membership) is driven through `classifyPromptWithLLM` — the exact function production calls. On-demand (`--model`/`--heuristic`/`--limit`/`--json`, exit 0/1/2). First measurements: **production LLM path 82% mode / 100% tier (WARN)** — it consistently routes trivial fully-specified edits (rename a file, fix a typo, bump a version) to ALGORITHM-E1 instead of NATIVE; **offline heuristic baseline 77% / 64%**, printed informationally on every `bun test` run.
- **`hooks-parity.test.ts` renamed to `hooks-helpers.test.ts`** — the old name implied cross-runtime parity verification; the file is 5 helper unit tests that compare nothing against upstream. Parity (O4) remains an estimate until a real cross-runtime comparison exists.
- **`classifier-health.lib.js` llmRate** now uses the same per-row `use_llm` intent as the degraded metric, so windows mixing useLLM=true/false traffic don't understate the healthy share.

- **Native `pai_notify` voice tool** — final voice is now an explicit OpenCode tool call instead of parsing `🎯 COMPLETED` from `message.part.updated`. The tool requires `message` and `language` (`pt-BR` or `en-US`), emits `agent_completed` with `source: "pai_notify"`, and dedupes per response message. `🎯 COMPLETED` remains a visible final-line convention only. Legacy `/notify` stays for inherited startup/progress curls and now requires `language` for speaking payloads.
- **Runtime event bridge (plugin v2.12.0)** — first validation against a real `opencode serve` (1.16.2) exposed that session/message hooks never fired: on the current plugin surface `chat.message`, `tool.execute.*`, custom `tool` definitions and `experimental.*` are real hooks, but session lifecycle and message updates are **bus events** (generic `event` hook) and the permission hook is `permission.ask`. The plugin now bridges `session.created/idle/deleted` to the named handlers; post-message inspection and satisfaction capture are fed from `message.part.updated` (content lives in parts, not `message.content`) with a role/agent cache and per-part dedupe. Also fixed: `install.sh` renders the plugin path **absolute** in `opencode.jsonc` — OpenCode resolves relative plugin paths against the server CWD, so `./plugins/...` silently failed to load under the systemd service.
- **Edge TTS for the desktop renderer** — `--tts` uses the bundled `edge-tts-speaker.ts` by default. It auto-installs `edge-tts` into `~/.config/opencode/tts-venv`, selects voices from event `language`, and can be replaced entirely with `PULSE_TTS_CMD`. Setup in INSTALL.md.
- **Pulse Broker (Phase C1/C2)** — `opencode/broker/`, installed to `PAI/broker/`, optional runtime on port 31337. Tails `notifications.jsonl` (fs.watch + offset, 1s safety interval, truncation-aware) and fans events out over SSE to identified subscribers (`GET /subscribe?device=&name=&focus=`), each delivery carrying a per-subscriber render decision and a `dedupe_key`. Routing policy v1 in pure `broker-lib.ts`: `attention` always speaks; a subscriber displaying the event's session suppresses voice for other subscribers (badge-only); mute via `POST /presence`. `POST /notify` accepts the upstream Pulse payload and appends it to the same stream (inherited agent curls work; their health gates now pass against `/health` and `/api/pulse/health`). `renderer-desktop.ts` is the reference consumer (notify-send + Edge TTS by default, `PULSE_TTS_CMD` override). User systemd unit template shipped. 15 tests (routing matrix + real-SSE integration with a spawned broker).
- **Notifications stream — contract v1** (plugin v2.11.0, `MEMORY/OBSERVABILITY/notifications.jsonl`): the producer side of the Pulse-mobile plan. The plugin emits human-relevant events with a speakable `speak` field: `session_started` and `phase_transition` (milestones, the latter detected inside `syncISAToWorkRegistry` where the previous phase is known), `agent_completed` (now emitted by `pai_notify` with per-message dedupe), `guard_denied`/`security_blocked`/`tool_failing` (attention — guards, security pipeline, ≥3 consecutive failures of the same tool), and `session_completed` (digest with duration). Plain native sessions start and end silently — only ISA-tracked work notifies. No rate limiting or routing at the producer; that belongs to broker/renderers. Schema documented as a stable contract in `opencode/docs/NOTIFICATIONS_STREAM.md`. Covered by unit, behavioral, and E2E scenarios.
- **PAI runtime tools manifest + minimal OpenCode helpers** — `PAI/TOOLS/manifest.json` is now the canonical contract for implemented/deferred/optional helpers. Implemented helpers: `Inference.ts` (provider-neutral command adapter), `ForgeProgress.ts` (Codex wrapper), `AnvilProgress.ts` (Moonshot/Kimi wrapper), `CrossVendorAudit.ts` (read-only Cato audit wrapper), `Arthur.ts` (credential-policy narrator), `MemoryRetriever.ts`, `KnowledgeGraph.ts`, `Checkpoint.ts`, `SessionHarvester.ts`, and `KnowledgeHarvester.ts`. Missing external providers return structured `unavailable`/`skipped` instead of letting agents improvise.
- **CheckpointPerISC + harvesters (plugin v2.13.0)** — ISA write/edit events now record allowlist-only git checkpoints for newly completed ISCs with idempotent sidecar state. `Checkpoint.ts` provides list/show/rollback preview. Session/Knowledge harvesters are implemented with dry-run/review-queue-first behavior.
- **Tools manifest validator** — `validate-tools-manifest.js` validates implemented tool files, fallbacks for deferred/optional helpers, manifest coverage, and repo test references. It is wired into promise integrity, install validation, behavioral tests, and `install.sh --check`.
- **ReadGuard + containment-minimum security parity** — OpenCode security now inspects `read`/`glob`/`grep` paths in `tool.execute.before` and `permission.asked`, denying zero-access reads such as `/etc/shadow` and requiring approval for credential-bearing reads (`.env`, `.npmrc`, cloud credentials, SSH private keys). Bash reads of credential files (`cat .env`, etc.) require approval. High-confidence secret material is blocked from being written outside protected PAI zones.

- **`build-mobile` lean-profile agent** (plugin v2.10.0): second primary agent in `opencode.jsonc.template` for mobile clients. Sent **per message** (`POST /session/{id}/message` accepts `agent`), so the same session hands off between desktop (full profile) and mobile (lean profile) without being locked to either. The plugin's system transform reads the client agent (from the transform payload or the latest `chat.message`, persisted as `client_agent` in `current-work-<session>.json`) and injects a lean context for agents in `LEAN_AGENTS` (env-overridable via `PAI_LEAN_AGENTS`): identity + classification + mode rules + active work + terse delivery instructions, skipping the full CLAUDE.md operational doc. Output ceremony is suppressed on mobile; the final voice sentence is sent through `pai_notify`, while `🎯 COMPLETED:` remains visible in both profiles.
- **Mobile app agent negotiation**: the Flutter client discovers server agents via `GET /agent` once per connection and attaches `agent: build-mobile` to outgoing messages only when the server defines it — plain OpenCode servers keep working untouched.

- **Install-time path migration** (`patch_installed_paths` in `install.sh`): rewrites legacy upstream `~/.claude/` paths to `~/.config/opencode/` in installed skills/PAI core. Repo files stay pristine for clean upstream diffs. `PAI/bin/` scripts excluded (repo-native).
- **Promise-integrity checks** in `test-behavioral.sh`: no installed agent references `~/.claude/`; no duplicated `PAI/PAI/` paths in installed `CLAUDE.md`; every installed command file is registered in `opencode.jsonc`; every static path promised by an agent exists post-install; `PAI/TOOLS` is checked through the tools manifest validator.
- **Helper fallbacks**: Forge, Cato, Arthur, Anvil, and Inference now have executable helpers that return explicit `unavailable`/`skipped` behavior when external infrastructure is absent. No improvised work when infrastructure is absent.
- `/context-search`, `/cs`, and `/pu` commands registered in `opencode.jsonc.template` (files existed but were unregistered).

### Changed

- **All 15 specialist agents declare `mode: subagent`**: they no longer appear in client agent pickers (TUI Shift+Tab cycle, mobile picker). Only `build`/`build-mobile` are primary. Specialists remain invocable by the DA and by commands (`/pai` → Algorithm). New structural check enforces this.
- **`install_agents` now removes retired agents** (`BrowserAgent`, `QATester`, `UIReviewer`, legacy `e1`–`e5`/`rate` agent files) before copying — `cp -f` never deletes, so stale files from old installs used to pollute agent pickers forever. Reinstalling cleans existing instances.
- **Test isolation**: `bun test` now preloads `tests/setup.ts` (via `bunfig.toml`) pointing `PAI_DIR` at a temp dir, so running the suite no longer creates `~/.config/opencode/PAI` on the developer's machine.
- **Voice notifications are now health-checked**: all 11 voice-enabled agents probe `localhost:31337/health` once per run (1s timeout) and skip every legacy startup/progress curl silently if Pulse is absent. Notify curls are fire-and-forget (`--max-time 2 ... || true`). Final speech is handled by `pai_notify`.
- Validator agent roster: 18 → 15 named agents, plus negative checks that deprecated agents are absent.
- Hardcoded-path check now scans all installed content (was PULSE/ only).
- **Classifier telemetry honesty (two fixes, prerequisite for the health monitor).** (1) `pai-hooks.js`: the `mode-classifier.jsonl` `fallback` flag was `source === 'fail-safe'` only — so when the LLM path *threw* and fell back to the heuristic, it logged `fallback:false`, hiding the most common degradation. Now also true when `useLLM && source === 'heuristic'`. (2) `mode-classifier.lib.js`: `normalizeClassification` omitted `'command'` from `validSources`, coercing every legit meta-command (`/status`, `/voice`, …) to `source:'fail-safe'` and inflating any failure-rate signal with normal config traffic; `'command'` is now a valid source.

### Removed

- Deprecated agents `BrowserAgent`, `QATester`, `UIReviewer` (replaced by the Interceptor skill).

### Fixed

- 43 duplicated `~/.config/opencode/PAI/PAI/...` paths in `PAI/CLAUDE.md` context routing tables.
- 2 legacy `~/.claude/` paths in `Arthur.md`.

**Validation snapshot:** 226/226 installed checks passing (109 structural + 106 behavioral + 11 E2E runtime). Repository suite: 200/200.

## [2.9.1] — Observability Parity (Headless / Non-Visual)

### Added

- **Session Events Stream** (`MEMORY/OBSERVABILITY/session-events.jsonl`)
  - Events: `session_created`, `session_idle`, `session_archived`, `session_deleted`, `state_sync`
  - Schema: `{ timestamp, event, session_id, payload }`
  - Payloads vary by event type (project/directory on create, sync fields on state_sync, etc.)
  - Emitted from: `session.created`, `session.idle`, `session.deleted`, and ISA sync triggers

- **Tool Failures Stream** (`MEMORY/OBSERVABILITY/tool-failures.jsonl`)
  - Captures tool execution failures only (successes remain in `tool-activity.jsonl`)
  - Schema: `{ timestamp, event, session_id, tool_name, failure_mode, error_message, retry_happened, security_involved, permission_involved, duration_ms }`
  - Failure modes: `error`, `exception`, `timeout`, `permission_denied`, `security_blocked`
  - Emitted from: `tool.execute.after` when `!success`

- **Subagent Traces** (`MEMORY/OBSERVABILITY/subagent-trace.jsonl`)
  - Execution traces for agent spawns (`agent_spawned`) and skill invocations (`skill_invoked`)
  - Schema: `{ timestamp, event, session_id, type, name, description, success, duration_ms }`
  - Complements guard decisions (agent-guard/skill-guard) with actual execution records
  - Emitted from: `tool.execute.after` for `agent`/`task`/`skill` tools

- **Prompt Hash in Classifier Telemetry**
  - `mode-classifier.jsonl` now includes `prompt_hash` (truncated FNV-1a, 16 chars)
  - Enables correlation without exposing full prompt content
  - Event type field added (`event: 'mode_classification'`)

### Changed

- **Plugin version**: 2.8.0 → 2.9.1
- **Observability directory structure**: all streams now under `MEMORY/OBSERVABILITY/`
- **Tool activity logging**: refactored success/failure detection to support separate failure stream
- **ISA sync telemetry**: state sync events now emitted to `session-events.jsonl`

### Design Notes

- All observability is **append-only JSONL**, no rotation or compaction
- **Backend-first**: zero dashboard/visual/voice dependency
- **VPS/headless compatible**: file-based, no HTTP routes or browser requirements
- **Future mobile/backend ready**: consistent schemas, minimal payloads, typed events
- No duplicate streams: successes go to `tool-activity.jsonl`, failures go to `tool-failures.jsonl`
- Guard decisions and execution traces are separate streams to avoid conflating intent with outcome

---

## [2.9.0] — Canonical Runtime E2E Validation

### Added

- **Canonical Runtime E2E Suite** (`bin/test-e2e-runtime.sh`)
  - 6 canonical scenarios, 10 runtime checks total
  - Headless, scriptable, no visual/dashboard dependency
  - Scenarios:
    1. **Prompt Security Path** — dangerous prompt blocked, safe prompt allowed
    2. **Mode Selection Path** — trivial ask → MINIMAL, complex ask → ALGORITHM
    3. **Session Lifecycle Path** — create → work → idle → delete with registry verification
    4. **ISA/State Sync Path** — ISA frontmatter changes propagate to `work.json`
    5. **Passive Satisfaction Path** — explicit ratings and praise captured without slash commands
    6. **Permission/Security Path** — `rm -rf` and `curl | bash` blocked with correct violations
  - Each scenario imports real plugin functions and verifies actual behavior
  - Clear PASS/FAIL output with subsystem attribution on failure

- **E2E Scenario Scripts** (`tests/e2e-runtime/*.js`)
  - Standalone JS scenarios using real `pai-hooks.lib.js` exports
  - No mocking — tests exercise actual inspection/classification/sync logic
  - Fixtures created and cleaned up automatically

### Changed

- **Validation tiers** — three-tier structure now documented:
  1. Structural (75 checks)
  2. Behavioral (45 checks)
  3. Runtime E2E (10 scenarios)
- **Plugin version**: remains 2.8.0 (no plugin changes in this release)
- **Validator integration**: `validate-pai-installation.sh` now optionally runs E2E suite after behavioral tests

### Design Notes

- E2E suite is a **second layer** on top of existing structural/behavioral checks, not a replacement
- Scenarios reflect real usage patterns, not just grep-based confidence
- Suitable for VPS/headless environments — zero browser/UI dependency
- Failures point to specific subsystem regressions (e.g., "ISA sync failed", "Classifier routed incorrectly")

---

## [2.8.0] — AgentGuard / SkillGuard

### Added

- **AgentGuard** (`plugins/lib/pai-hooks.lib.js`)
  - `inspectAgentSpawn()`: validates agent spawn decisions before execution
  - Rules:
    - **Trivial lookup detection**: warns when native tools (glob/read/grep) would suffice
    - **Fan-out threshold**: warns when session exceeds configured agent count (default: 3)
    - **Vague delegation**: warns on underspecified prompts (< 30 chars or generic phrasing)
    - **Expensive agent mismatch**: warns when research/deep agents used for trivial tasks
  - Output: `allow` / `warn` / `deny` with rationale and metadata
  - Warn-first philosophy; deny only on unambiguous high-confidence misfires
  - In-memory session agent counter (resets per plugin load)

- **SkillGuard** (`plugins/lib/pai-hooks.lib.js`)
  - `inspectSkillInvocation()`: validates skill invocation decisions before execution
  - Rules:
    - **Obvious misfire**: denies when high-specificity skill (ArXiv, Remotion, etc.) is invoked in clearly wrong context
    - **Trivial request**: warns when native tools (bash, read, grep) would suffice
    - **High-cost on trivial**: warns when expensive skills (BrightData, Apify, Research) are used for simple lookups
  - Output: `allow` / `warn` / `deny` with rationale and metadata
  - Warn-first philosophy; deny only on unambiguous misfires

- **Guard Integration in Plugin**
  - `tool.execute.before` now runs AgentGuard on `agent`/`task` tool invocations
  - `tool.execute.before` now runs SkillGuard on `skill` tool invocations
  - Warn decisions: logged to console + JSONL, execution continues
  - Deny decisions: logged to console + JSONL, execution blocked with explicit error
  - Non-blocking design — warnings do not halt execution

- **Observability**
  - `MEMORY/OBSERVABILITY/agent-guard.jsonl`: structured log of all agent guard decisions
  - `MEMORY/OBSERVABILITY/skill-guard.jsonl`: structured log of all skill guard decisions
  - Each entry includes: timestamp, session_id, requested agent/skill, decision, rationale, metadata

- **Tests**
  - `tests/security-pipeline.test.ts`: 16 new unit tests covering AgentGuard and SkillGuard
    - AgentGuard: 6 warn cases, 2 allow cases
    - SkillGuard: 2 deny cases, 3 warn cases, 2 allow cases
  - `tests/plugin-integration.test.ts`: 3 new integration tests
    - Skill misfire blocked in hook
    - Trivial agent spawn warned in hook
    - Legitimate skill use allowed in hook
  - `test-behavioral.sh`: 7 new behavioral checks + 1 functional test

### Changed

- **Plugin version**: 2.7.0 → 2.8.0
- **Behavioral test count**: 37 → 44 checks
- **Unit test count**: 89 → 107 tests across 4 files
- **Handler count**: remains 10 (guards integrated within existing `tool.execute.before`)

### Design Notes

- Backend-only guard rails with no dashboard, visual UI, or voice dependency
- Headless/VPS/mobile-friendly: all decisions logged to JSONL, no HTTP routes
- Warn-first approach minimizes friction while still surfacing bad decisions
- Deny threshold is intentionally high to avoid false positives
- Configurable via environment variables:
  - `PAI_AGENTGUARD_FANOUT_MAX` (default: 3)
  - `PAI_AGENTGUARD_DENY_CONFIDENCE=true` to enable deny on high-confidence agent misfires

---

## [2.7.0] — ISA ↔ Work-State Sync

### Added

- **ISA Detection and State Extraction** (`plugins/lib/pai-hooks.lib.js`)
  - `isISAArtifactPath()`: recognizes task ISA paths in `MEMORY/WORK/**`, project `ISA.md`, and legacy `PRD.md`
  - `extractISAState()`: parses frontmatter and extracts state-bearing fields (`phase`, `progress`, `updated`, `effort`, `mode`, `task`, `title`, `status`)
  - `syncISAToWorkRegistry()`: propagates ISA state into `work.json` and `current-work-<session>.json`
  - Upsert semantics: updates existing sessions in-place, never duplicates
  - Resilient to partial or missing frontmatter
  - Slug derivation from `MEMORY/WORK/<slug>` path, with fallback to parent directory name

- **ISA Sync Integration in Plugin**
  - `tool.execute.after` triggers sync on any `write`/`edit`/`multiedit` touching an ISA artifact
  - `session.created` runs initial sync if an ISA already exists for the work directory
  - Console logging of sync operations for observability

- **Tests**
  - `tests/isa-work-sync.test.ts`: 16 unit tests covering detection, extraction, sync, upsert, and edge cases
  - `test-behavioral.sh`: 5 new behavioral checks for ISA sync (detect, extract, sync, version, functional)

### Changed

- **Plugin version**: 2.6.0 → 2.7.0
- **Behavioral test count**: 32 → 37 checks
- **Unit test count**: 34 → 50 tests across 3 files

### Design Notes

- This is a **backend-only state sync** with no dashboard, visual tab, or voice dependency
- Works headlessly on VPS and is deployment-agnostic
- ISA frontmatter is the **single source of truth** for task state; `work.json` is derived
- Non-ISA writes do not trigger sync, avoiding registry corruption

---

## [2.6.0] — Mode/Tier Classifier Subsystem

### Added

- **Explicit Mode/Tier Classifier** (`plugins/lib/mode-classifier.lib.js`)
  - Provider-agnostic classification interface with two tiers:
    - **Heuristic layer** (default): deterministic, zero cost, zero latency
    - **LLM layer** (optional): configurable via env vars, uses any OpenAI-compatible API
  - Structured output: `MODE`, `TIER`, `REASON`, `SOURCE`, `CONFIDENCE`
  - Explicit fail-safe to `ALGORITHM E3` when confidence is low or on error
  - Override detection for `/e1`–`/e5` slash commands
  - LRU cache for LLM results (100 entries, 5min TTL) to reduce API usage
  - Auto-discovery of available API endpoints
  - Default model: `opencode/deepseek-v4-flash-free` (~4-5s response, free tier)

- **Classifier Integration in Plugin**
  - `chat.message` hook now runs explicit classification on every top-level prompt
  - Classification result persisted to `current-work-<session>.json`
  - Registry updated in `work.json` with `currentMode`, `effort`, and `modeHistory`
  - Telemetry stream: `MEMORY/OBSERVABILITY/mode-classifier.jsonl`
  - System context injection reads stored classification and surfaces it to the model

- **Observability**
  - JSONL telemetry includes: mode, tier, source, confidence, latency_ms, fallback flag
  - Console logging of classification decision on every prompt

### Changed

- **System Context Contract**
  - `buildPAISystemContext()` now reads explicit classification from session state
  - When present, classification is injected as `## Explicit Mode/Tier Classification`
  - Model instructed to honor explicit classification above self-selection
  - Model-native mode rules remain as fallback/backup behavior

- **Version bump**: `pai-hooks.js` 2.5.0 → 2.6.0

### Validation

- Behavioral tests expanded to cover classifier (see test-behavioral.sh)
- Integration tests added for classification normalization and fail-safe

## Compatibility Principle

Do not describe the port as fully 1:1. Track concrete parity by behavior and validator coverage. `/pai` must remain optional, not required, for normal PAI operation.
