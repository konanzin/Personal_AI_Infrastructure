# Plan — Observability Parity (Headless / Non-Visual)

## Goal

Improve observability parity with original PAI while explicitly excluding:

- Pulse dashboard work
- voice work
- visual terminal affordances

## Position

Because your likely long-term interface is mobile and because VPS/headless deployment matters, observability should be treated as:

- file-first
- API-friendly
- JSONL-friendly
- transportable to future mobile consumers

## Current strengths

The port already has useful observability foundations:

- `tool-activity.jsonl`
- `security-events.jsonl`
- session/work registries
- ratings signals
- archive state

## Remaining gap

The original system had broader coverage around:

- tool failure tracking
- richer classifier telemetry
- more explicit subagent/skill orchestration traces
- document integrity style checks

## Scope

### In scope

- JSONL event expansion
- consistent event schemas
- classifier event logs
- guard-rail event logs
- session transition logs

### Out of scope

- charts
- dashboards
- voice output
- visual summaries

## Recommended observability targets

### 1. Mode-classifier telemetry

Record:
- prompt excerpt hash or truncated text
- mode
- tier
- source
- latency
- fallback used or not

### 2. Agent/skill guard telemetry

Record:
- requested agent/skill
- decision (`allow/warn/deny`)
- rationale
- timestamp

### 3. Session transition telemetry

Record:
- session created
- session idle
- session archived
- state sync updates

### 4. Tool failure telemetry

Record:
- tool name
- failure mode
- whether retry happened
- whether security/permission was involved

## Suggested storage strategy

Use append-only JSONL under `MEMORY/OBSERVABILITY/` with narrow, typed files rather than one giant mixed stream.

Recommended files:

- `mode-classifier.jsonl`
- `agent-guard.jsonl`
- `skill-guard.jsonl`
- `session-events.jsonl`
- `tool-failures.jsonl`

## Files likely to change

- `opencode/plugins/pai-hooks.js`
- `opencode/plugins/lib/pai-hooks.lib.js`
- `opencode/docs/README-OPENCODE.md`
- `opencode/docs/CHANGELOG-OPENCODE.md`
- optionally validation scripts for smoke coverage

## Success criteria

- observability improves without adding visual surface area
- future mobile/backend consumers can read the data cleanly
- parity improves in a way that is deployment-agnostic

## Recommendation to implementation agent

Treat observability as a **backend contract**, not a UI feature. Design logs now so a future mobile client can consume them without needing a migration.
