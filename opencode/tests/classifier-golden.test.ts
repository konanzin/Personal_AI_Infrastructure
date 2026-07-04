/**
 * Golden-set shape + scorer unit tests for the O3 correctness eval.
 *
 * The LLM run itself costs tokens and lives in bin/eval-classifier-golden.js
 * (on-demand). What CAN run free on every suite pass runs here:
 *   1. the golden set stays well-formed (a malformed case would silently skew
 *      the accuracy numbers),
 *   2. the scorer's math and thresholds are pinned,
 *   3. an informational baseline: the offline heuristic path scored against the
 *      same set, printed (not asserted) so heuristic drift is visible at a glance.
 */
import { describe, test, expect } from "bun:test";
import {
  GOLDEN_SET,
  scoreGolden,
  DEFAULT_GOLDEN_THRESHOLDS,
} from "../plugins/lib/classifier-golden.lib.js";
import { classifyPrompt, normalizeClassification } from "../plugins/lib/mode-classifier.lib.js";

const VALID_MODES = ["MINIMAL", "NATIVE", "ALGORITHM"];
const VALID_TIERS = ["E1", "E2", "E3", "E4", "E5"];

describe("GOLDEN_SET shape", () => {
  test("has enough cases to mean anything", () => {
    expect(GOLDEN_SET.length).toBeGreaterThanOrEqual(20);
  });

  test("every case is well-formed", () => {
    for (const c of GOLDEN_SET) {
      expect(typeof c.prompt).toBe("string");
      expect(c.prompt.length).toBeGreaterThan(0);
      expect(VALID_MODES).toContain(c.mode);
      if (c.mode === "ALGORITHM") {
        expect(Array.isArray(c.tiers)).toBe(true);
        expect(c.tiers!.length).toBeGreaterThan(0);
        for (const t of c.tiers!) expect(VALID_TIERS).toContain(t);
      } else {
        // tiers on a non-ALGORITHM case would silently never be graded.
        expect(c.tiers).toBeUndefined();
      }
    }
  });

  test("prompts are unique", () => {
    const prompts = GOLDEN_SET.map((c) => c.prompt);
    expect(new Set(prompts).size).toBe(prompts.length);
  });

  test("covers all three modes", () => {
    const modes = new Set(GOLDEN_SET.map((c) => c.mode));
    for (const m of VALID_MODES) expect(modes.has(m)).toBe(true);
  });
});

describe("scoreGolden", () => {
  const CASES = [
    { prompt: "a", mode: "MINIMAL" },
    { prompt: "b", mode: "NATIVE" },
    { prompt: "c", mode: "ALGORITHM", tiers: ["E2", "E3"] },
    { prompt: "d", mode: "ALGORITHM", tiers: ["E4", "E5"] },
  ];

  test("perfect run scores ok with full accuracy", () => {
    const r = scoreGolden(CASES, [
      { mode: "MINIMAL", tier: null, source: "llm" },
      { mode: "NATIVE", tier: null, source: "llm" },
      { mode: "ALGORITHM", tier: "E3", source: "llm" },
      { mode: "ALGORITHM", tier: "E4", source: "llm" },
    ]);
    expect(r.status).toBe("ok");
    expect(r.modeAccuracy).toBe(1);
    expect(r.tierAccuracy).toBe(1);
    expect(r.failures).toHaveLength(0);
    expect(r.bySource.llm).toBe(4);
  });

  test("mode misses are primary: accuracy below alert threshold → alert", () => {
    const everythingE3 = CASES.map(() => ({ mode: "ALGORITHM", tier: "E3", source: "llm" }));
    const r = scoreGolden(CASES, everythingE3);
    // 2/4 modes correct (the two ALGORITHM cases) — the exact "everything is
    // ALGORITHM-E3" failure shape the health monitor cannot see.
    expect(r.modeAccuracy).toBe(0.5);
    expect(r.status).toBe("alert");
    expect(r.failures.filter((f) => f.kind === "mode")).toHaveLength(2);
  });

  test("tier is graded as accepted-set membership, only when mode matched", () => {
    const r = scoreGolden(CASES, [
      { mode: "MINIMAL", tier: null },
      { mode: "NATIVE", tier: null },
      { mode: "ALGORITHM", tier: "E5" }, // outside ["E2","E3"] → tier failure
      { mode: "NATIVE", tier: null }, // mode miss → NOT tier-eligible
    ]);
    expect(r.tierEligible).toBe(1);
    expect(r.tierCorrect).toBe(0);
    expect(r.failures.filter((f) => f.kind === "tier")).toHaveLength(1);
    // 3/4 mode (>= 0.65 alert floor, < 0.85 warn floor) → warn regardless of tier
    expect(r.status).toBe("warn");
  });

  test("null results are counted as errors, not skipped", () => {
    const r = scoreGolden(CASES, [null, null, null, null]);
    expect(r.modeAccuracy).toBe(0);
    expect(r.status).toBe("alert");
    expect(r.failures.every((f) => f.kind === "error")).toBe(true);
  });

  test("tier-only weakness degrades ok → warn", () => {
    const r = scoreGolden(
      [
        { prompt: "c", mode: "ALGORITHM", tiers: ["E2"] },
        { prompt: "d", mode: "ALGORITHM", tiers: ["E2"] },
      ],
      [
        { mode: "ALGORITHM", tier: "E5" },
        { mode: "ALGORITHM", tier: "E5" },
      ],
    );
    expect(r.modeAccuracy).toBe(1);
    expect(r.tierAccuracy).toBe(0);
    expect(r.status).toBe("warn");
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Informational baseline — heuristic path vs the golden set, free, every run.
// NOT asserted: the heuristic is the fallback, not the production path; this
// prints its score so a heuristic regression is visible without gating CI on it.
// The production-path score comes from `bun bin/eval-classifier-golden.js`.
// ─────────────────────────────────────────────────────────────────────────────
describe("Heuristic baseline (informational)", () => {
  test("print offline heuristic score against the golden set", () => {
    const results = GOLDEN_SET.map((c) => normalizeClassification(classifyPrompt(c.prompt)));
    const r = scoreGolden(GOLDEN_SET, results, DEFAULT_GOLDEN_THRESHOLDS);
    const pct = (x: number | null) => (x == null ? "n/a" : `${(x * 100).toFixed(0)}%`);
    console.log(
      `\n  HEURISTIC BASELINE: mode ${r.modeCorrect}/${r.total} (${pct(r.modeAccuracy)})` +
        ` · tier ${r.tierCorrect}/${r.tierEligible} (${pct(r.tierAccuracy)})` +
        ` · would be: ${r.status.toUpperCase()}`,
    );
    for (const f of r.failures.slice(0, 8)) {
      console.log(`    - [${f.kind}] "${f.prompt}" → expected ${f.expected}, got ${f.got}`);
    }
    expect(r.total).toBe(GOLDEN_SET.length);
  });
});
