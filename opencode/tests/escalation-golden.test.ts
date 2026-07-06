/**
 * Unit tests for the escalation golden machinery (pure parts only — the LLM
 * runner bin/eval-escalation-golden.js is on-demand and costs calls).
 *
 * Guards the executor-side eval W1.2 was missing (audit 2026-07-05): the
 * builder must derive the under/over/control probes from the classifier
 * golden set, the parser must extract decisions robustly, and the scorer's
 * asymmetric thresholds (under-escalation is the incident class) must hold.
 */
import { describe, test, expect } from "bun:test";
import {
  buildEscalationCases,
  buildExecutorPrompt,
  parseDecision,
  scoreEscalation,
  DEFAULT_ESCALATION_THRESHOLDS,
} from "../plugins/lib/escalation-golden.lib.js";
import { GOLDEN_SET } from "../plugins/lib/classifier-golden.lib.js";
import { formatClassificationContext } from "../plugins/lib/mode-classifier.lib.js";

const MINI_SET = [
  { prompt: "fix the login bug", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "vague fix" },
  { prompt: "design a migration plan from SQLite to Postgres", mode: "ALGORITHM", tiers: ["E3", "E4", "E5"], note: "architecture — tier floor E3" },
  { prompt: "rename config.js to config.mjs", mode: "NATIVE", note: "mechanical edit" },
  { prompt: "ok", mode: "MINIMAL", note: "ack" },
];

describe("buildEscalationCases", () => {
  test("ALGORITHM cases yield an under probe (suggested NATIVE) and a control", () => {
    const cases = buildEscalationCases(MINI_SET as any);
    const under = cases.find((c) => c.kind === "under");
    const control = cases.find((c) => c.kind === "control");
    expect(under?.prompt).toBe("fix the login bug");
    expect(under?.suggestion.mode).toBe("NATIVE");
    expect(under?.expectedMode).toBe("ALGORITHM");
    expect(control?.suggestion.mode).toBe("ALGORITHM");
    expect(control?.expectedTiers).toEqual(["E2", "E3", "E4"]);
    // control suggests a tier from the accepted set (mid pick)
    expect(control?.expectedTiers).toContain(control?.suggestion.tier);
  });

  test("NATIVE cases yield an over probe (suggested ALGORITHM E4)", () => {
    const cases = buildEscalationCases(MINI_SET as any);
    const over = cases.find((c) => c.kind === "over");
    expect(over?.prompt).toBe("rename config.js to config.mjs");
    expect(over?.suggestion).toMatchObject({ mode: "ALGORITHM", tier: "E4" });
    expect(over?.expectedMode).toBe("NATIVE");
  });

  test("MINIMAL cases are excluded (context-dependent, would measure noise)", () => {
    const cases = buildEscalationCases(MINI_SET as any);
    expect(cases.some((c) => c.prompt === "ok")).toBe(false);
  });

  test("tier-under probes only where E1 is unambiguously wrong-low (accepted set ≥E3)", () => {
    const cases = buildEscalationCases(MINI_SET as any);
    const tierUnder = cases.filter((c) => c.kind === "tier-under");
    // "fix the login bug" accepts E2 — an E1 suggestion there is an
    // adjacent-tier judgment call, not a wrong-low probe. Only the E3+ case
    // qualifies.
    expect(tierUnder.length).toBe(1);
    expect(tierUnder[0].prompt).toContain("migration plan");
    expect(tierUnder[0].suggestion).toMatchObject({ mode: "ALGORITHM", tier: "E1" });
    expect(tierUnder[0].expectedTiers).toEqual(["E3", "E4", "E5"]);
  });

  test("every non-MINIMAL prompt gets a none probe (suggestion: null)", () => {
    const cases = buildEscalationCases(MINI_SET as any);
    const none = cases.filter((c) => c.kind === "none");
    expect(none.length).toBe(3); // 2 ALGORITHM + 1 NATIVE
    expect(none.every((c) => c.suggestion === null)).toBe(true);
    const alg = none.find((c) => c.prompt === "fix the login bug")!;
    expect(alg.expectedTiers).toEqual(["E2", "E3", "E4"]);
  });

  test("real golden set derives a usable population of every kind", () => {
    const cases = buildEscalationCases(GOLDEN_SET);
    const count = (k: string) => cases.filter((c) => c.kind === k).length;
    expect(count("under")).toBeGreaterThanOrEqual(10);
    expect(count("over")).toBeGreaterThanOrEqual(10);
    expect(count("control")).toBe(count("under"));
    expect(count("tier-under")).toBeGreaterThanOrEqual(3);
    expect(count("none")).toBe(count("under") + count("over"));
  });
});

describe("buildExecutorPrompt", () => {
  test("embeds the production-rendered suggestion prose verbatim", () => {
    const cases = buildEscalationCases(MINI_SET as any);
    const under = cases.find((c) => c.kind === "under")!;
    const ctx = formatClassificationContext(under.suggestion as any);
    const prompt = buildExecutorPrompt(under, ctx);
    // The eval measures the REAL injected prose — the W1.2 suggestion stance
    // must be present, or the eval is probing something production doesn't say.
    expect(ctx).toContain("suggestion");
    expect(prompt).toContain(ctx);
    expect(prompt).toContain(under.prompt);
    expect(prompt).toContain("DECISION:");
  });

  test("none probes omit the classification block entirely (pure self-selection)", () => {
    const cases = buildEscalationCases(MINI_SET as any);
    const none = cases.find((c) => c.kind === "none")!;
    const prompt = buildExecutorPrompt(none, undefined);
    expect(prompt).not.toContain("suggestion");
    expect(prompt).not.toContain("classifier");
    expect(prompt).toContain(none.prompt);
    expect(prompt).toContain("DECISION:");
  });
});

describe("parseDecision", () => {
  test("parses the canonical line", () => {
    expect(parseDecision("DECISION: MODE=ALGORITHM TIER=E3")).toEqual({ mode: "ALGORITHM", tier: "E3" });
  });
  test("takes the last DECISION line and tolerates chatter", () => {
    const out = "thinking...\nDECISION: MODE=NATIVE\nwait, actually:\nDECISION: MODE=ALGORITHM TIER=E4\n";
    expect(parseDecision(out)).toEqual({ mode: "ALGORITHM", tier: "E4" });
  });
  test("mode without tier parses; garbage returns null", () => {
    expect(parseDecision("DECISION: MODE=NATIVE")).toEqual({ mode: "NATIVE", tier: null });
    expect(parseDecision("no decision here")).toBeNull();
    expect(parseDecision("")).toBeNull();
  });
});

describe("scoreEscalation", () => {
  const cases = buildEscalationCases(MINI_SET as any); // under, control, over

  test("perfect executor scores ok on every kind", () => {
    const results = cases.map((c) =>
      c.kind === "control"
        ? { mode: c.expectedMode, tier: c.suggestion.tier }
        : { mode: c.expectedMode, tier: c.expectedTiers?.[0] ?? (c.expectedMode === "ALGORITHM" ? "E3" : null) },
    );
    const r = scoreEscalation(cases, results as any);
    expect(r.status).toBe("ok");
    expect(r.byKind.under.rate).toBe(1);
    expect(r.byKind["tier-under"].rate).toBe(1);
    expect(r.byKind.over.rate).toBe(1);
    expect(r.byKind.control.rate).toBe(1);
    expect(r.byKind.none.rate).toBe(1);
  });

  test("executor that swallows wrong-LOW suggestions alerts (the incident class)", () => {
    // Adopts every suggestion verbatim (self-selects correctly when there is
    // none): under probes stay NATIVE → under rate 0; tier-under stays E1.
    const results = cases.map((c) =>
      c.suggestion
        ? { mode: c.suggestion.mode, tier: c.suggestion.tier }
        : { mode: c.expectedMode, tier: c.expectedTiers?.[0] ?? null },
    );
    const r = scoreEscalation(cases, results as any);
    expect(r.byKind.under.rate).toBe(0);
    expect(r.byKind["tier-under"].rate).toBe(0); // E1 outside the E3+ accepted set
    expect(r.status).toBe("alert");
    expect(r.failures.some((f) => f.kind === "under")).toBe(true);
    expect(r.failures.some((f) => f.kind === "tier-under")).toBe(true);
  });

  test("weak self-selection warns — the W2.2 gate", () => {
    // Suggestions handled perfectly, but the none bucket (no classifier
    // block) picks NATIVE for ALGORITHM work: none rate collapses → warn.
    const results = cases.map((c) => {
      if (c.kind === "none") return { mode: "NATIVE", tier: null };
      if (c.kind === "control") return { mode: c.expectedMode, tier: c.suggestion.tier };
      return { mode: c.expectedMode, tier: c.expectedTiers?.[0] ?? (c.expectedMode === "ALGORITHM" ? "E3" : null) };
    });
    const r = scoreEscalation(cases, results as any);
    expect(r.byKind.none.rate).toBeLessThan(1);
    expect(r.status).toBe("warn");
  });

  test("control adoption requires the tier to land in the accepted set", () => {
    const results = cases.map((c) =>
      c.kind === "control" ? { mode: "ALGORITHM", tier: "E5" } : { mode: c.expectedMode, tier: null },
    );
    const r = scoreEscalation(cases, results as any);
    // E5 lands outside E2|E3|E4 (login bug) but inside E3|E4|E5 (migration):
    // exactly one of the two controls fails, proving membership is enforced.
    expect(r.byKind.control.correct).toBe(1);
    expect(r.failures.some((f) => f.kind === "control" && f.prompt === "fix the login bug")).toBe(true);
  });

  test("missing decisions are failures, not silent drops", () => {
    const results = cases.map(() => null);
    const r = scoreEscalation(cases, results as any);
    expect(r.failures.length).toBe(cases.length);
    expect(r.byKind.under.rate).toBe(0);
  });

  test("thresholds are asymmetric by design: under is guarded harder than over", () => {
    expect(DEFAULT_ESCALATION_THRESHOLDS.underWarn).toBeGreaterThan(DEFAULT_ESCALATION_THRESHOLDS.overWarn);
    expect(DEFAULT_ESCALATION_THRESHOLDS.underAlert).toBeDefined();
  });
});
