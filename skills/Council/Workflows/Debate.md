# Debate Workflow

Full structured multi-agent debate with 3 rounds and visible transcript.

## Voice Notification

```bash
(curl -s --max-time 2 -X POST http://localhost:31337/notify \
  -H "Content-Type: application/json" \
  -d '{"message": "Running the Debate workflow in the Council skill to run multi-agent debate", "language": "en-US"}' \
  > /dev/null 2>&1 || true) &
```

Running the **Debate** workflow in the **Council** skill to run multi-agent debate...

## Prerequisites

- Topic or question to debate
- Optional: Custom council member descriptions (otherwise auto-composed)

## CRITICAL: Persona Design

**ALL council members are personas written inline into the spawn prompt of `general-purpose` agents. NEVER use static agent types (Explore, Cato, etc.) for seats.**

Unprompted spawns are generic and topic-ignorant. Council debates require personas with domain-specific knowledge, a name, and distinct analytical approaches tailored to the debate topic.

See `CouncilMembers.md` for full persona design instructions.

## Execution

### Step 0: Design Council Members

Before any debate rounds, analyze the topic, decide which 4 perspectives create productive friction, and write one persona per seat — name, expertise, disposition, stake. These persona blocks go verbatim at the top of each spawn prompt (see `CouncilMembers.md` for the shape). Default slots when the user doesn't specify: Builder, Skeptic, Pragmatist, Analyst — each grounded in the topic, not generic.

### Step 1: Announce the Council

Output the debate header with the persona names:

```markdown
## Council Debate: [Topic]

**Council Members:** [List persona names with one-line expertise descriptions]
**Rounds:** 3 (Positions -> Responses -> Synthesis)
```

### Step 2: Round 1 - Initial Positions

Launch 4 parallel Agent calls (one per council member), each with `subagent_type: "general-purpose"`.

**Each agent prompt includes the member's persona block PLUS:**
```
COUNCIL DEBATE - ROUND 1: INITIAL POSITIONS

Topic: [The topic being debated]

[Full topic context — include relevant background, data, quotes, etc. that the agent needs to form an informed opinion]

Give your initial position on this topic from your specialized perspective.
- Speak in first person as your character
- Be specific and substantive (100-150 words)
- State your key concern, recommendation, or insight
- You'll respond to other council members in Round 2
```

**Output each response as it completes:**
```markdown
### Round 1: Initial Positions

**[Agent 1 Name] ([trait description]):**
[Response]

**[Agent 2 Name] ([trait description]):**
[Response]

**[Agent 3 Name] ([trait description]):**
[Response]

**[Agent 4 Name] ([trait description]):**
[Response]
```

### Step 3: Round 2 - Responses & Challenges

Launch 4 parallel Agent calls with Round 1 transcript included.

**Each agent prompt includes the member's persona block PLUS:**
```
COUNCIL DEBATE - ROUND 2: RESPONSES & CHALLENGES

Topic: [The topic being debated]

Here's what the council said in Round 1:
[Full Round 1 transcript]

Now respond to the other council members:
- Reference specific points they made ("I disagree with [Name]'s point about X...")
- Challenge assumptions or add nuance
- Build on points you agree with
- Maintain your specialized perspective
- 100-150 words

The value is in genuine intellectual friction -- engage with their actual arguments.
```

### Step 4: Round 3 - Synthesis

Launch 4 parallel Agent calls with Round 1 + Round 2 transcripts.

**Each agent prompt includes the member's persona block PLUS:**
```
COUNCIL DEBATE - ROUND 3: SYNTHESIS

Topic: [The topic being debated]

Full debate transcript so far:
[Round 1 + Round 2 transcripts]

Final synthesis from your perspective:
- Where does the council agree?
- Where do you still disagree with others?
- What's your final recommendation given the full discussion?
- 100-150 words

Be honest about remaining disagreements -- forced consensus is worse than acknowledged tension.
```

### Step 5: Council Synthesis

After all rounds complete, synthesize the debate:

```markdown
### Council Synthesis

**Areas of Convergence:**
- [Points where 3+ agents agreed]
- [Shared concerns or recommendations]

**Remaining Disagreements:**
- [Points still contested between agents]
- [Trade-offs that couldn't be resolved]

**Recommended Path:**
[Based on convergence and weight of arguments, the recommended approach is...]
```

## Timing

- Persona design: ~5-10 seconds (written inline, no tool calls)
- Round 1: ~10-20 seconds (parallel)
- Round 2: ~10-20 seconds (parallel)
- Round 3: ~10-20 seconds (parallel)
- Synthesis: ~5 seconds

**Total: 40-90 seconds for full debate**

## Done

Debate complete. The transcript shows the full intellectual journey from initial positions through challenges to synthesis.
