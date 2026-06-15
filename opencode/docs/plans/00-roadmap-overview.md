# PAI OpenCode — Gap Closure Roadmap

This directory holds implementation-ready plan files for closing the highest-value gaps in the PAI → OpenCode port.

Note: the current code-verified operational parity plan set lives under
`operational-parity/`. The older files in this directory predate the full
Claude Code original vs OpenCode port parity audit and cover only a subset of
the runtime.

## Constraints for this phase

- No Pulse dashboard work
- No visual/statusline work
- No voice notification work
- Must remain deployable on VPS / headless environments
- Mobile will be the future primary interface, so plans should prefer backend/state correctness over local desktop UX
- Prefer provider-agnostic architecture where possible

## Plan files

1. `01-mode-classifier-plan.md`
   - Recommendation for the best classifier model strategy
   - Provider-agnostic classification architecture
   - Implementation plan for restoring stronger mode/tier parity

2. `02-isa-work-state-sync-plan.md`
   - Plan to restore stronger ISA ↔ work-state parity
   - Explicitly excludes Pulse dashboard integration

3. `03-agent-skill-guard-plan.md`
   - Plan for AgentGuard / SkillGuard style safeguards in OpenCode

4. `04-runtime-e2e-validation-plan.md`
   - Plan for canonical real-session validation flows

5. `05-observability-parity-plan.md`
   - Plan for non-visual, non-voice observability parity

## Recommended execution order

1. Mode classifier
2. ISA/work-state sync
3. Agent/skill guard rails
4. Runtime E2E validation
5. Observability parity
