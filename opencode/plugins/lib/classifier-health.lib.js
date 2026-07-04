/**
 * Classifier health analyzer — closes the O5 loop for mode classification.
 *
 * The production classifier defaults to the LLM path (useLLM=true). If that path
 * silently breaks — a CLI-output format drift in `opencode run --pure`, the provider
 * going away, a timeout regression — every prompt quietly degrades to the heuristic
 * (or the ALGORITHM-E3 fail-safe) and NOTHING tells you. That is the exact shape of
 * the b6ec6a8f bug: a tested escape hatch masking a dead production path.
 *
 * mode-classifier.jsonl already records `source` for every classification. This turns
 * that write-only stream into a signal: it computes the share of classifications that
 * did NOT come from the intended path and returns an ok/warn/alert verdict.
 *
 * Pure and dependency-free so it is unit-testable; the bin/ wrapper feeds it real
 * file + config. No I/O here.
 */

// Sources that represent a deliberate, healthy route — never counted as degradation.
//   llm       → the intended path when useLLM=true
//   override  → a human/env forced the classification
//   command   → PAI meta-command bypass (/status, /voice, ...) — intentional NATIVE
const HEALTHY_LLM = "llm";
const DELIBERATE = new Set(["override", "command"]);

export const DEFAULT_THRESHOLDS = {
  // Share of *automated* classifications that degraded (heuristic-when-LLM-expected,
  // or fail-safe). Heuristic is a soft degrade; fail-safe is a hard failure.
  degradedWarn: 0.2,
  degradedAlert: 0.5,
  // Hard-failure share on its own — a small but nonzero fail-safe rate is worse than
  // a large heuristic rate, so it gets its own tighter thresholds.
  failSafeWarn: 0.05,
  failSafeAlert: 0.2,
  // Below this many samples we don't have the statistics to judge; status = 'insufficient'.
  minSamples: 10,
};

/**
 * @param {Array<object>} entries  Parsed mode-classifier.jsonl rows (any order).
 * @param {object} opts
 * @param {boolean} opts.expectLLM  Whether the current config intends the LLM path.
 * @param {number}  [opts.window]   Consider only the most recent N classifications.
 * @param {object}  [opts.thresholds]
 * @returns {{
 *   status: 'ok'|'warn'|'alert'|'insufficient',
 *   total: number, considered: number,
 *   bySource: Record<string, number>,
 *   degradedRate: number, failSafeRate: number, llmRate: number|null,
 *   reasons: string[],
 * }}
 */
export function analyzeClassifierHealth(entries, opts = {}) {
  const { expectLLM = true } = opts;
  const t = { ...DEFAULT_THRESHOLDS, ...(opts.thresholds || {}) };

  const rows = (Array.isArray(entries) ? entries : [])
    .filter((e) => e && e.event === "mode_classification" && typeof e.source === "string");

  // Most recent `window` by timestamp when present, else input order (already appended
  // chronologically). Slicing the tail is correct for an append-only JSONL stream.
  const ordered = rows.slice();
  const windowed = opts.window ? ordered.slice(-opts.window) : ordered;

  const bySource = {};
  for (const r of windowed) bySource[r.source] = (bySource[r.source] || 0) + 1;

  const total = windowed.length;
  // Denominator excludes deliberate bypasses — they are not attempts at automated
  // classification, so counting them would dilute a real LLM outage.
  const automated = windowed.filter((r) => !DELIBERATE.has(r.source));
  const considered = automated.length;

  // Intent is resolved PER ROW: prefer the event's own `use_llm` (recorded at emit
  // time) over the caller's current-config default, so a later config change can't
  // retroactively mislabel old rows. Rows predating the field fall back to expectLLM.
  const rowExpectsLLM = (r) => (typeof r.use_llm === "boolean" ? r.use_llm : expectLLM);

  const failSafe = automated.filter((r) => r.source === "fail-safe").length;
  const heuristic = automated.filter((r) => r.source === "heuristic").length;
  // llmRate uses the same per-row intent as `degraded`: only rows where the LLM
  // path was intended belong in its denominator, so a window that mixes
  // useLLM=true/false traffic doesn't understate the healthy share.
  const llmIntended = automated.filter(rowExpectsLLM);
  const llm = llmIntended.filter((r) => r.source === HEALTHY_LLM).length;

  // Degradation depends on intent. If LLM was expected for a row, a heuristic result
  // means the LLM path fell back → degraded. If LLM was NOT expected, heuristic is the
  // intended path and only fail-safe (a genuine exception) counts as degraded.
  const degraded = automated.filter((r) => {
    if (r.source === "fail-safe") return true;
    if (r.source === "heuristic") return rowExpectsLLM(r);
    return false;
  }).length;

  const degradedRate = considered ? degraded / considered : 0;
  const failSafeRate = considered ? failSafe / considered : 0;
  const llmRate = llmIntended.length ? llm / llmIntended.length : null;

  const reasons = [];
  let status = "ok";

  if (considered < t.minSamples) {
    status = "insufficient";
    reasons.push(`only ${considered} automated classifications (need ${t.minSamples} to judge)`);
    return { status, total, considered, bySource, degradedRate, failSafeRate, llmRate, reasons };
  }

  const bump = (level) => {
    if (level === "alert") status = "alert";
    else if (level === "warn" && status !== "alert") status = "warn";
  };

  if (failSafeRate >= t.failSafeAlert) {
    bump("alert");
    reasons.push(`fail-safe rate ${pct(failSafeRate)} ≥ alert ${pct(t.failSafeAlert)} — classifier is throwing exceptions`);
  } else if (failSafeRate >= t.failSafeWarn) {
    bump("warn");
    reasons.push(`fail-safe rate ${pct(failSafeRate)} ≥ warn ${pct(t.failSafeWarn)}`);
  }

  if (degradedRate >= t.degradedAlert) {
    bump("alert");
    reasons.push(
      expectLLM
        ? `degraded rate ${pct(degradedRate)} ≥ alert ${pct(t.degradedAlert)} — LLM path likely dead (falling back to heuristic/fail-safe)`
        : `degraded rate ${pct(degradedRate)} ≥ alert ${pct(t.degradedAlert)}`,
    );
  } else if (degradedRate >= t.degradedWarn) {
    bump("warn");
    reasons.push(`degraded rate ${pct(degradedRate)} ≥ warn ${pct(t.degradedWarn)}`);
  }

  if (status === "ok") {
    reasons.push(
      expectLLM
        ? `healthy — ${pct(llmRate)} classified via LLM, degraded ${pct(degradedRate)}`
        : `healthy — heuristic path intended, fail-safe ${pct(failSafeRate)}`,
    );
  }

  return { status, total, considered, bySource, degradedRate, failSafeRate, llmRate, reasons };
}

function pct(x) {
  return x == null ? "n/a" : `${(x * 100).toFixed(0)}%`;
}
