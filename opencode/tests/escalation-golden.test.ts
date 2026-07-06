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

  test("real golden set derives a usable population of every kind", () => {
    const cases = buildEscalationCases(GOLDEN_SET);
    const count = (k: string) => cases.filter((c) => c.kind === k).length;
    expect(count("under")).toBeGreaterThanOrEqual(10);
    expect(count("over")).toBeGreaterThanOrEqual(10);
    expect(count("control")).toBe(count("under"));
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
        : { mode: c.expectedMode, tier: c.expectedMode === "ALGORITHM" ? "E3" : null },
    );
    const r = scoreEscalation(cases, results as any);
    expect(r.status).toBe("ok");
    expect(r.byKind.under.rate).toBe(1);
    expect(r.byKind.over.rate).toBe(1);
    expect(r.byKind.control.rate).toBe(1);
  });

  test("executor that swallows wrong-LOW suggestions alerts (the incident class)", () => {
    // Adopts every suggestion verbatim: under probes stay NATIVE → under rate 0.
    const results = cases.map((c) => ({ mode: c.suggestion.mode, tier: c.suggestion.tier }));
    const r = scoreEscalation(cases, results as any);
    expect(r.byKind.under.rate).toBe(0);
    expect(r.status).toBe("alert");
    expect(r.failures.some((f) => f.kind === "under")).toBe(true);
  });

  test("control adoption requires the tier to land in the accepted set", () => {
    const results = cases.map((c) =>
      c.kind === "control" ? { mode: "ALGORITHM", tier: "E5" } : { mode: c.expectedMode, tier: null },
    );
    const r = scoreEscalation(cases, results as any);
    expect(r.byKind.control.correct).toBe(0); // E5 outside E2|E3|E4
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
