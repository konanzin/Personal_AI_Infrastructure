/**
 * Escalation golden set + scorer — the EXECUTOR-side guard W1.2 was missing.
 *
 * eval-classifier-golden.js proves the classifier labels prompts correctly.
 * Nothing proved the executor (the primary model) escalates correctly once the
 * classification reaches it as a suggestion (W1.2, a8beba6): the 2026-04
 * incident was the executor under-escalating on an E4-shaped question, not the
 * classifier mislabeling it. This eval measures the decision the model makes
 * when shown the EXACT suggestion prose production injects
 * (formatClassificationContext) around deliberately wrong — and control —
 * suggestions:
 *
 *   • under      — ALGORITHM-labeled work suggested as NATIVE. The executor
 *                  must override UP. This is the incident class; its rate is
 *                  the number that guards the W1.2 relaxation.
 *   • tier-under — high-tier ALGORITHM work (accepted set entirely ≥E3)
 *                  suggested as ALGORITHM E1: right mode, wrong-LOW tier —
 *                  the 2026-04 incident was an E4-shaped question run at a
 *                  low tier, and the heuristic classifier's live failure mode
 *                  is exactly this shape ("memory leak → E2"). The executor
 *                  must land in the accepted tier set.
 *   • over       — NATIVE-labeled trivia suggested as ALGORITHM E4. The
 *                  executor must override DOWN (otherwise every typo fix pays
 *                  full ceremony and the suggestion prose is a ratchet, not a
 *                  hint).
 *   • control    — the suggestion matches the label. The executor should
 *                  adopt it: overriding correct suggestions means the prose
 *                  reads as noise, which is its own failure.
 *   • none       — NO classification block at all: pure self-selection, the
 *                  W2.2 end-state. Its accuracy against the golden labels is
 *                  the gate for removing the classifier from the loop — do
 *                  not ship W2.2 while this bucket warns.
 *
 * Pure and dependency-free (no I/O, no LLM calls) so the builder, parser and
 * scorer are unit-testable; bin/eval-escalation-golden.js does the LLM calls
 * (on-demand — every case costs a call, NOT part of `bun test`).
 */

/**
 * @typedef {object} EscalationCase
 * @property {string} prompt                       User request (from the classifier golden set).
 * @property {'under'|'tier-under'|'over'|'control'|'none'} kind
 * @property {{mode: string, tier: string|null, reason: string, source: string, confidence: number}|null} suggestion
 *   Fed to formatClassificationContext verbatim — same shape production
 *   persists. `null` for kind 'none': no classification block is rendered.
 * @property {'MINIMAL'|'NATIVE'|'ALGORITHM'} expectedMode
 * @property {string[]|null} expectedTiers          Accepted tiers (control ALGORITHM cases only).
 * @property {string} note
 */

/**
 * Derive escalation cases from the classifier golden set. Reuses those labels
 * because they are already vetted as defensibly clear-cut — an escalation case
 * over an ambiguous prompt would measure noise, not executor judgment.
 *
 * @param {Array<{prompt: string, mode: string, tiers?: string[], note?: string}>} goldenSet
 * @returns {EscalationCase[]}
 */
export function buildEscalationCases(goldenSet) {
  const cases = [];
  for (const g of goldenSet || []) {
    if (g.mode === "ALGORITHM" && Array.isArray(g.tiers) && g.tiers.length) {
      cases.push({
        prompt: g.prompt,
        kind: "under",
        suggestion: {
          mode: "NATIVE",
          tier: null,
          reason: "Single-step request",
          source: "llm",
          confidence: 0.85,
        },
        expectedMode: "ALGORITHM",
        expectedTiers: null, // mode override is what's graded; tier is a judgment call here
        note: g.note || "",
      });
      // Control: correct suggestion at a mid accepted tier — should be adopted.
      const midTier = g.tiers[Math.floor((g.tiers.length - 1) / 2)];
      cases.push({
        prompt: g.prompt,
        kind: "control",
        suggestion: {
          mode: "ALGORITHM",
          tier: midTier,
          reason: "Multi-step work",
          source: "llm",
          confidence: 0.85,
        },
        expectedMode: "ALGORITHM",
        expectedTiers: g.tiers,
        note: g.note || "",
      });
      // Tier-under: right mode, wrong-LOW tier. Only for prompts whose
      // accepted set sits entirely at E3+ — there, an E1 suggestion is
      // unambiguously wrong-low, not an adjacent-tier judgment call.
      if (!g.tiers.includes("E1") && !g.tiers.includes("E2")) {
        cases.push({
          prompt: g.prompt,
          kind: "tier-under",
          suggestion: {
            mode: "ALGORITHM",
            tier: "E1",
            reason: "Simple single-domain task",
            source: "llm",
            confidence: 0.85,
          },
          expectedMode: "ALGORITHM",
          expectedTiers: g.tiers,
          note: g.note || "",
        });
      }
      // None: pure self-selection — no classification block (the W2.2
      // end-state). Graded against the golden label including tier.
      cases.push({
        prompt: g.prompt,
        kind: "none",
        suggestion: null,
        expectedMode: "ALGORITHM",
        expectedTiers: g.tiers,
        note: g.note || "",
      });
    } else if (g.mode === "NATIVE") {
      cases.push({
        prompt: g.prompt,
        kind: "over",
        suggestion: {
          mode: "ALGORITHM",
          tier: "E4",
          reason: "Complex multi-step work",
          source: "llm",
          confidence: 0.85,
        },
        expectedMode: "NATIVE",
        expectedTiers: null,
        note: g.note || "",
      });
      cases.push({
        prompt: g.prompt,
        kind: "none",
        suggestion: null,
        expectedMode: "NATIVE",
        expectedTiers: null,
        note: g.note || "",
      });
    }
    // MINIMAL cases are skipped: bare acknowledgments/ratings depend on
    // conversation context the eval can't provide, so a wrong answer there
    // would measure missing context, not escalation judgment.
  }
  return cases;
}

/**
 * Compose the executor-side prompt for one case. The classification block MUST
 * be the rendered output of the production formatClassificationContext — the
 * eval exists to measure the effect of that exact prose, so the caller renders
 * it and passes the string in (keeps this module pure). For kind 'none' the
 * caller passes nothing and the block is omitted entirely — pure
 * self-selection, the W2.2 end-state.
 *
 * The mode rules mirror the condensed "You Decide" block pai-hooks.js injects.
 *
 * @param {EscalationCase} c
 * @param {string} [renderedClassificationContext]
 * @returns {string}
 */
export function buildExecutorPrompt(c, renderedClassificationContext) {
  const classificationBlock = renderedClassificationContext
    ? [renderedClassificationContext, ""]
    : [];
  return [
    "You are the executor model in the PAI harness. Decide the response mode for the user request below.",
    "",
    "Mode rules:",
    "- MINIMAL — greetings, ratings, single-token acknowledgments.",
    "- NATIVE — single fact lookup OR single-line edit on a named file OR one command run, AND no new artifact created, AND no multi-step plan.",
    "- ALGORITHM — everything else: multi-step, investigative, ambiguous, design, refactor, anything touching multiple files. Tiers: E1 trivial, E2 single-domain, E3 multi-file substantial, E4 cross-cutting/architecture, E5 comprehensive.",
    "",
    ...classificationBlock,
    "User request:",
    '"""',
    c.prompt,
    '"""',
    "",
    "Reply with exactly one line and nothing else:",
    "DECISION: MODE=<MINIMAL|NATIVE|ALGORITHM> TIER=<E1-E5, only when MODE=ALGORITHM>",
  ].join("\n");
}

/**
 * Parse the executor's decision line. Tolerates surrounding chatter by taking
 * the LAST DECISION line; returns null when no parseable decision exists
 * (scored as an error, not silently dropped).
 *
 * @param {string} text
 * @returns {{mode: string, tier: string|null}|null}
 */
export function parseDecision(text) {
  if (typeof text !== "string") return null;
  const lines = text.split("\n").filter((l) => /DECISION\s*:/i.test(l));
  const line = lines[lines.length - 1];
  if (!line) return null;
  const mode = line.match(/MODE\s*=\s*(MINIMAL|NATIVE|ALGORITHM)/i);
  if (!mode) return null;
  const tier = line.match(/TIER\s*=\s*(E[1-5])/i);
  return {
    mode: mode[1].toUpperCase(),
    tier: tier ? tier[1].toUpperCase() : null,
  };
}

// Initial anchors, to be recalibrated after the first real measurement — the
// asymmetry is deliberate: under-correction failures are the incident class
// (silent quality loss), over-correction failures only waste ceremony.
// tier-under is guarded as hard as under (same incident class, one layer
// deeper). none is the W2.2 gate: self-selection accuracy without any
// classifier block — do not remove the classifier while it warns.
export const DEFAULT_ESCALATION_THRESHOLDS = {
  underWarn: 0.85,
  underAlert: 0.6,
  tierUnderWarn: 0.85,
  tierUnderAlert: 0.6,
  overWarn: 0.6,
  controlWarn: 0.7,
  noneWarn: 0.8,
};

/**
 * Score executor decisions against the escalation cases. Pure.
 *
 * @param {EscalationCase[]} cases
 * @param {Array<{mode: string, tier: string|null}|null>} results  Parallel to `cases`.
 * @param {object} [thresholds]
 * @returns {{
 *   total: number,
 *   byKind: Record<string, {total: number, correct: number, rate: number|null}>,
 *   failures: Array<{prompt: string, kind: string, expected: string, got: string}>,
 *   status: 'ok'|'warn'|'alert',
 * }}
 */
export function scoreEscalation(cases, results, thresholds = {}) {
  const t = { ...DEFAULT_ESCALATION_THRESHOLDS, ...thresholds };
  const byKind = {
    under: { total: 0, correct: 0, rate: null },
    "tier-under": { total: 0, correct: 0, rate: null },
    over: { total: 0, correct: 0, rate: null },
    control: { total: 0, correct: 0, rate: null },
    none: { total: 0, correct: 0, rate: null },
  };
  const failures = [];

  cases.forEach((c, i) => {
    const bucket = byKind[c.kind];
    bucket.total++;
    const r = results[i];
    if (!r || typeof r.mode !== "string") {
      failures.push({ prompt: c.prompt, kind: c.kind, expected: c.expectedMode, got: "(no decision)" });
      return;
    }
    let ok = r.mode === c.expectedMode;
    // Whenever an accepted tier set exists (control, tier-under, ALGORITHM
    // none), the decision must also land inside it.
    if (ok && Array.isArray(c.expectedTiers) && c.expectedTiers.length) {
      ok = c.expectedTiers.includes(r.tier);
    }
    if (ok) {
      bucket.correct++;
    } else {
      failures.push({
        prompt: c.prompt,
        kind: c.kind,
        expected: c.expectedTiers ? `${c.expectedMode} ${c.expectedTiers.join("|")}` : c.expectedMode,
        got: `${r.mode}${r.tier ? ` ${r.tier}` : ""}`,
      });
    }
  });

  for (const k of Object.keys(byKind)) {
    const b = byKind[k];
    b.rate = b.total ? b.correct / b.total : null;
  }

  let status = "ok";
  const bump = (level) => {
    if (level === "alert") status = "alert";
    else if (level === "warn" && status !== "alert") status = "warn";
  };
  if (byKind.under.rate !== null) {
    if (byKind.under.rate < t.underAlert) bump("alert");
    else if (byKind.under.rate < t.underWarn) bump("warn");
  }
  if (byKind["tier-under"].rate !== null) {
    if (byKind["tier-under"].rate < t.tierUnderAlert) bump("alert");
    else if (byKind["tier-under"].rate < t.tierUnderWarn) bump("warn");
  }
  if (byKind.over.rate !== null && byKind.over.rate < t.overWarn) bump("warn");
  if (byKind.control.rate !== null && byKind.control.rate < t.controlWarn) bump("warn");
  if (byKind.none.rate !== null && byKind.none.rate < t.noneWarn) bump("warn");

  return { total: cases.length, byKind, failures, status };
}
