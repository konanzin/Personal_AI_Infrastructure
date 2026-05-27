# Kimi Workflow for PAI Mobile

This document describes how `opencode` with the `kimi-for-coding/k2p6` model is used as the primary coding arm for this repository.

## Invocation

```bash
# Standard coding session in this repo
opencode run --model kimi-for-coding/k2p6 \
  "Read ISA.md and implement the next approved slice."

# Continue the previous coding session
opencode run --model kimi-for-coding/k2p6 --continue
```

## Principles

1. **Architecture control stays human.** Kimi produces code; architectural decisions are reviewed and approved.
2. **ISA-driven development.** Every significant slice starts with or updates the `ISA.md` criteria.
3. **Minimal but coherent.** Code is kept small, but type-safe and well-structured.
4. **Bun-first.** Never npm. Never pnpm. Always Bun.
5. **TypeScript strict.** No `any` without explicit justification.

## Typical Session Flow

1. **Read the ISA.** Check `ISA.md` for current phase and criteria.
2. **State the slice.** Tell Kimi which milestone and specific criteria to target.
3. **Review the plan.** Kimi should present the execution plan before non-trivial changes.
4. **Approve or refine.** You adjust scope; Kimi executes.
5. **Verify inline.** Kimi verifies each criterion with tool calls (Read, Grep, Bash).
6. **Record evidence.** Verification is appended to the ISA.

## Example Prompts

```text
"Implement M1 contracts: define SessionSummary, SessionMessage, MessagePart, 
PermissionRequest, NotificationPayload in shared-types and shared-schemas. 
Follow ISA.md criteria ISC-13 through ISC-19."
```

```text
"Add the connectionStore and settingsStore to apps/mobile using Zustand. 
Extend the existing store pattern. TypeScript strict."
```

## What Kimi Does

- Scaffolds files and packages
- Writes TypeScript with strict types
- Refactors across the monorepo
- Adds tests and verifies them
- Updates the ISA and records verification

## What You Do

- Approve plans before execution
- Verify architectural decisions
- Test on real devices
- Merge and deploy

## Constraints

- Do not ask Kimi to run `bun install` if Bun is broken in the environment.
- Prefer file creation over package installation in broken environments.
- Always reference the ISA criteria in execution prompts.
