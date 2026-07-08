# Standard Research Workflow

**Mode:** 4 different researcher types, 1 query each | **Timeout:** 2 minutes

## 🚨 CRITICAL: URL Verification Required

**BEFORE delivering any research results with URLs:**
1. Verify EVERY URL using WebFetch or curl
2. Confirm the content matches what you're citing
3. NEVER include unverified URLs - research agents HALLUCINATE URLs
4. A single broken link is a CATASTROPHIC FAILURE

See `SKILL.md` for full URL Verification Protocol.

## When to Use

- Default mode for most research requests
- User says "do research" or "research this"
- Need multiple perspectives quickly

## Workflow

### Step 1: Craft One Query Per Angle

Create ONE focused query per research angle (the angles live in the prompt, not in named personas — the old vendor-named researchers were four identical websearch agents; drift register W2.14):
- **Depth**: academic depth, detailed analysis, scholarly sources
- **Breadth**: multi-perspective synthesis, cross-domain connections
- **Contrarian**: counter-consensus, fact-based; long-term truth over short-term trend
- **Current-state**: live-web retrieval with citations; freshest snapshot

### Step 2: Launch 4 Agents in Parallel (1 per angle)

**SINGLE message with 4 Task calls:**

```typescript
Task({
  subagent_type: "general-purpose",
  description: "[topic] depth angle",
  prompt: "Do ONE search for: [query optimized for depth/analysis]. Tag each finding with confidence: [HIGH], [MED], or [LOW]. Return findings immediately."
})

Task({
  subagent_type: "general-purpose",
  description: "[topic] breadth angle",
  prompt: "Do ONE search for: [query optimized for breadth/perspectives]. Tag each finding with confidence: [HIGH], [MED], or [LOW]. Return findings immediately."
})

Task({
  subagent_type: "general-purpose",
  description: "[topic] contrarian angle",
  prompt: "Do ONE search for: [query optimized for contrarian/long-term-truth angle]. Prefer counter-consensus signal and durable facts over trending narrative. Tag each finding with confidence: [HIGH], [MED], or [LOW]. Return findings immediately."
})

Task({
  subagent_type: "general-purpose",
  description: "[topic] current-state angle",
  prompt: "Do ONE search for: [query optimized for live-web current state with citations]. Tag each finding with confidence: [HIGH], [MED], or [LOW]. Return findings immediately."
})
```

**Each agent:**
- Gets ONE query
- Does ONE search
- Returns immediately

### Step 3: Cross-Check Synthesis

Combine the four perspectives **with confidence scoring and conflict detection:**

1. **Cross-reference findings:** Where two or more agents report the same fact → tag `[HIGH]`
2. **Flag unique findings:** Findings from only one agent → tag `[MED]`
3. **Detect contradictions:** Where agents disagree → tag `[CONFLICT]` with both sides
4. **Quantitative check:** Any number cited by one agent — did any other agent's sources confirm it?

This adds ~2-3 seconds to synthesis (reading all four results with conflict lens) — well within the <5s budget.

### Step 4: Parallel URL Verification

Agents now self-verify URLs before returning. For any remaining unverified URLs, batch-verify in parallel:

```bash
# Parallel URL check (not sequential)
for url in "${urls[@]}"; do curl -s -o /dev/null -w "%{http_code} $url\n" -L "$url" & done; wait
```

**If URL fails:** Remove it. If the finding was `[HIGH]` based on cross-reference, downgrade to `[MED]`.

### Step 5: Return Results

```markdown
📋 SUMMARY: Research on [topic]
🔍 ANALYSIS: [Key findings with confidence tags: [HIGH] [MED] [LOW] [CONFLICT]]
⚡ ACTIONS: 4 researchers × 1 query each + cross-check synthesis
✅ RESULTS: [Synthesized answer]
📊 STATUS: Standard mode - 4 agents, cross-checked
📁 CAPTURE: [Key verified facts]
➡️ NEXT: [Suggest extensive if CONFLICT items need resolution]
📖 STORY EXPLANATION: [5-8 numbered points]
🎯 COMPLETED: Research on [topic] complete
```

## Speed Target

~15-30 seconds for results
