# Plan — Mode / Tier Classifier

## Decision

### Recommended model strategy

The best approach is **not** to hardwire the port to one vendor model. The best approach is:

- a **provider-agnostic classifier interface**
- with a **Sonnet-class model as the default parity target**
- and a **small-model fallback path** for environments where cost/latency matter more than perfect parity

### Recommendation

Use this hierarchy:

1. **Default parity model:** a Sonnet-class model
   - Reason: the original PAI doctrine explicitly used a stronger external classifier because mode/tier selection is foundational behavior
   - Goal: maximize fidelity first

2. **Configurable fallback model:** a cheaper/faster small model
   - Reason: VPS/mobile/backend deployments need cost control and portability

3. **Fail-safe:** deterministic fallback to `ALGORITHM E3`
   - Reason: under-escalation is worse than over-escalation in PAI doctrine

## Goal

Restore explicit mode/tier classification as a first-class subsystem rather than relying entirely on model-self-selection from injected system context.

## Scope

### In scope

- Provider-agnostic classifier interface
- External mode/tier classifier hook for top-level prompts
- Structured output: `MODE`, `TIER`, `REASON`, `SOURCE`
- Configurable default model
- Fail-safe path to `ALGORITHM E3`
- Telemetry for classifier outcomes

### Out of scope

- Dashboard rendering
- Mobile UI
- Voice announcements
- End-user visual controls

## Current gap

Today the port relies on:

- `experimental.chat.system.transform`
- model-native interpretation of mode rules

This is workable, but it is weaker than the original architecture because:

- classification is implicit
- classification quality depends on whatever model is currently answering
- there is no isolated telemetry stream for classifier correctness
- there is no separate fallback boundary

## Target architecture

### New subsystem

Add a prompt-classification path that runs before substantive execution for top-level prompts.

### Core contract

The classifier returns exactly:

```text
MODE: MINIMAL | NATIVE | ALGORITHM
TIER: E1 | E2 | E3 | E4 | E5   # only when MODE=ALGORITHM
REASON: one sentence
SOURCE: classifier | fail-safe | override
```

### Suggested implementation shape

1. Create a classifier utility module
   - input: raw user prompt + limited conversation context + optional explicit `/eN`
   - output: normalized classification object

2. Invoke it at the earliest viable OpenCode hook boundary for top-level prompts
   - if OpenCode cannot cleanly emulate `UserPromptSubmit`, use the closest pre-response boundary and persist the result

3. Persist result into session state
   - e.g. `MEMORY/STATE/current-work-<session>.json`
   - optionally append to `mode-classifier.jsonl`

4. Update the build agent/system prompt contract
   - executor reads explicit classifier output when present
   - falls back to current model-native behavior only if classifier is unavailable

## Files likely to change

- `opencode/plugins/pai-hooks.js`
- `opencode/plugins/lib/pai-hooks.lib.js`
- `opencode/config/opencode.jsonc.template`
- `opencode/docs/README-OPENCODE.md`
- `opencode/docs/CHANGELOG-OPENCODE.md`
- `opencode/bin/test-behavioral.sh`
- `opencode/bin/validate-pai-installation.sh`

## Implementation phases

### Phase 1 — interface + stub

- Define classifier result schema
- Add utility function with explicit fail-safe return
- Add tests for normalization and fail-safe behavior

### Phase 2 — hook integration

- Wire classifier to top-level prompts
- Store classification result in session-local state
- Ensure `/e1`–`/e5` overrides still win

### Phase 3 — executor integration

- Make runtime prefer classifier output over pure self-selection
- Preserve current system-context rules as backup behavior

### Phase 4 — telemetry + hardening

- Append classifier decisions to observability JSONL
- Capture latency, source, mode, tier, fallback rate

## Validation plan

### Must-pass behavioral cases

1. Greeting → `MINIMAL`
2. Single fact lookup → `NATIVE`
3. Single named-file tiny edit → `NATIVE`
4. Multi-file refactor → `ALGORITHM E3+`
5. Architecture question → `ALGORITHM E3/E4`
6. `/e1` override on complex ask → forced `ALGORITHM E1`
7. Classifier failure path → `ALGORITHM E3` fail-safe

## Success criteria

- Mode/tier is no longer purely emergent from the answering model
- Classifier behavior is configurable and portable
- Fail-safe is explicit
- Observability exists for classification quality

## Recommendation to implementation agent

Implement this as a **pluggable subsystem**, not as Anthropic-only doctrine. Parity target can be Sonnet-class, but the interface must remain provider-agnostic.
