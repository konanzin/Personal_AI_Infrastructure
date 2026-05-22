# Plan — AgentGuard / SkillGuard Parity

## Goal

Add guard rails that reduce bad agent/skill invocation decisions in the OpenCode port, without building any visual or Pulse dashboard surfaces.

## Current gap

The original architecture had stronger pre-execution controls around:

- agent spawning
- skill invocation
- high-cost / low-fit orchestration decisions

The OpenCode port currently has stronger command/file security than orchestration security.

## What this plan should achieve

### AgentGuard

Block or warn on:

- unnecessary agent spawning for trivial lookups
- spawning where direct tools are cheaper/faster
- too many agents for low-value work
- agent usage where permissions/risk profile are wrong

### SkillGuard

Block or warn on:

- obvious misfires of high-specificity skills
- repeated accidental invocation of adjacent-but-wrong skills
- skills used where a native tool path is simpler

## Scope

### In scope

- backend guard logic
- observability of guard decisions
- allow/warn/block outcomes

### Out of scope

- Pulse HTTP routes
- visual moderation UI
- manual approval dashboard

## Suggested architecture

### AgentGuard contract

Input:
- requested subagent type
- task description
- optional prompt length / task complexity signals

Output:
- `allow`
- `warn`
- `deny`
- rationale string

### SkillGuard contract

Input:
- requested skill name
- user request / triggering text

Output:
- `allow`
- `warn`
- `deny`
- rationale string

## Integration points

### AgentGuard

- prefer pre-tool boundary when agent/task tool is invoked
- log decisions to observability JSONL

### SkillGuard

- prefer pre-tool boundary when skill tool is invoked
- log decisions to observability JSONL

## Rules to implement first

### AgentGuard v1

- deny/warn when direct `glob/read/grep` would suffice for trivial lookup
- warn when agent fan-out exceeds a configured threshold
- warn when task prompt is too vague for delegation

### SkillGuard v1

- warn when skill description clearly mismatches request keywords
- warn when request is obviously native-tool-simple
- warn when a high-cost skill is used for a trivial ask

## Files likely to change

- `opencode/plugins/pai-hooks.js`
- `opencode/plugins/lib/pai-hooks.lib.js`
- `opencode/bin/test-behavioral.sh`
- `opencode/docs/README-OPENCODE.md`
- `opencode/docs/CHANGELOG-OPENCODE.md`

## Validation plan

### Must-pass cases

1. trivial file lookup → guard warns against agent spawn
2. large multi-threaded task → guard allows agent use
3. clearly wrong skill invocation → guard warns or denies
4. native-tool-simple request → guard warns against skill overuse

## Success criteria

- orchestration mistakes are reduced before execution
- decisions are observable in logs
- solution remains headless and VPS-friendly

## Recommendation to implementation agent

Start with **warn-first** behavior. Only promote to deny where the misfire pattern is extremely high-confidence.
