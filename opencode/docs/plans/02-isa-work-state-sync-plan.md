# Plan — ISA ↔ Work-State Sync (Without Dashboard)

## Goal

Restore stronger parity between:

- ISA/task state
- `work.json`
- session-local current-work state

without implementing any Pulse dashboard behavior.

## Key decision

Yes: implement backend/state sync.

No: do **not** implement any UI/dashboard coupling in this phase.

## Current gap

The port has:

- work registry creation
- session lifecycle tracking
- archive behavior
- recent work context injection

But it does **not** clearly reproduce the original “ISA frontmatter is the source of truth and state is synchronized from it” design.

That means:

- phase drift is possible
- progress drift is possible
- the runtime may know a session exists without strongly knowing where it is in the Algorithm lifecycle

## Scope

### In scope

- session state updates from ISA frontmatter
- canonical phase/progress sync to `work.json`
- sync on write/edit to ISA-like files
- project-ISA and task-ISA path handling

### Out of scope

- Pulse dashboard rendering
- visual tabs
- UI phase indicators
- mobile presentation layer

## Target architecture

### State sources

1. **Primary source:** ISA frontmatter / canonical task artifact
2. **Derived state:** `MEMORY/STATE/work.json`
3. **Ephemeral bridge:** `current-work-<session>.json`

### Sync rule

Whenever an ISA-like artifact is written/edited and includes state-bearing frontmatter, propagate:

- `phase`
- `progress`
- `updated`
- `effort`
- `mode`
- `task` / `slug` if available

into the session registry.

## Suggested implementation shape

### Option A — lightweight sync in plugin

Add a post-write/post-edit sync path inside `tool.execute.after` for writes touching ISA/task files.

### Option B — dedicated sync helper

Create a helper in `pai-hooks.lib.js`:

- detect candidate ISA files
- parse frontmatter
- upsert session registry

Recommended: **Option B** for maintainability.

## Files likely to change

- `opencode/plugins/pai-hooks.js`
- `opencode/plugins/lib/pai-hooks.lib.js`
- `opencode/bin/test-behavioral.sh`
- `opencode/docs/README-OPENCODE.md`
- `opencode/docs/CHANGELOG-OPENCODE.md`

## Detection logic

Recognize at least:

- task ISA paths in `MEMORY/WORK/**`
- project `ISA.md` files where applicable
- legacy compatible task metadata if still needed

## Validation plan

### Must-pass cases

1. Write/edit task ISA frontmatter → `work.json` updates phase/progress
2. Re-edit same ISA → registry updates in place, not duplicate session spam
3. Session deletion/archive preserves final synced state
4. Missing/partial frontmatter does not corrupt registry
5. Non-ISA writes do not trigger sync

## Success criteria

- `work.json` reflects real task phase/progress from the underlying artifact
- sync works headlessly on VPS
- no dashboard dependency exists

## Recommendation to implementation agent

Implement only the **state synchronization contract**. Treat all presentation surfaces as future consumers, not part of this work.
