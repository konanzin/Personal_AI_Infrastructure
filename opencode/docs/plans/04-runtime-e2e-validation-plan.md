# Plan — Canonical Runtime E2E Validation

## Goal

Move beyond structural + grep-heavy behavioral checks by defining a small set of canonical runtime flows that mimic real usage.

## Why this matters

The current harness is valuable for regression protection, but much of it is still:

- structural
- synthetic
- static-content based

That is not enough for long-term parity confidence.

## Scope

### In scope

- headless or semi-headless real runtime flows
- scriptable validation scenarios
- expected PASS/FAIL criteria

### Out of scope

- visual dashboard checks
- mobile UI checks
- voice notification checks

## Canonical scenarios

### Scenario 1 — Prompt security path

Input:
- dangerous injected prompt

Verify:
- `chat.message` pre-sanitizes
- security event recorded
- model is not handed raw malicious content

### Scenario 2 — Mode-selection path

Input:
- trivial ask
- medium ask
- complex ask

Verify:
- resulting behavior matches expected mode/tier decision path

### Scenario 3 — Session lifecycle path

Input:
- create session
- perform work
- idle
- delete/end

Verify:
- registry created
- idle only updates `lastIdleAt`
- archive/cleanup occurs in correct order

### Scenario 4 — ISA/state sync path

Input:
- update an ISA/task artifact

Verify:
- `work.json` reflects phase/progress changes

### Scenario 5 — Passive satisfaction path

Input:
- explicit bare rating in normal message
- praise short-form

Verify:
- passive capture writes rating data
- no slash command dependency exists

### Scenario 6 — Permission/security command path

Input:
- dangerous bash command

Verify:
- permission/security path blocks correctly
- logs are written correctly

## Suggested deliverables

- one script per scenario, or one orchestrator script with named cases
- clear PASS/FAIL output
- minimal fixture creation and cleanup

## Files likely to change

- `opencode/bin/test-behavioral.sh`
- new scripts under `opencode/bin/` or `opencode/tests/`
- docs describing canonical validation flows

## Success criteria

- at least 5 canonical flows are runnable on a VPS/headless box
- failures point to specific subsystem regressions
- test suite no longer depends primarily on grep-based confidence

## Recommendation to implementation agent

Do not try to replace the current lightweight behavioral harness. Add a **second layer** of canonical E2E scenarios on top of it.
