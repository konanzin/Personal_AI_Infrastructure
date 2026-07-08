# Memory System

**PAI's file-system-based memory. Everything we know, everything we've learned, everything we've researched, everything we're working on.**

This is not a narrow event log or a preferences store. This is PAI's comprehensive knowledge system — the full shared memory between {{PRINCIPAL_NAME}} and {{DA_NAME}}. If we built knowledge together, it belongs here. That includes: work tracking, learnings from failures and successes, research and OSINT investigations, contact dossiers, security events, runtime state, and any other knowledge that would be valuable in future conversations.

**Two storage layers:**
- **PAI MEMORY** (`~/.config/opencode/PAI/MEMORY/`) — structured, hook-driven, entity-based
- **Auto-Memory** (`~/.config/opencode/projects/<project>/memory/`) — legacy/unstructured learnings when present

Both layers are memory. Both are persistent. Both should be used.

**Version:** OpenCode memory-read runtime (2026-06-14)
**Location:** `~/.config/opencode/PAI/MEMORY/`

---

## Architecture

OpenCode plugin state is the source of truth for session/work state. Hooks capture domain-specific events directly. The current port implements Knowledge retrieval, graph navigation, conservative transcript mining, and Knowledge Archive maintenance. Pattern synthesis and embeddings remain deferred.

```
User Request
    ↓
OpenCode plugin/runtime state
    ↓
Hook Events trigger domain-specific captures:
    ├── Algorithm (AI) → WORK/
    ├── SatisfactionCapture → LEARNING/SIGNALS/
    ├── WorkCompletionLearning → LEARNING/
    └── SecurityPipeline → SECURITY/
    ↓
Knowledge capture (inline):
    └── Algorithm LEARN phase → KNOWLEDGE/ (writes People/Companies/Ideas/Research with schema)
    ↓
Harvesting and maintenance:
    ├── SessionHarvester → learning files or review-only KNOWLEDGE/_harvest-queue candidates
    ├── KnowledgeHarvester → status, validate, index, and conservative harvest
    └── LearningPatternSynthesis → deferred
    ↓
Retrieval & Navigation (on-demand):
    ├── MemoryRetriever → compact context from KNOWLEDGE/ (BM25-lite lexical search, no LLM required)
    └── KnowledgeGraph → associative traversal over KNOWLEDGE/ (tags + wikilinks + related fields)
```

**Key insight:** Hooks write directly to specialized directories. There is no intermediate database or index requirement. Retrieval tools read the same markdown files at query time.

---

## Directory Structure

```
~/.config/opencode/PAI/MEMORY/
├── KNOWLEDGE/              # Organized, browsable knowledge archive (entity-based, v2.1)
│   ├── _index.md           # Master MOC dashboard
│   ├── _schema.md          # Object type definitions (People, Companies, Ideas, Research)
│   ├── _archive/           # Retired seedlings + purged noise (90-day expiry)
│   ├── _embeddings/        # Per-note vectors (deferred)
│   ├── _harvest-queue/     # Flagged items for next harvest
│   ├── People/             # Human beings — OSINT, contacts, profiles
│   ├── Companies/          # Organizations — research, competitors, partners
│   ├── Ideas/              # Insights, theses, analyses, frameworks
│   └── Research/           # Multi-source investigations with methodology and verified findings
├── WORK/                   # PRIMARY work tracking
│   └── {timestamp}_{slug}/
│       └── ISA.md          # Single source of truth (metadata + ISC + decisions + changelog)
├── LEARNING/               # Learnings (includes signals)
│   ├── SYSTEM/             # PAI/tooling learnings
│   │   └── YYYY-MM/
│   ├── ALGORITHM/          # Task execution learnings
│   │   └── YYYY-MM/
│   ├── FAILURES/           # Full context dumps for low ratings (1-3)
│   │   └── YYYY-MM/
│   │       └── {timestamp}_{8-word-description}/
│   │           ├── CONTEXT.md      # Human-readable analysis
│   │           ├── transcript.jsonl # Raw conversation
│   │           ├── sentiment.json  # Sentiment metadata
│   │           └── tool-calls.json # Tool invocations
│   ├── SYNTHESIS/          # Aggregated pattern analysis
│   │   └── YYYY-MM/
│   │       └── weekly-patterns.md
│   ├── REFLECTIONS/        # Algorithm performance reflections
│   │   └── algorithm-reflections.jsonl
│   └── SIGNALS/            # User satisfaction ratings
│       └── ratings.jsonl
├── RESEARCH/               # Agent output captures
│   └── YYYY-MM/
├── SECURITY/               # Security audit events
│   └── security-events.jsonl
├── STATE/                  # Operational state
│   ├── algorithms/         # Per-session algorithm state (phase, criteria, effort level)
│   ├── kitty-sessions/     # Per-session Kitty terminal env (listenOn, windowId)
│   ├── tab-titles/         # Per-window tab state (title, color, phase)
│   ├── events.jsonl        # Unified event log (append-only, typed events from hooks)
│   ├── session-names.json  # Auto-generated session names (from SessionAutoName hook)
│   ├── current-work.json
│   ├── trending-cache.json
│   ├── progress/           # Multi-session project tracking
│   └── integrity/          # System health checks
├── PAISYSTEMUPDATES/         # Architecture change history
│   ├── index.json
│   ├── CHANGELOG.md
│   └── YYYY/MM/
└── README.md
```

---

## Directory Details

### Claude Code projects/ - Native Session Storage

**Location:** `~/.config/opencode/PAI/projects/-Users-{username}--claude/`
*(Replace `{username}` with your system username, e.g., `-Users-john--claude`)*
**What populates it:** Claude Code automatically (every conversation)
**Content:** Complete session transcripts in JSONL format
**Format:** `{uuid}.jsonl` - one file per session
**Retention:** 30 days (Claude Code manages cleanup)
**Purpose:** Source of truth for all session data; harvesting tools read from here

This is the actual "firehose" - every message, tool call, and response. PAI leverages this native storage rather than duplicating it.

### KNOWLEDGE/ - Organized Knowledge Archive

**What populates it:** Algorithm LEARN phase (direct writes with schema enforcement), manual `/knowledge add`, KnowledgeHarvester.ts (validates against schema, reflections disabled)
**Content:** Curated knowledge notes organized by entity type — people, companies, ideas, research. Topic is a tag, not a domain.
**Format:** Markdown files with YAML frontmatter (entity_type, tags, status). Full object type definitions in `_schema.md`.
**Purpose:** Browsable, organized archive of entities we'd look up by name — harvested from sessions and manual captures

**4 entity types:** People (human beings — OSINT, contacts, profiles), Companies (organizations — research, competitors, partners), Ideas (insights, theses, analyses, frameworks), Research (multi-source investigations with methodology and verified findings)
**The lookup test:** "Would {{PRINCIPAL_NAME}} look this up by name?" — if yes, it's knowledge. If not, it belongs in WORK/ or LEARNING/.
**Research vs. Ideas:** If it involved multiple sources, parallel investigation, verification, and produced a comprehensive dataset — it's research. A single insight or thesis is an idea. Research entries link to full output in WORK/.
**What doesn't belong:** Task logs, algorithm reflections, ISA checklists, verification stubs → WORK/ and LEARNING/, not KNOWLEDGE/
**Note types:** reference, synthesis, moc, source, temporal
**Status lifecycle:** seedling → budding → evergreen (90-day expiry for unreferenced seedlings → `_archive/`)
**Linking:** `[[kebab-case-wikilinks]]` for explicit links, tags for cross-cutting, `rg` for backlinks, semantic embeddings deferred
**Navigation:** `_index.md` MOC dashboards per entity type (auto-generated, structured: recently-updated, most-referenced, by-tag, seedlings)

**Key principle:** Algorithm LEARN phase writes directly with proper schemas (best context to capture what was learned). Harvester validates against schema and handles maintenance. Topic (security, AI, business) is a tag on the entity, not a separate domain.

### WORK/ - Primary Work Tracking

**What populates it:**
- Algorithm (AI) creates work dir with ISA.md during execution
- `WorkCompletionLearning.hook.ts` on Stop (updates ISA/THREAD)
- `SessionCleanup.hook.ts` on SessionEnd (marks COMPLETED)

**Content:** Flat work directories with a single ISA.md as source of truth
**Format:** `WORK/{timestamp}_{slug}/ISA.md` — consolidated metadata + ISC + decisions + changelog
**Purpose:** Track all discrete work units with lineage, verification, and feedback

**ISA.md Structure (v4.0 — consolidated single file):**
- **YAML frontmatter** — session metadata (id, title, session_id, status, effort_level, completed_at, iteration count, verification_summary)
- **STATUS** — progress table (criteria passing, phase, next action, blockers)
- **APPETITE** — time budget, circuit breaker, ISC target count
- **CONTEXT** — problem space from user prompt, key files
- **RISKS & RABBIT HOLES** — populated during THINK phase
- **PLAN** — populated during PLAN phase
- **IDEAL STATE CRITERIA** — checkbox markdown (`- [x]`/`- [ ]`) as system of record
- **DECISIONS** — non-obvious technical decisions logged during BUILD/EXECUTE
- **CHANGELOG** — timestamped entries replacing THREAD.md

**Work Directory Lifecycle:**
1. Algorithm execution → AI creates work dir with ISA.md (frontmatter includes session metadata)
2. `PostToolUse` → ISASync syncs ISA frontmatter to work.json on Write/Edit
3. `SessionEnd` → SessionCleanup marks ISA status COMPLETED, clears state

**Note:** Legacy work directories (pre-2026-02-22) may have META.yaml, ISC.json, THREAD.md alongside ISA.md. All consumers check ISA.md frontmatter first, fall back to legacy files.

### LEARNING/ - Categorized Learnings

**What populates it:**
- `SatisfactionCapture.hook.ts` (explicit ratings + implicit sentiment + low-rating learnings)
- `WorkCompletionLearning.hook.ts` (significant work session completions)
- `SessionHarvester.ts` (periodic extraction from projects/ transcripts)
- `LearningPatternSynthesis.ts` (aggregates ratings into pattern reports)

**Structure:**
- `LEARNING/SYSTEM/YYYY-MM/` - PAI/tooling learnings (infrastructure issues)
- `LEARNING/ALGORITHM/YYYY-MM/` - Task execution learnings (approach errors)
- `LEARNING/SYNTHESIS/YYYY-MM/` - Aggregated pattern analysis (weekly/monthly reports)
- `LEARNING/REFLECTIONS/algorithm-reflections.jsonl` - Algorithm performance reflections (Q1/Q2/Q3 from LEARN phase)
- `LEARNING/SIGNALS/ratings.jsonl` - All user satisfaction ratings

**Categorization logic:**
| Directory | When Used | Example Triggers |
|-----------|-----------|------------------|
| `SYSTEM/` | Tooling/infrastructure failures | hook crash, config error, deploy failure |
| `ALGORITHM/` | Task execution issues | wrong approach, over-engineered, missed the point |
| `FAILURES/` | Full context for low ratings (1-3) | severe frustration, repeated errors |
| `REFLECTIONS/` | Algorithm performance analysis | per-session 3-question reflection from LEARN phase |
| `SYNTHESIS/` | Pattern aggregation | weekly analysis, recurring issues |

### LEARNING/FAILURES/ - Full Context Failure Analysis

**What populates it:**
- `SatisfactionCapture.hook.ts` via `FailureCapture.ts` (for ratings 1-3)
- Manual migration via `bun FailureCapture.ts --migrate`

**Content:** Complete context dumps for low-sentiment events
**Format:** `FAILURES/YYYY-MM/{timestamp}_{8-word-description}/`
**Purpose:** Enable retroactive learning system analysis by preserving full context

**Each failure directory contains:**
| File | Description |
|------|-------------|
| `CONTEXT.md` | Human-readable analysis with metadata, root cause notes |
| `transcript.jsonl` | Full raw conversation up to the failure point |
| `sentiment.json` | Sentiment analysis output (rating, confidence, detailed analysis) |
| `tool-calls.json` | Extracted tool calls with inputs and outputs |

**Directory naming:** `YYYY-MM-DD-HHMMSS_eight-word-description-from-inference`
- Timestamp in PST
- 8-word description generated by fast inference to capture failure essence

**Rating thresholds:**
| Rating | Capture Level |
|--------|--------------|
| 1 | Full failure capture + learning file |
| 2 | Full failure capture + learning file |
| 3 | Full failure capture + learning file |
| 4-5 | Learning file only (if warranted) |
| 6-10 | No capture (positive/neutral) |

**Why this exists:** When significant frustration occurs (1-3), a brief summary isn't enough. Full context enables:
1. Root cause identification - what sequence led to the failure?
2. Pattern detection - do similar failures share characteristics?
3. Systemic improvement - what changes would prevent this class of failure?

### RESEARCH/ - Investigations & Agent Outputs

**What populates it:** Agent tasks write directly; OSINT workflows; any multi-agent research
**Content:** Agent completion outputs, OSINT dossiers, investigation reports, competitive analysis, deep dives
**Format:** `RESEARCH/YYYY-MM/YYYY-MM-DD-HHMMSS_AGENT-type_description.md`
**Purpose:** Archive of all research and investigation work — the structured output side of knowledge we build together

**Note:** Research findings should ALSO be summarized as auto-memory entries (reference type in `projects/<project>/memory/`) so they're discoverable at session start. RESEARCH/ holds the full output; auto-memory holds the summary and pointer.

### SECURITY/ - Security Events (Active — v3.0)

**What populates it:** `SecurityPipeline.hook.ts` on tool validation
**Content:** Security audit events (blocks, confirmations, alerts)
**Format:** `SECURITY/security-events.jsonl`
**Purpose:** Security decision audit trail

### STATE/ - Fast Runtime Data

**What populates it:** Various tools and hooks
**Content:** High-frequency read/write JSON files for runtime state
**Key Property:** Ephemeral - can be rebuilt from RAW or other sources. Optimized for speed, not permanence.

**Key contents:**
- `algorithms/` - Per-session algorithm state files (`{sessionId}.json` — phase, criteria, effort level, active flag)
- `kitty-sessions/` - Per-session Kitty terminal env (`{sessionId}.json` — listenOn, windowId for tab control and voice gating)
- `tab-titles/` - Per-window tab state (`{windowId}.json` — title, color, phase for daemon recovery)
- `session-names.json` - Auto-generated session names from SessionAutoName hook
- `current-work.json` - Active work directory pointer
- `progress/` - Multi-session project tracking
- `integrity/` - System health check results

This is mutable state that changes during execution - not historical records. If deleted, system recovers gracefully.

**`events.jsonl` - Unified Event Log:**

An append-only JSONL file where hooks emit structured, typed events alongside their normal state writes. Each line is a JSON object with `timestamp`, `session_id`, `source`, `type`, and type-specific fields. The type field uses a dot-separated topic hierarchy (e.g., `algorithm.phase`, `work.created`, `rating.captured`, `voice.sent`). This file is an observability layer -- it does NOT replace any of the mutable state files listed above. Events are written by `${PAI_DIR}/hooks/lib/observability-transport.ts` using synchronous append, and errors are silently swallowed so the event log never disrupts hook execution. Consumers can tail or `fs.watch` this file for real-time visibility into PAI activity.

### PAISYSTEMUPDATES/ - Change History

**What populates it:** Manual via CreateUpdate.ts tool
**Content:** Canonical tracking of all system changes
**Purpose:** Track architectural decisions and system changes over time

---

## Hook Integration

| Hook | Trigger | Writes To |
|------|---------|-----------|
| Algorithm (AI) | During execution | WORK/ISA.md, STATE/current-work-{sessionId}.json |
| OpenCode plugin ISA sync | Write/Edit tool completion | STATE/work.json (syncs ISA frontmatter) |
| OpenCode plugin classifier | User prompt | STATE/current-work-{sessionId}.json, OBSERVABILITY/mode-classifier.jsonl |
| OpenCode plugin session lifecycle | Session idle/delete | STATE/work.json, OBSERVABILITY/session-events.jsonl |
| OpenCode plugin security guards | Tool/prompt validation | STATE/security-events.jsonl |
| MemoryRetriever.ts | On-demand CLI | KNOWLEDGE/ read-only retrieval |
| KnowledgeGraph.ts | On-demand CLI | KNOWLEDGE/ read-only graph traversal |

> **Note:** Original Claude Code memory hooks are legacy/reference material. The current OpenCode runtime writes memory state through the PAI plugin and the installed read-only memory tools.

## Harvesting & Retrieval Tools

| Tool | Purpose | Reads From | Writes To |
|------|---------|------------|-----------|
| SessionHarvester.ts | Conservative transcript learning extraction | session JSONL | LEARNING/ |
| SessionHarvester.ts --mine | Review-queue mining for decisions/preferences/milestones/problems | session JSONL | KNOWLEDGE/_harvest-queue/ |
| KnowledgeHarvester.ts | Status, validate, index, and conservative harvest | KNOWLEDGE/, WORK/, RESEARCH/, _harvest-queue/ | KNOWLEDGE/ |
| LearningPatternSynthesis.ts | Deferred, not installed in current OpenCode port | LEARNING/SIGNALS/ | LEARNING/SYNTHESIS/ |
| FailureCapture.ts | Full context dumps for low ratings | projects/, SIGNALS/ | LEARNING/FAILURES/ |
| MemoryRetriever.ts | BM25-lite search + compact excerpts for context retrieval | KNOWLEDGE/ | (stdout — read-only) |
| KnowledgeGraph.ts | Associative graph navigation over tags/wikilinks | KNOWLEDGE/ | (stdout — read-only) |
| ActivityParser.ts | Parse recent file changes | projects/ | (analysis only) |

---

## Data Flow

```
User Request
    ↓
OpenCode runtime events and plugin state
    ↓
Algorithm (AI) → WORK/{timestamp}_{slug}/ISA.md + STATE/current-work-{sessionId}.json
    ↓
[Work happens - AI writes ISA directly, ISASync keeps work.json + KV in sync]
    ↓
[If context compacts] → PreCompact.hook.ts → stdout handover (preserved through compaction)
    ↓
Auto-Memory → projects/<project>/memory/MEMORY.md (Claude writes learnings)
    ↓
SatisfactionCapture → LEARNING/SIGNALS/ + LEARNING/
    ↓
WorkCompletionLearning → LEARNING/ (for significant work, reads ISA.md frontmatter)
    ↓
SessionSummary → WORK/ISA.md (status→COMPLETED), clears STATE/current-work-{sessionId}.json

[Between sessions]
    ↓
Auto-Dream (server-controlled) → consolidates memory/MEMORY.md

[Periodic harvesting]
    ↓
SessionHarvester → learning files / review queue
LearningPatternSynthesis → deferred
```

---

## Quick Reference

### Check current work
```bash
cat ~/.config/opencode/PAI/PAI/MEMORY/STATE/current-work.json
ls ~/.config/opencode/PAI/PAI/MEMORY/WORK/ | tail -5
```

### Check ratings
```bash
tail ~/.config/opencode/PAI/PAI/MEMORY/LEARNING/SIGNALS/ratings.jsonl
```

### View session transcripts
```bash
# List recent sessions (newest first)
# Replace {username} with your system username
ls -lt ~/.config/opencode/PAI/projects/-Users-{username}--claude/*.jsonl | head -5

# View last session events
tail ~/.config/opencode/PAI/projects/-Users-{username}--claude/$(ls -t ~/.config/opencode/PAI/projects/-Users-{username}--claude/*.jsonl | head -1) | jq .
```

### Check learnings
```bash
ls ~/.config/opencode/PAI/PAI/MEMORY/LEARNING/SYSTEM/
ls ~/.config/opencode/PAI/PAI/MEMORY/LEARNING/ALGORITHM/
ls ~/.config/opencode/PAI/PAI/MEMORY/LEARNING/SYNTHESIS/
```

### Check failures
```bash
# List recent failure captures
ls -lt ~/.config/opencode/PAI/PAI/MEMORY/LEARNING/FAILURES/$(date +%Y-%m)/ 2>/dev/null | head -10

# View a specific failure
cat ~/.config/opencode/PAI/PAI/MEMORY/LEARNING/FAILURES/2026-01/*/CONTEXT.md | head -100

# Migrate historical low ratings to FAILURES
bun run ~/.config/opencode/PAI/TOOLS/FailureCapture.ts --migrate
```

### Check multi-session progress
```bash
ls ~/.config/opencode/PAI/PAI/MEMORY/STATE/progress/
```

### Run harvesting tools

Harvesting tools exist in the current OpenCode port, but they are conservative
maintenance helpers, not autonomous background jobs. Prefer `--dry-run` before
writing new memory artifacts.

```bash
# Harvest learnings from recent sessions
bun run ~/.config/opencode/PAI/TOOLS/SessionHarvester.ts --recent 10

# Mine conversations for decisions, preferences, milestones, problems
bun run ~/.config/opencode/PAI/TOOLS/SessionHarvester.ts --mine --recent 10

# Generate pattern synthesis
bun run ~/.config/opencode/PAI/TOOLS/LearningPatternSynthesis.ts --week
```

### Retrieve knowledge (compressed context)
```bash
# Search knowledge archive with BM25 ranking
bun run ~/.config/opencode/PAI/TOOLS/MemoryRetriever.ts "query terms"

# Raw excerpts without LLM compression
bun run ~/.config/opencode/PAI/TOOLS/MemoryRetriever.ts "query terms" --raw --top 5
```

### Navigate knowledge graph
```bash
# Graph stats: nodes, edges, clusters
bun run ~/.config/opencode/PAI/TOOLS/KnowledgeGraph.ts stats

# BFS traversal from a note
bun run ~/.config/opencode/PAI/TOOLS/KnowledgeGraph.ts traverse <slug> --hops 2

# Directly connected notes
bun run ~/.config/opencode/PAI/TOOLS/KnowledgeGraph.ts related <slug>

# Find notes by tag
bun run ~/.config/opencode/PAI/TOOLS/KnowledgeGraph.ts find <tag>
```

---

## Migration History

**2026-04-07:** Memory System v7.6 - Retrieval + Navigation + Mining + Temporal
- Added `MemoryRetriever.ts` — BM25-lite search across KNOWLEDGE/ without required LLM compression. Returns compact context within configurable output budget.
- Added `KnowledgeGraph.ts` — In-memory graph over KNOWLEDGE/ frontmatter tags, wikilinks, and related fields. BFS traversal, stats, hubs, related notes, tag search. Computed at query time, zero persistent storage.
- Added `--mine` flag to `SessionHarvester.ts` — Regex-based classification of conversation segments into decisions, preferences, milestones, problems. Candidates written to `KNOWLEDGE/_harvest-queue/` for review, never directly to KNOWLEDGE/.
- Added `valid_from`/`valid_until` optional frontmatter fields to all 4 entity types in `_schema.md` — Temporal fact validity tracking. Contradiction detector now skips note pairs with non-overlapping validity windows.
- Updated `KnowledgeHarvester.ts contradictions` command to check temporal fields before flagging pairs.
- Knowledge skill updated with `graph`, `retrieve`, and `mine` commands.
- Pulse wiki module's `/api/wiki/graph` endpoint uses wikilinks only; `KnowledgeGraph.ts` provides richer graph (tags + wikilinks + related fields) via CLI.
- Inspired by MemPalace (Ben Sigman) analysis — adapted 4 techniques to PAI's file-based architecture without adding vector DB, SQLite, or any opaque storage.

**2026-04-05:** Knowledge Archive v2.1 - Research entity type added
- Added Research as 4th entity type in KNOWLEDGE/ — for multi-source investigations with methodology, sources, and verified findings
- Research vs. Ideas: multi-source investigation = research, single insight = idea
- Schema includes methodology, agent_count, source_session fields
- Observatory API and KnowledgeHarvester updated to support Research domain
- MEMORY/RESEARCH/ remains as raw agent output archive; KNOWLEDGE/Research/ holds curated entries

**2026-04-02:** Knowledge Archive v2.0 - Entity-based redesign
- Redesigned from 8 topic-based domains (Business, Health, Learnings, People, Projects, Research, Security, Technology) to 3 entity types: People, Companies, Ideas
- Topic is now a tag on the entity, not a separate domain folder
- Strict schema per entity type defined in `_schema.md`
- Algorithm LEARN phase writes directly to KNOWLEDGE/ with proper schemas (no harvester intermediary needed)
- Harvester reflections disabled; harvester now validates against schema and handles maintenance
- The lookup test: "Would {{PRINCIPAL_NAME}} look this up by name?" — if not, it's not knowledge
- Observatory renders type-specific layouts per entity type

**2026-04-01:** v7.5 - Comprehensive Knowledge Store
- Updated documentation to reflect that memory is PAI's everything — not just prefs and events
- Auto-memory stores all shared knowledge: research, OSINT, contact dossiers, reference material, not just corrections/patterns
- RESEARCH/ section expanded to cover investigations, OSINT workflows, competitive analysis
- Added guidance: research findings should be summarized in auto-memory (reference type) for discoverability
- Clarified two-layer architecture: PAI MEMORY (structured/hook-driven) + Auto-Memory (everything else)

**2026-03-31:** v7.4 - Eliminated PAI/MEMORY/AUTO fragmentation
- Removed `autoMemoryDirectory` setting from settings.json (was still redirecting to PAI/MEMORY/AUTO/)
- Migrated 2 unique feedback items to CC's native memory at `~/.config/opencode/PAI/projects/-Users-{YourName}--claude/memory/`
- Deleted `PAI/MEMORY/AUTO/` directory — CC native memory is the single auto-memory location
- Updated PAI Upgrade redistribution workflow to scan CC native memory path
- Updated statusline token estimation to use CC native memory path

**2026-03-24:** v7.3 - Auto-Memory & PreCompact Integration
- Enabled Claude Code's built-in auto-memory using default path (`~/.config/opencode/PAI/projects/<project>/memory/`)
- Replaced blocking MEMORY.md ("Do Not Store Memories Here") with clean index
- Created `PreCompact.hook.ts` — captures work state before conversation compaction
- Added PreCompact hook to settings.json (matcher: `"*"` for auto + manual)
- Documented auto-dream (server-controlled consolidation feature)
- PAI hooks and auto-memory now coexist: hooks for structured domain events, auto-memory for unstructured learnings

**2026-02-22:** v7.2 - ISA Consolidation (v4.0 work directories)
- Consolidated META.yaml, ISC.json, THREAD.md into single ISA.md per work directory
- ISA.md frontmatter now holds session metadata (title, session_id, status, completed_at)
- ISC section in ISA (checkbox markdown) is the system of record for criteria
- CHANGELOG section in ISA replaces THREAD.md
- All hooks updated: SessionCleanup, WorkCompletionLearning, LoadContext
- Legacy fallback preserved: consumers check ISA.md first, fall back to META.yaml/ISC.json
- Dropped never-populated sections: NON-SCOPE, ASSUMPTIONS, OPEN QUESTIONS

**2026-01-17:** v7.1 - Full Context Failure Analysis
- Added LEARNING/FAILURES/ directory for comprehensive failure captures
- Created FailureCapture.ts tool for generating context dumps
- Updated RatingCapture.hook.ts to create failure captures for ratings 1-3
- Each failure gets its own directory with transcript, sentiment, tool-calls, and context
- Directory names use 8-word descriptions generated by fast inference
- Added migration capability via `bun FailureCapture.ts --migrate`

**2026-01-12:** v7.0 - Projects-native architecture
- Eliminated RAW/ directory entirely - Claude Code's `projects/` is the source of truth
- Removed EventLogger.hook.ts (was duplicating what projects/ already captures)
- Created SessionHarvester.ts to extract learnings from projects/ transcripts
- Created WorkCompletionLearning.hook.ts for session-end learning capture
- Created LearningPatternSynthesis.ts for rating pattern aggregation
- Added LEARNING/SYNTHESIS/ for pattern reports
- Updated ActivityParser.ts to use projects/ as data source
- Removed archive functionality from pai.ts (Claude Code handles 30-day cleanup)

**2026-01-11:** v6.1 - Removed RECOVERY system
- Deleted RECOVERY/ directory (5GB of redundant snapshots)
- Removed RecoveryJournal.hook.ts, recovery-engine.ts, snapshot-manager.ts
- Git provides all necessary rollback capability

**2026-01-11:** v6.0 - Major consolidation
- WORK is now the PRIMARY work tracking system (not SESSIONS)
- Deleted SESSIONS/ directory entirely
- Merged SIGNALS/ into LEARNING/SIGNALS/
- Merged PROGRESS/ into STATE/progress/
- Merged integrity-checks/ into STATE/integrity/
- Fixed AutoWorkCreation hook (prompt vs user_prompt field)
- Updated all hooks to use correct paths

**2026-01-10:** v5.0 - Documentation consolidation
- Consolidated WORKSYSTEM.md into MEMORYSYSTEM.md

**2026-01-09:** v4.0 - Major restructure
- Moved BACKUPS to `~/.config/opencode/PAI/BACKUPS/` (outside MEMORY)
- Renamed RAW-OUTPUTS to RAW
- All directories now ALL CAPS

**2026-01-05:** v1.0 - Unified Memory System migration
- Previous: `~/.config/opencode/PAI/history/`, `~/.config/opencode/PAI/context/`, `~/.config/opencode/PAI/progress/`
- Current: `~/.config/opencode/PAI/PAI/MEMORY/`
- Files migrated: 8,415+

---

## Claude Code Auto-Memory & Auto-Dream

PAI coexists with Claude Code's built-in memory system rather than replacing it.

### Auto-Memory
**Location:** `~/.config/opencode/PAI/projects/<project>/memory/` (default, matches system prompt injection)
**Writer:** Claude (automatic, during sessions)
**Index:** `MEMORY.md` — first 200 lines loaded at every session start
**Content:** Everything that doesn't have a structured hook — research findings, OSINT dossiers, contact profiles, user preferences, corrections, patterns, reference material, and any other knowledge built during sessions

Auto-memory is not a narrow preferences store. It is the general-purpose knowledge layer of PAI's memory system. If we built knowledge together and it would be valuable in a future conversation, it belongs here. Types include:
- **user** — who {{PRINCIPAL_NAME}} is, how to work with him
- **feedback** — corrections and confirmed approaches
- **project** — ongoing work context, decisions, deadlines
- **reference** — pointers to external resources, research summaries, contact dossiers, OSINT findings

PAI's hooks capture structured domain-specific events (LEARNING/, WORK/, SIGNALS/). Auto-memory captures everything else.

**Configuration:**
- Enabled by default (`autoMemoryEnabled` not set = true)
- No custom `autoMemoryDirectory` — uses default path so system prompt path matches
- Manage via `/memory` command in any session

### Auto-Dream (Server-Controlled)
**Trigger:** Server-side feature flag — runs between sessions when 24+ hours and 5+ sessions have elapsed
**What it does:** Background subagent consolidates auto-memory files — prunes stale entries, resolves contradictions, converts relative dates, deduplicates

PAI doesn't control auto-dream activation. When it runs, it operates on the auto-memory directory above.

### PreCompact Hook
**What:** Preserves active work context before conversation compaction
**Hook:** `PreCompact.hook.ts` (matcher: `"*"`)
**Captures:** Active task, ISA summary, files modified, key decisions, session ID
**Output:** Structured handover note on stdout, preserved through compaction

### How PAI Memory and Auto-Memory Coexist

| System | Writer | Content | Loaded When |
|--------|--------|---------|-------------|
| Auto-Memory (`MEMORY.md`) | Claude | All shared knowledge: research, contacts, corrections, patterns, references | First 200 lines at session start |
| PAI WORK/ | Algorithm + hooks | Task tracking, ISAs, ISC | On demand via LoadContext |
| PAI LEARNING/ | Hooks + harvesters | Ratings, failures, synthesis | On demand via dynamic context |
| PAI STATE/ | Hooks | Ephemeral runtime state | On demand |
| Auto-Dream | Claude (subagent) | Consolidated auto-memory | Runs between sessions |
| PreCompact | Hook | Work-in-progress handover | Before compaction |

---

## Related Documentation

- **Hook System:** `../Hooks/HookSystem.md`
- **Architecture:** `PAISYSTEMARCHITECTURE.md`
