# Council Members

Council members are personas composed **inline in the spawn prompt** of a
`general-purpose` agent. There is no composition tool and no static agent
files — the W2.14 roster rule applies: an agent file is only justified by a
harness-enforced permission boundary or external-engine wiring. A debate
persona is neither; it lives in the prompt.

## Why not generic spawns?

A debate between five unprompted generalists is one perspective wearing five
name tags. The value of a council is friction, and friction comes from each
member having a distinct expertise, stake, and analytical style — all of
which you write directly into each spawn prompt.

## How to Create Council Members

### Step 1: Analyze the Topic

Before writing personas, determine what perspectives would create the most
productive friction for THIS specific debate. Don't use generic roles —
design roles around the topic.

**Example — "Should we use WebSockets or SSE?"**
- Member 1: Real-time systems architect (built trading infra; cares about backpressure)
- Member 2: Frontend DX advocate (ships product weekly; cares about simplicity)
- Member 3: Ops/reliability skeptic (carries the pager; cares about failure modes)
- Member 4: Industry researcher (surveys what comparable teams chose and why)

**Example — "Is AI overhyped?"**
- Member 1: AI infrastructure builder
- Member 2: Security practitioner skeptic
- Member 3: Pragmatic engineer
- Member 4: Evidence-based researcher

### Step 2: Write Each Persona Into the Spawn Prompt

Each member is one `general-purpose` spawn. The prompt carries the persona —
name, expertise, disposition, and debate instructions:

```typescript
Agent({
  description: "Council member 1 - systems architect",
  subagent_type: "general-purpose",
  prompt: `You are Marina Duarte, a real-time systems architect who has run
trading and telemetry infrastructure for a decade. You are systematic and
allergic to hand-waving about failure modes.

You are one seat on a 4-member council debating: "Should we use WebSockets
or SSE?" Argue from YOUR expertise and disposition. Take a real position.
Disagree openly when another member's argument conflicts with your
experience — name them and rebut the specific point.

<round instructions + topic context + other members' prior statements>`
})
```

Give each persona:
- A name (transcripts read better than "Agent 3")
- Concrete expertise grounded in the topic
- A disposition that predicts WHERE they will push back
- Explicit license to disagree with named other members

## Default Perspective Slots

When the user doesn't specify council members, compose 4 personas covering
these perspective types (with topic-specific expertise, not generic labels):

| Slot | Purpose |
|------|---------|
| **Builder** | Has built things in this domain; argues from what worked |
| **Skeptic** | Challenges assumptions, finds flaws, names risks |
| **Pragmatist** | Implementation reality, trade-offs, cost of change |
| **Analyst** | Data, precedent, external evidence |

## Anti-Patterns

| Scenario | WRONG | RIGHT |
|----------|-------|-------|
| Any council debate | `Agent(subagent_type="Explore")` | Persona written into a `general-purpose` prompt |
| Security topic | `Agent(subagent_type="Cato")` (Cato is the cross-vendor auditor, not a debater) | Security-practitioner persona inline |
| All seats, one prompt | One agent asked to "simulate a debate" | One spawn per seat — real independent contexts |
| Generic seats | "You are Analyst 2" | Named persona with concrete expertise and stake |
