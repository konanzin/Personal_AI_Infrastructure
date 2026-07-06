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

  test("requireIntentField judges only telemetry-contract-v2 rows (per-row use_llm)", () => {
    // Pre-v2 history: meta-command bypasses coerced to 'fail-safe' before 'command'
    // was a valid source, plus heuristic-era fail-safes. Under the flag they are
    // unjudgeable and must not poison the window (the 2026-07-05 false alarm).
    const legacy = [...mk("fail-safe", 6), ...mk("heuristic", 2), ...mk("llm", 20)]; // no use_llm field
    const v2 = mk("llm", 12).map((r) => ({ ...r, use_llm: true }));

    const withFlag = analyzeClassifierHealth([...legacy, ...v2] as any, {
      expectLLM: true,
      requireIntentField: true,
    });
    expect(withFlag.considered).toBe(12);
    expect(withFlag.status).toBe("ok"); // legacy fail-safes excluded

    const withoutFlag = analyzeClassifierHealth([...legacy, ...v2] as any, { expectLLM: true });
    expect(withoutFlag.status).not.toBe("ok"); // default keeps old behavior
  });

  test("requireIntentField with too few v2 rows reports insufficient, not failure", () => {
    const legacy = mk("fail-safe", 40);
    const v2 = mk("llm", 4).map((r) => ({ ...r, use_llm: true }));
    const r = analyzeClassifierHealth([...legacy, ...v2] as any, {
      expectLLM: true,
      requireIntentField: true,
    });
    expect(r.status).toBe("insufficient");
  });

  test("discarded pre-v2 rows are counted and surfaced, never silently dropped", () => {
    // A v1-only machine with a genuinely dead LLM path (audit finding, 2026-07-05):
    // every row is unjudgeable, so the monitor cannot say "alert" — but it must not
    // read as a clean green either. The discard count and a reason make it visible.
    const v1OnlyBroken = mk("fail-safe", 45).concat(mk("heuristic", 5)); // no use_llm
    const r = analyzeClassifierHealth(v1OnlyBroken as any, {
      expectLLM: true,
      requireIntentField: true,
    });
    expect(r.status).toBe("insufficient");
    expect(r.discarded).toBe(50);
    expect(r.reasons.join(" ")).toContain("50 pre-v2 rows excluded");

    // Judged windows also carry the count (zero when everything is v2).
    const allV2 = mk("llm", 20).map((row) => ({ ...row, use_llm: true }));
    expect(analyzeClassifierHealth(allV2 as any, { expectLLM: true, requireIntentField: true }).discarded).toBe(0);
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
