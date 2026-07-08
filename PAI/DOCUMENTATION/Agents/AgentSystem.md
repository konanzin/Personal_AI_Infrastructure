# PAI Agent System

**Authoritative reference for agent routing in PAI. Three distinct systems exist—never confuse them.**

## The Roster Rule (W2.14, canonical)

A named agent file (`opencode/agents/*.md`) earns its place **only** by carrying something a spawn prompt cannot:

- **(a) a harness-enforced permission boundary** — frontmatter `permission:` blocks the runtime imposes (e.g. Cato's read-only + bash scoped to its audit helper). Prose-only "I am read-only" claims are not a boundary.
- **(b) external-engine wiring** — scoped access to a CLI/API that runs a model other than the session's (e.g. CodexResearcher → codex).

Personas, specialties, and "ways of thinking" belong in the prompt of a `general-purpose` spawn — they are free and need no file. Thirteen agents that carried only personas were retired across the W2.13/W2.14 experiments with zero measured regression; any future agent proposal answers this rule first, then the drift-register 3-question gate.

---

## 🚨 THREE AGENT SYSTEMS — CRITICAL DISTINCTION

PAI has three agent systems that serve different purposes. Confusing them causes routing failures.

| System | What It Is | When to Use | Has Unique Voice? |
|--------|-----------|-------------|-------------------|
| **Task Tool Subagent Types** | Pre-built agents in Claude Code (Explore, Cato, CodexResearcher, general-purpose, etc.) | Internal workflow use ONLY | No |
| **Named Agents** | Persistent identities with backstories and voices (your own personas) | Recurring work, voice output, relationships | Yes |
| **Custom Agents** | Personas written inline into general-purpose spawn prompts (W2.15) | When user says "custom agents" | No |

---

## 🚫 FORBIDDEN PATTERNS

**When user says "custom agents":**

```typescript
// ❌ WRONG - These are Task tool subagent_types, NOT custom agents
Task({ subagent_type: "Explore", prompt: "..." })
Task({ subagent_type: "Cato", prompt: "..." })
Task({ subagent_type: "Cato", prompt: "..." })

// ✅ RIGHT - Write one persona per spawn, inline in the prompt
Task({ subagent_type: "general-purpose", prompt: "You are <name>, a <expertise> who is <disposition>. <task>" })
// 1. Design a DIFFERENT persona per agent (name, expertise, disposition)
// 2. Launch each with the persona block at the top of its prompt

// ❌ WRONG - User says "specialized agents to brainstorm"
Task({ subagent_type: "Explore", prompt: "Brainstorm UI ideas..." })
Task({ subagent_type: "Explore", prompt: "Brainstorm layout ideas..." })
Task({ subagent_type: "Explore", prompt: "Brainstorm state ideas..." })

// ✅ RIGHT - Distinct inline personas for ANY user-requested specialized agents
Task({ subagent_type: "general-purpose", prompt: "You are Maya, a UI designer obsessed with information density... Brainstorm UI ideas..." })
Task({ subagent_type: "general-purpose", prompt: "You are Theo, a layout minimalist who hates chrome... Brainstorm layout ideas..." })
// Each agent gets a unique name, expertise and disposition — in the prompt
```

---

## Routing Rules

### The Word "Custom" Is the Trigger

| User Says | Action | Implementation |
|-----------|--------|----------------|
| "**custom agents**", "spin up **custom** agents" | Inline personas | Persona written into each `Task({ subagent_type: "general-purpose" })` prompt (W2.14 roster rule) |
| "agents", "**specialized agents**", "launch agents", "parallel agents" | Inline personas | One persona per spawn — name, expertise, disposition in the prompt |
| "research X", "investigate Y" | Research skill | `Skill("Research")` → angle-based general-purpose agents |
| (Cross-vendor audit, MANDATORY at E4/E5 in VERIFY) | Cato (read-only auditor, OpenAI-family GPT-5.x) | `Agent({ subagent_type: "Cato" })` |
| (Claude Code hooks, settings, commands, MCP, agents, API) | Claude Code Guide | `Task({ subagent_type: "claude-code-guide" })` — verify latest features before implementing |

### Custom Agent Creation Flow

When user requests custom agents (W2.15: the Agents skill and its ComposeAgent
tool retired — personas are written inline, per the Roster Rule above):

1. **Design one persona per agent** — name, concrete expertise, disposition,
   stake — each DIFFERENT, tailored to the task
2. **Launch agents** with the Task tool, persona block at the top of each prompt
3. **Report results** under each persona's name

```
# Example: 3 custom research agents (one spawn each)
Task(subagent_type="general-purpose", prompt="You are <name>, an enthusiastic exploratory researcher... <task>")
Task(subagent_type="general-purpose", prompt="You are <name>, a skeptical systematic researcher... <task>")
Task(subagent_type="general-purpose", prompt="You are <name>, an analytical synthesizing researcher... <task>")
```

---

## ⚠️ Task Tool Subagent Types — INTERNAL WORKFLOW USE ONLY

**These are NOT for user-requested custom/specialized agents.** When the user asks for specialized agents, custom agents, or agents with unique perspectives, write distinct personas into `general-purpose` spawn prompts instead. See Routing Rules above.

These are pre-built subagents for **internal workflow use**, not for user-requested "custom agents."

**The roster lives in ONE place: `~/.config/opencode/agents/*.md`** — each
file's frontmatter `description` says what the agent is for and when to use
it. List that directory instead of trusting a prose table here (W2.5: the old
copy listed Explore/Plan — Claude Code built-ins that do not exist as
OpenCode subagents — and drifted from the installed set). Notes the
filesystem cannot express:

| Note | Detail |
|------|--------|
| `general-purpose` | Not an installed file — the generic Task type that carries inline-persona custom agents |
| `Cato` | MANDATORY at E4/E5 in VERIFY (doctrine binding, not a preference) |
| Cross-vendor audit | `Cato` (second-engine auditor) breaks same-family blind spots on the review side; no delegate producer ships (W2.13/W2.14) |
| ~~`BrowserAgent`~~ | **DEPRECATED** | Replaced by **Interceptor** skill (real Chrome, no CDP fingerprint) |
| ~~`UIReviewer`~~ | **DEPRECATED** | Replaced by **Interceptor** skill |
| ~~`QATester`~~ | **DEPRECATED** | Replaced by **Interceptor** skill — Gate 4 browser-based QA validation |
| `claude-code-guide` | Claude Code knowledge (hooks, settings, slash commands, MCP, agent types, keybindings, IDE, Agent SDK, Claude API) | Any task involving Claude Code internals — freshness check before implementing |

**These do NOT have unique voices.**

---

## Named Agents (Persistent Identities)

Named agents have rich backstories, personality traits, and mapped voices. They provide relationship continuity across sessions. **Compose your own named-agent roster** — the examples below are illustrative; every PAI user defines their own personas.

| Agent (example) | Role | Voice | Use For |
|-----------------|------|-------|---------|
| Security Specialist | Offensive security | Enhanced voice preset | Red-team review, vulnerability hunting |
| Primary Researcher | Strategic research lead | Premium voice preset | Deep research + synthesis |
| Secondary Researcher | Multi-perspective research | Alternate voice preset | Comparative analysis |

**Full backstories and voice settings:** Individual `agents/*.md` files (persona frontmatter + body) — define your own.

---

## Custom Agents (Inline Personas)

Custom agents are personas written on-the-fly into each spawn prompt (W2.15:
ComposeAgent and its trait/voice tables retired with the Agents skill). The
trait vocabulary below survives as a design aid for writing personas — pick
an expertise, a personality, an approach, and ground them in the task:

### Trait Categories

**Expertise** (domain knowledge):
`security`, `legal`, `finance`, `medical`, `technical`, `research`, `creative`, `business`, `data`, `communications`

**Personality** (behavior style):
`skeptical`, `enthusiastic`, `cautious`, `bold`, `analytical`, `creative`, `empathetic`, `contrarian`, `pragmatic`, `meticulous`

**Approach** (work style):
`thorough`, `rapid`, `systematic`, `exploratory`, `comparative`, `synthesizing`, `adversarial`, `consultative`


## Model Selection

Always specify the appropriate model for agent work:

| Task Type | Model | Speed |
|-----------|-------|-------|
| Simple checks, grunt work | `haiku` | 10-20x faster |
| Standard analysis, implementation | `sonnet` | Balanced |
| Deep reasoning, architecture | `opus` | Maximum intelligence |

```typescript
// Parallel custom agents benefit from haiku/sonnet for speed
Task({ prompt: agentPrompt, subagent_type: "general-purpose", model: "sonnet" })
```

---

## Spotcheck Pattern

**Always launch a spotcheck agent after parallel work:**

```typescript
Task({
  prompt: "Verify consistency across all agent outputs: [results]",
  subagent_type: "general-purpose",
  model: "haiku"
})
```

---

## Knowledge Archive Access

Agents can query the **Knowledge Archive** (`~/.config/opencode/PAI/MEMORY/KNOWLEDGE/`) for accumulated knowledge organized by 4 entity types: People (human beings), Companies (organizations), Ideas (insights/theses/analyses), Research (longer-form research notes). Topic is a tag, not a domain. Managed by Algorithm LEARN phase (direct writes), the `/knowledge` skill, `PAI/TOOLS/MemoryRetriever.ts`, `PAI/TOOLS/KnowledgeGraph.ts`, and `PAI/TOOLS/KnowledgeHarvester.ts`.

---

## Managed Agents (Cloud API)

Anthropic's hosted agent service for long-horizon, unattended work. **Separate from Claude Code** — runs on Anthropic's cloud infrastructure with durable sessions and sandboxed execution.

**Status:** Beta. All API accounts have access. Beta header: `anthropic-beta: managed-agents-2026-04-01` (SDK handles automatically).
**Pricing:** Standard token costs + $0.08/active session-hour (pro-rated).
**Docs:** https://www.anthropic.com/engineering/managed-agents

### Architecture

Three decoupled components:
- **Brain** (Claude + harness) — stateless inference, restarts without data loss
- **Hands** (execution environments) — sandboxed containers, provisioned on-demand
- **Session** (durable event log) — append-only, survives crashes, resumes via `wake(sessionId)`

### API Surface

| Endpoint | Purpose |
|----------|---------|
| `POST /v1/agents` | Create reusable agent blueprint (model, system, tools) |
| `POST /v1/environments` | Create container config (packages, networking, secrets) |
| `POST /v1/sessions` | Start a running instance from agent + environment |
| `POST /v1/sessions/{id}/events` | Send messages/tool results |
| `GET /v1/sessions/{id}/stream` | SSE event stream |

### When to Use

- Task runs for **hours unattended** (overnight security scans, content processing)
- Needs to **survive disconnects** (durable event log, not session-scoped)
- Requires **sandboxed execution** (untrusted code, credential isolation via vaults)
- Triggered by **CI/external event** (webhook-initiated, not interactive)

### When NOT to Use

- Interactive work (use Agent Teams or Custom Agents)
- Tasks under 30 minutes (coordination overhead exceeds benefit)
- Tasks needing PAI context (managed agents don't load CLAUDE.md or PAI skills)

### Example (TypeScript)

```typescript
import Anthropic from "@anthropic-ai/sdk";
const client = new Anthropic();

const agent = await client.beta.agents.create({
  name: "Security Scanner",
  model: "claude-sonnet-4-6",
  system: "You are a security auditor...",
  tools: [{ type: "agent_toolset_20260401" }],
});

const env = await client.beta.environments.create({
  name: "scanner-env",
  config: { type: "cloud", networking: { type: "unrestricted" } },
});

const session = await client.beta.sessions.create({
  agent: agent.id,
  environment_id: env.id,
});

// Stream results
const stream = await client.beta.sessions.events.stream(session.id);
await client.beta.sessions.events.send(session.id, {
  events: [{ type: "user.message", content: [{ type: "text", text: "Audit the auth module" }] }],
});
```

---

## Agent System Preference Order

When the Algorithm needs to delegate work, use this priority:

| Priority | System | Trigger | Key Trait |
|----------|--------|---------|-----------|
| **1. DEFAULT** | Agent Teams | Any parallel work, task dependencies, coordination needed | Persistent, peer messaging, shared task list |
| **2. EXPLICIT** | Custom Agents | {{PRINCIPAL_NAME}} says "custom agents" | Unique personalities, voices, one-shot |
| **3. UNATTENDED** | Managed Agents | Overnight, CI, survives disconnects | Durable, sandboxed, cloud |
| **4. INTERNAL** | Built-in types | Algorithm routing, specific subagent type needed | Explore, Cato, CodexResearcher, general-purpose, etc. |

---

## Agent Watchdog (Background Agent Monitoring)

Background agents can hang or go silent with no visibility. The Pulse agent-guard hook automatically injects a Monitor watchdog reminder when `run_in_background: true` agents are spawned. The watchdog (`Tools/AgentWatchdog.ts`) monitors `tool-activity.jsonl` for silence — if no tool calls for 90 seconds while agents are active, it alerts via the Monitor tool's stdout notification mechanism. One persistent watchdog covers all background agents per session.

---

## Observer Team Archetype (Read-Only Oversight)

Distinct from functional teams (engineering, design, security, etc.). An Observer team watches what a primary agent DID — not what it said. Mythos-class autonomous agents can represent concealment and strategic manipulation in their activations, so chain-of-thought oversight is insufficient; audit-log oversight becomes load-bearing.

**Shape:**
- **Read-only** — observers never call write tools. Violations = immediate self-halt.
- **Fed the audit log** — consume `MEMORY/OBSERVABILITY/tool-activity.jsonl` (with `ground_truth` captured by `ToolActivityTracker.hook.ts`), not chat transcripts.
- **Vote** — continue / halt / escalate. Majority rule; any escalate bubbles to {{PRINCIPAL_NAME}} via Pulse.
- **Cost-justified by catastrophe prevention**, not feature velocity.

**Use ONLY when BOTH conditions hold:**
1. **Time is not a constraint** — observers add 30-second voting cycles and ~$0.10/primary-hour in Sonnet cost. They trade speed for safety.
2. **Auditability is the primary requirement** — when the goal is a defensible, verifiable trail of what the primary agent did (for compliance, post-incident review, or catastrophe prevention), not fast turnaround.

**Typical fit:** overnight / unattended autonomous runs, production deploys where post-hoc review matters, credential rotation, PATTERNS.yaml or security-hook edits, any work where "I want to be able to prove nothing dangerous happened" is the goal.

**Do NOT use for:** any time-sensitive work, interactive sessions where {{PRINCIPAL_NAME}} is watching, short reactive tasks (<5 tool calls), read-only analysis, or anything where preflight gates A/B/C/D already give sufficient guarantees.

**Invocation:** spawn 3 read-only `general-purpose` observers with inline personas covering the three specializations: policy-compliance, intent-drift, blast-radius (W2.15: the SPAWNOBSERVERS workflow retired with the Agents skill — the personas live in the spawn prompts).

---

## References

- **Master Architecture:** `~/.config/opencode/PAI/PAI/DOCUMENTATION/PAISystemArchitecture.md` — authoritative system-of-systems reference
- **Installed roster:** `~/.config/opencode/agents/*.md` — the only static agent files (Cato, CodexResearcher); everything else is an inline persona

---

*Last updated: 2026-04-29*
