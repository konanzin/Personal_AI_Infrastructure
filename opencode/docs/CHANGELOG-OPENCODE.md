# PAI OpenCode Port Changelog

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

---

## Current Port State

This repository ports PAI from Claude Code to OpenCode-native configuration and plugin surfaces.

### Verified Architecture

| Area | Current State |
|------|---------------|
| Config | `~/.config/opencode/opencode.jsonc` generated from `opencode/config/opencode.jsonc.template` |
| Plugin | `pai-hooks.js` loaded explicitly through OpenCode `plugin` config |
| Plugin lib | `plugins/lib/pai-hooks.lib.js`, not root auto-loaded |
| Agents | 18 `.md` files installed under `~/.config/opencode/agents/` |
| Commands | `/pai`, `/status`, `/interview`, `/pulse`, `/context`, `/e1`-`/e5` |
| Memory | `~/.config/opencode/PAI/MEMORY/{STATE,WORK,KNOWLEDGE,LEARNING,RESEARCH}` |
| Validation | 75 checks in `validate-pai-installation.sh` |

### Parity Notes

| Claude Code Feature | OpenCode Port Status |
|---------------------|----------------------|
| SecurityPipeline | Native `tool.execute.before` implementation |
| PermissionGuard | Native `permission.asked` implementation |
| ToolActivityTracker | Native `tool.execute.after` logging |
| ContentScanner | Native `tool.execute.after` scanning |
| Session cleanup | Adapted to OpenCode session lifecycle |
| Satisfaction capture | Captured passively from user messages (explicit ratings and praise fast-path); no dedicated `/rate` command |
| Work learning | Captured during session deletion where metadata exists |
| ISA sync | **Backend-only state sync** — ISA frontmatter is source of truth for `work.json` phase/progress |
| LoadContext | **1:1 via `experimental.chat.system.transform`** — full TELOS context injected into system prompt |
| Compaction context | **1:1 via `experimental.session.compacting`** — PAI rules preserved across context resets |
| PrePromptGuard | **1:1 via `chat.message`** — blocks dangerous prompts *before* model processing |
| Default PAI behavior | OpenCode default build agent plus system transform with model-native mode classification; `/pai` not required |
| PromptGuard | Adapted: `chat.message` pre-sanitizes denied prompts before model context; `message.updated` still logs post-event findings |
| Voice | External Pulse notification only; no OpenCode-native voice |
| Statusline | Slash-command/status output instead of Claude Code sidebar |

**Parity estimate: ~85-90%** (up from 82-87%). Remaining gaps are primarily platform-different (voice, statusline sidebar) rather than functional.

**Validation: 112/112 checks passing** (75 structural + 37 behavioral).

### Important: Repo vs Runtime Sync

The repository and installed runtime can get out of sync. After pulling updates:

```bash
# Deploy latest plugin to active OpenCode installation
bash opencode/bin/deploy-plugin.sh

# Or with restart
bash opencode/bin/deploy-plugin.sh --restart
```

### Removed Historical Noise

- Deleted the old bugfix review document because it described a point-in-time audit, not source of truth.
- Deleted the old incident report from the repo because active safety is now represented by installer behavior, validator checks, and plugin placement.
- Removed accidentally generated literal `${HOME}` test artifacts from the repository tree.

### Behavioral Validation Matrix

Latest run: `bash opencode/bin/test-behavioral.sh`

| Category | Tests | Result |
|----------|-------|--------|
| Structural (version, handlers, paths) | 6/6 | ✅ PASS |
| Side-effects (files, JSON validity) | 4/4 | ✅ PASS |
| PermissionGuard (`permission.asked`) | 1/1 | ✅ PASS |
| Rating parser (explicit message ratings) | 1/1 | ✅ PASS |
| System context injection | 3/3 | ✅ PASS |
| Mode/Tier Classifier | 8/8 | ✅ PASS |
| Compaction context preservation | 2/2 | ✅ PASS |
| Session lifecycle (idle/deleted) | 3/3 | ✅ PASS |
| ISA ↔ Work-State Sync | 5/5 | ✅ PASS |
| Security pipeline (bash/write/presanitize) | 3/3 | ✅ PASS |
| **Total** | **37/37** | **✅ ALL PASS** |

## Compatibility Principle

Do not describe the port as fully 1:1. Track concrete parity by behavior and validator coverage. `/pai` must remain optional, not required, for normal PAI operation.
