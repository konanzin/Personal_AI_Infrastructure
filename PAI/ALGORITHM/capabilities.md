# Algorithm Capabilities Reference

Loaded by OBSERVE on demand during capability selection.

## Thinking & Analysis Capabilities

Use these to enrich understanding BEFORE or DURING ISC writing. Select in the pre-ISC capability scan.

**Typical Cost column** (renamed from "Tier Fit" in Algorithm v5.0.0): the lowest effort tier at which this capability typically fits the budget. Pure information — not a restriction. The model decides per-task whether the capability is worth its cost given the tier time budget. At E1/E2, capabilities marked E3+ usually blow the budget; at E5 anything fits.

| Capability | Phases | Trigger Signal | Invoke | Typical Cost |
|------------|--------|----------------|--------|----------|
| IterativeDepth | OBSERVE | **Default at Extended+** when time budget allows deeper understanding; any important task where exploring the full problem space before ISC improves outcome; understanding what's actually being asked vs what was literally said; exploring different approach angles before committing; ambiguous scope, multi-faceted problems, hidden assumptions | `Skill("IterativeDepth")` | E2+ |
| FeedbackMemoryConsult | PLAN | **First step of PLAN at Extended+.** Before committing to approach, grep `~/.config/opencode/PAI/projects/${HARNESS_USER_DIR}/memory/feedback_*.md` by task keywords. Prevents repeating mistakes already documented. Turns the memory system from write-only diary into active guardrail. | `Bash('rg -l "KEYWORDS" ~/.config/opencode/PAI/projects/${HARNESS_USER_DIR}/memory/feedback_*.md')` | E2+ |
| Advisor | VERIFY | **At commitment boundaries on multi-step ISAs.** Before approach commitment, when stuck, once after durable deliverable before declaring done. Skip for short reactive tasks. If empirical results contradict advisor, re-call surfacing the conflict — do NOT silently switch. | `bun ~/.config/opencode/PAI/PAI/TOOLS/Inference.ts --mode advisor <task> <state> <question>` | E3+ |
| ReReadCheck | VERIFY→LEARN boundary | **Final gate before emitting response (v3.29 RR1).** Re-read user's last message verbatim; enumerate every explicit ask against what shipped; block `phase: complete` on any `✗`. Targets the 82% "missed ask" complaint cluster. MANDATORY at every tier — at E1 single-part it's a one-line block. No fast-path exemption. | *(inline doctrine step — no external tool)* | E1+ |
| FirstPrinciples | THINK | Architecture decisions, inherited assumptions, stuck on approach | `Skill("FirstPrinciples")` | E2+ |
| SystemsThinking | OBSERVE, THINK | Recurring problems, structural causes, feedback loops, unintended consequences, "why does this keep happening?" Iceberg model, causal loop diagrams, Senge archetypes, Meadows' 12 leverage points | `Skill("SystemsThinking")` | E3+ |
| Council | THINK, PLAN | Multi-perspective decision, trade-offs, controversial direction | `Skill("Council")` | E4+ |
| RedTeam | THINK, VERIFY | Strategy validation, stress-test plan, attack assumptions | `Skill("RedTeam")` | E4+ |
| Science | THINK→EXECUTE | Debugging hypothesis, systematic investigation, optimization | `Skill("Science")` | E3+ |
| BitterPillEngineering | VERIFY | Audit for over-engineering, dead weight, fragile scaffolding | `Skill("BitterPillEngineering")` | E3+ |
| Evals | VERIFY | Objective measurement, prompt comparison, quality scoring | `Skill("Evals")` | E4+ |
| ContextSearch | OBSERVE | Prior PAI work, session recovery, cold-start | `Skill("ContextSearch")` | E1+ |
| **ISA Skill** | **OBSERVE, PLAN, EXECUTE, VERIFY, LEARN** | **MANDATORY at E2+ for ISA scaffolding (`Skill("ISA", "scaffold from prompt at tier T")`), tier completeness checks (`Skill("ISA", "check completeness")`), ephemeral feature extraction at PLAN, canonical Decisions/Changelog/Verification entries via Append at any phase, and Reconcile after ephemeral feature work at LEARN. E1 may inline-write the minimal Goal+Criteria ISA to preserve <90s budget. The skill owns the canonical twelve-section template and refuses to write partial Deutsch C/R/L Changelog entries.** | `Skill("ISA", "<verb> <args>")` | E1+ |

## Code Quality Capabilities

The session model reviews its own changes (read the diff, run the tests). The
second-model reviewer is **Cato** — cross-vendor audit at E4/E5 via
`PAI/TOOLS/CrossVendorAudit.ts` (Verification Doctrine Rule 2a). W2.15: the
upstream /simplify, /batch, /code-review and /codex:* command rows were
phantoms in this port — no such commands ship; they were removed rather than
carried as wallpaper.

### Delegate code production (retired)

No second-model code producer ships. The Forge/Anvil producer line was retired across the two roster experiments (drift register W2.13/W2.14): the mandatory bindings predated evidence, the cross-family rationale collapsed on an OpenAI-primary harness, and Anvil ended the observation window with zero invocations and no engine configured on any machine. The session model writes the code; Cato audits it at E4/E5. If a real long-context engine need appears, re-adding the producer is a one-commit revert.

## Delegation & Infrastructure Capabilities

Use for parallel workstreams and non-blocking execution.

| Capability | When | Invoke |
|------------|------|--------|
| Agent Teams | **DEFAULT for parallel work.** 2+ agents on related work, task dependencies, coordination needed. Teammates persist, self-claim tasks, message peers. | `TeamCreate` + `Agent` with `team_name` |
| Custom Agents | **ONLY when {{PRINCIPAL_NAME}} says "custom agents".** Unique personas written inline into each spawn prompt (W2.14 roster rule). One-shot parallel work. | `Agent(subagent_type="general-purpose", prompt=<persona + task>)` |
| Delegation | 3+ independent workstreams (routes to above) | `Skill("Delegation")` |
| Worktree Isolation | Parallel write-agents on overlapping files | `Agent` with `isolation: "worktree"` |
| Background Agents | Non-blocking research or verification | `Agent` with `run_in_background: true` |
| Observer Team | **ONLY when time is not a constraint AND auditability is the primary requirement.** 2-3 read-only observer agents (inline personas: log auditor, safety skeptic) watch `tool-activity.jsonl` (ground-truth audit log), vote continue/halt/escalate. Deliberate speed-for-safety trade — not for interactive work. | `Agent(subagent_type="general-purpose", prompt=<observer persona>)` per seat |
| Monitor | Event-driven waiting: logs, deploys, CI, file changes | `Monitor` tool — each stdout line wakes the agent |
| Mass Parallelism | Large migrations, bulk refactors across many files | N parallel `Agent` spawns with `isolation: "worktree"` |

## Research & Intelligence Capabilities

Use when external information is needed.

| Capability | When | Invoke |
|------------|------|--------|
| Research | External context, multi-source investigation | `Skill("Research")` |
| ContextSearch | Prior PAI work, session recovery | `Skill("ContextSearch")` |
| Claude Code Guide | Claude Code internals, hooks, settings | `Agent(subagent_type="claude-code-guide")` |

## Agent Routing (Preference Order)

| Priority | User says | System | Invoke |
|----------|-----------|--------|--------|
| **1. DEFAULT** | "parallel work", "agents", "team", "swarm", or Algorithm selects delegation | **Agent Teams** — persistent teammates, shared task list, peer messaging | `TeamCreate` + `Agent` with `team_name` |
| **2. EXPLICIT** | "custom agents", "spin up custom agents" | **Custom Agents** — unique personas written inline into each spawn prompt | `Agent(subagent_type="general-purpose", prompt=<persona + task>)` |
| **3. UNATTENDED** | "run overnight", "long-running", "CI", or task exceeds session lifetime | **Background agents** — non-blocking, harness-tracked | `Agent` with `run_in_background: true` |
| **4. INTERNAL** | (Algorithm internal routing, user names a type) | **Built-in types** (Explore, Cato, CodexResearcher, general-purpose, etc.) | `Agent(subagent_type="...")` |

## Binding Commitment

Selecting a capability = binding commitment to invoke it via tool. If you realize mid-execution it's unneeded, remove it from the list with a reason.

## Proactive Skill Scan

The tables above cover the most commonly applicable capabilities. For domain-specific tasks, also check the system prompt skill list for specialized skills (e.g., ArXiv for paper search, Interceptor for web verification, Telos for life-context work). Match skill triggers to the current task domain.

## Codex Operations

The codex engine is reached through two shipped surfaces only: **Cato**
(`PAI/TOOLS/CrossVendorAudit.ts`, engine per `USER/Config/cato.json`) and the
**CodexResearcher** subagent. The upstream /codex:* management commands do not
exist in this port (W2.15).

## Agent Composition Guidelines

When spawning agents: provide raw source material not summaries, parallelize independent threads, use background agents for non-blocking work, don't duplicate work agents are already doing.

## Output Format

```
🏹 CAPABILITIES SELECTED:
 🏹 [Each capability, target phase, 8-word reason, use as many appropriate Capabilities as possible given the amount of time you have]
🏹 [12-24 words on selection rationale]
```
