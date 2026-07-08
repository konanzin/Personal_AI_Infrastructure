---
name: Council
description: "Multi-agent collaborative debate that produces visible round-by-round transcripts with genuine intellectual friction. All council members are personas composed INLINE in the spawn prompt of general-purpose agents (W2.14 roster rule — no composition tool, no static agent types), each with domain expertise, disposition, and stake tailored to the specific topic. Two workflows: DEBATE (3 rounds, full transcript + synthesis, parallel execution within rounds, 40-90 seconds total) and QUICK (1 round, fast perspective check). Context files: CouncilMembers.md (inline persona design instructions), RoundStructure.md (three-round structure and timing), OutputFormat.md (transcript format templates). Personas are designed per debate topic to create real disagreement; 4-6 well-designed personas outperform 12 generic ones. Council is collaborative-adversarial (debate to find best path); for pure adversarial attack on an idea, use RedTeam instead. NOT FOR parallel task execution across agents (use Delegation skill). USE WHEN council, debate, multiple perspectives, weigh options, deliberate, get different views, multi-agent discussion, what would experts say, is there consensus, pros and cons from multiple angles."
effort: high
context: fork
---

## Customization

**Before executing, check for user customizations at:**
`~/.config/opencode/PAI/USER/SKILLCUSTOMIZATIONS/Council/`

If this directory exists, load and apply any PREFERENCES.md, configurations, or resources found there. These override default behavior. If the directory does not exist, proceed with skill defaults.

# Council Skill

Multi-agent debate system where custom-composed agents discuss topics in rounds, respond to each other's points, and surface insights through intellectual friction.

## CRITICAL: Custom Personas Only — Written Inline

**Compose each council member as a persona written directly into the spawn prompt of a `general-purpose` agent.** The reason (not a rule for its own sake): a debate between unprompted generalists is one perspective wearing five name tags — the persona in the prompt buys the diversity the council exists for. There is no composition tool and no static agent types for seats (W2.14 roster rule).

Council debates require personas with:
- Domain expertise tailored to the specific debate topic
- A name, disposition, and stake that predict where they push back
- Distinct analytical approaches that create genuine friction

See `CouncilMembers.md` for full persona design instructions.

**Key Differentiator from RedTeam:** Council is collaborative-adversarial (debate to find best path), while RedTeam is purely adversarial (attack the idea). Council produces visible conversation transcripts; RedTeam produces steelman + counter-argument.

## Workflow Routing

Route to the appropriate workflow based on the request.

| Trigger | Workflow |
|---------|----------|
| Full structured debate (3 rounds, visible transcript) | `Workflows/Debate.md` |
| Quick consensus check (1 round, fast) | `Workflows/Quick.md` |
| Pure adversarial analysis | RedTeam skill |

## Quick Reference

| Workflow | Purpose | Rounds | Output |
|----------|---------|--------|--------|
| **DEBATE** | Full structured discussion | 3 | Complete transcript + synthesis |
| **QUICK** | Fast perspective check | 1 | Initial positions only |

## Context Files

| File | Content |
|------|---------|
| `CouncilMembers.md` | How to design inline personas for council seats |
| `RoundStructure.md` | Three-round debate structure and timing |
| `OutputFormat.md` | Transcript format templates |

## Core Philosophy

**Origin:** Best decisions emerge from diverse perspectives challenging each other. Not just collecting opinions - genuine intellectual friction where domain-specific experts respond to each other's actual points.

**Personas:** Every council seat is a persona written into its spawn prompt — unique name, expertise, and disposition tailored to the topic. Generic unprompted spawns produce generic debate. Sharp personas produce sharp, informed debate.

**Speed:** Parallel execution within rounds, sequential between rounds. A 3-round debate of 4 agents = 12 agent calls but only 3 sequential waits. Complete in 40-90 seconds.

## Examples

```
"Council: Should we use WebSockets or SSE?"
-> Design 4 personas around the topic (real-time architect, frontend advocate, ops skeptic, researcher)
-> DEBATE workflow -> 3-round transcript

"Quick council check: Is this API design reasonable?"
-> Design 4 API-relevant personas
-> QUICK workflow -> Fast perspectives

"Council: Is AI overhyped?"
-> Personas: AI builder, security skeptic, pragmatic engineer, evidence analyst
-> DEBATE workflow -> 3-round transcript
```

## Integration

**Works well with:**
- **RedTeam** - Pure adversarial attack after collaborative discussion
- **Research** - Gather context before convening the council

## Best Practices

1. Use QUICK for sanity checks, DEBATE for important decisions
2. Design personas around the specific topic, not generic roles
3. Review the transcript - insights are in the responses, not just positions
4. Trust multi-agent convergence when it occurs
5. Write the persona into every spawn prompt — diversity of perspective is the point

---

**Last Updated:** 2026-07-08

## Gotchas

- **Council seats are inline personas on `general-purpose` spawns — never static agent types.** Cato is the cross-vendor auditor, not a debater.
- **Debates need genuine disagreement to be valuable.** If all agents agree, the topic may not warrant Council.
- **More agents ≠ better debate.** 4-6 well-designed personas outperform 12 generic ones.
