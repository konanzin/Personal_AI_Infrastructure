/**
 * Classifier health analyzer — the O5 monitor that catches the production LLM path
 * silently degrading to heuristic/fail-safe (the b6ec6a8f failure class for the
 * classifier). See plugins/lib/classifier-health.lib.js.
 */
import { describe, test, expect } from "bun:test";
import {
  analyzeClassifierHealth,
  DEFAULT_THRESHOLDS,
} from "../plugins/lib/classifier-health.lib.js";

const mk = (source: string, n: number) =>
  Array.from({ length: n }, () => ({ event: "mode_classification", source }));

describe("analyzeClassifierHealth", () => {
  test("healthy LLM stream → ok", () => {
    const r = analyzeClassifierHealth(mk("llm", 40), { expectLLM: true });
    expect(r.status).toBe("ok");
    expect(r.llmRate).toBe(1);
    expect(r.degradedRate).toBe(0);
  });

  test("some fail-safe → warn on its own tighter threshold", () => {
    // 3/40 = 7.5% fail-safe → above failSafeWarn (5%), below degradedWarn (20%).
    const r = analyzeClassifierHealth([...mk("llm", 37), ...mk("fail-safe", 3)], {
      expectLLM: true,
    });
    expect(r.status).toBe("warn");
    expect(r.reasons.join(" ")).toContain("fail-safe rate");
  });

  test("LLM path dead — everything degraded to heuristic → alert", () => {
    const r = analyzeClassifierHealth(mk("heuristic", 40), { expectLLM: true });
    expect(r.status).toBe("alert");
    expect(r.degradedRate).toBe(1);
    expect(r.reasons.join(" ")).toContain("LLM path likely dead");
  });

  test("heuristic is HEALTHY when LLM is not expected", () => {
    const r = analyzeClassifierHealth(mk("heuristic", 40), { expectLLM: false });
    expect(r.status).toBe("ok");
    expect(r.degradedRate).toBe(0); // only fail-safe counts as degraded here
  });

  test("fail-safe still alerts even when LLM is not expected", () => {
    const r = analyzeClassifierHealth(
      [...mk("heuristic", 20), ...mk("fail-safe", 20)],
      { expectLLM: false },
    );
    expect(r.status).toBe("alert");
    expect(r.failSafeRate).toBe(0.5);
  });

  test("deliberate bypasses (override, command) are excluded from the denominator", () => {
    // 30 healthy llm + 20 meta-command bypasses. If bypasses counted, llmRate would
    // drop to 60% and dilute a real outage. They must be excluded → llmRate stays 100%.
    const r = analyzeClassifierHealth(
      [...mk("llm", 30), ...mk("command", 20)],
      { expectLLM: true },
    );
    expect(r.considered).toBe(30);
    expect(r.total).toBe(50);
    expect(r.llmRate).toBe(1);
    expect(r.status).toBe("ok");
  });

  test("per-row use_llm overrides current config (no false alert after a config change)", () => {
    // Config now expects LLM, but these 40 heuristic rows were emitted when useLLM
    // was false (use_llm:false recorded per row). They must NOT count as degraded.
    const rows = Array.from({ length: 40 }, () => ({
      event: "mode_classification",
      source: "heuristic",
      use_llm: false,
    }));
    const r = analyzeClassifierHealth(rows, { expectLLM: true });
    expect(r.status).toBe("ok");
    expect(r.degradedRate).toBe(0);
  });

  test("per-row use_llm:true DOES mark heuristic rows degraded even if caller default is false", () => {
    const rows = Array.from({ length: 40 }, () => ({
      event: "mode_classification",
      source: "heuristic",
      use_llm: true,
    }));
    const r = analyzeClassifierHealth(rows, { expectLLM: false });
    expect(r.status).toBe("alert");
    expect(r.degradedRate).toBe(1);
  });

  test("below minSamples → insufficient, never a false alarm", () => {
    const r = analyzeClassifierHealth(mk("fail-safe", 5), { expectLLM: true });
    expect(r.status).toBe("insufficient");
  });

  test("window keeps only the most recent N (recovery is visible)", () => {
    // Old failures then a healthy recent run: windowing to the tail shows ok.
    const stream = [...mk("fail-safe", 100), ...mk("llm", 40)];
    const r = analyzeClassifierHealth(stream, { expectLLM: true, window: 40 });
    expect(r.considered).toBe(40);
    expect(r.status).toBe("ok");
  });

  test("ignores non-classification rows and malformed sources", () => {
    const stream = [
      ...mk("llm", 30),
      { event: "security", source: "whatever" },
      { event: "mode_classification" }, // no source
      null,
    ];
    const r = analyzeClassifierHealth(stream as any, { expectLLM: true });
    expect(r.considered).toBe(30);
    expect(r.status).toBe("ok");
  });

  test("thresholds are configurable", () => {
    const strict = { ...DEFAULT_THRESHOLDS, failSafeWarn: 0.01, failSafeAlert: 0.02 };
    const r = analyzeClassifierHealth([...mk("llm", 39), ...mk("fail-safe", 1)], {
      expectLLM: true,
      thresholds: strict,
    });
    expect(r.status).toBe("alert"); // 2.5% fail-safe trips the strict alert
  });
});
