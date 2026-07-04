/**
 * Classifier golden set + scorer — closes the O3 gap the health monitor can't.
 *
 * monitor-classifier-health.js proves the LLM path is ALIVE (share of events on
 * the intended source). Nothing proved it is RIGHT: a model swap or prompt-format
 * drift that classifies every prompt as ALGORITHM-E3 would look perfectly healthy.
 * This golden set measures classification CORRECTNESS on the path production
 * actually runs (bin/eval-classifier-golden.js drives classifyPromptWithLLM, the
 * same function pai-hooks.js calls).
 *
 * Label policy — labels must be DEFENSIBLE, not aspirational:
 *   • Only clear-cut prompts. A case two reasonable people would label differently
 *     measures noise, not drift, and does not belong here.
 *   • mode is graded strictly; tier is graded as membership in an accepted set
 *     (`tiers`), because adjacent effort tiers are a judgment call while the
 *     mode boundary (MINIMAL / NATIVE / ALGORITHM) is the routing decision that
 *     changes behavior.
 *
 * Pure and dependency-free (no I/O, no LLM calls) so the scorer is unit-testable
 * and the set is importable from both the bin runner and the test suite.
 */

/**
 * @typedef {object} GoldenCase
 * @property {string} prompt
 * @property {'MINIMAL'|'NATIVE'|'ALGORITHM'} mode   Expected mode (strict).
 * @property {string[]} [tiers]  Accepted tiers when mode is ALGORITHM.
 * @property {string} note
 */

/** @type {GoldenCase[]} */
export const GOLDEN_SET = [
  // ── MINIMAL — pure acknowledgments and ratings ──
  { prompt: "ok", mode: "MINIMAL", note: "bare acknowledgment" },
  { prompt: "thanks!", mode: "MINIMAL", note: "bare thanks" },
  { prompt: "8", mode: "MINIMAL", note: "bare rating number" },
  { prompt: "perfect, that works", mode: "MINIMAL", note: "confirmation, no new work" },

  // ── NATIVE — simple, single-step, low-effort tasks ──
  { prompt: "what does the acronym YAML stand for?", mode: "NATIVE", note: "one-fact question" },
  { prompt: "what time is it in Tokyo right now?", mode: "NATIVE", note: "trivial lookup" },
  { prompt: "rename config.js to config.mjs", mode: "NATIVE", note: "single mechanical edit" },
  { prompt: "add a console.log at the top of main.ts printing 'boot'", mode: "NATIVE", note: "one-line change, fully specified" },
  { prompt: "show me the git status of this repo", mode: "NATIVE", note: "single command" },
  { prompt: "fix the typo 'recieve' in the README header", mode: "NATIVE", note: "boundary: contains 'fix' but is trivial" },
  { prompt: "bump the version in package.json to 2.1.0", mode: "NATIVE", note: "boundary: edit fully specified" },

  // ── ALGORITHM — multi-step, investigative, or design work ──
  { prompt: "debug why the login flow returns 401 right after a token refresh", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "root-cause debugging" },
  { prompt: "investigate the memory leak in the websocket server and fix it", mode: "ALGORITHM", tiers: ["E3", "E4", "E5"], note: "investigate + fix" },
  { prompt: "refactor the payment module to support multiple currencies, with tests", mode: "ALGORITHM", tiers: ["E3", "E4", "E5"], note: "cross-cutting refactor" },
  { prompt: "design a migration plan from SQLite to Postgres for the analytics service", mode: "ALGORITHM", tiers: ["E3", "E4", "E5"], note: "architecture/planning" },
  { prompt: "build a CLI tool that syncs my calendar into a markdown file every morning", mode: "ALGORITHM", tiers: ["E3", "E4", "E5"], note: "greenfield build" },
  { prompt: "our CI pipeline is flaky — find the root cause", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "investigation" },
  { prompt: "plan the plugin architecture for the editor, considering sandboxing and versioning", mode: "ALGORITHM", tiers: ["E3", "E4", "E5"], note: "design with constraints" },
  { prompt: "audit this codebase for security vulnerabilities and rank them", mode: "ALGORITHM", tiers: ["E3", "E4", "E5"], note: "broad audit" },
  { prompt: "compare React and Svelte for our dashboard rewrite and recommend one with reasons", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "comparative analysis" },
  { prompt: "migrate all fetch() calls in src/ to the new apiClient wrapper and update the tests", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "repo-wide migration" },
  { prompt: "why does the app crash on startup only when offline? reproduce and fix", mode: "ALGORITHM", tiers: ["E3", "E4", "E5"], note: "repro + fix" },
];

export const DEFAULT_GOLDEN_THRESHOLDS = {
  // Share of cases whose MODE matched. The primary routing signal.
  modeWarn: 0.85,
  modeAlert: 0.65,
  // Among ALGORITHM cases where the mode matched, share whose tier fell in the
  // accepted set. Secondary — tier misses waste effort, mode misses change behavior.
  tierWarn: 0.6,
};

/**
 * Score classification results against the golden set. Pure.
 *
 * @param {Array<{prompt: string, mode: string, tiers?: string[], note?: string}>} cases
 * @param {Array<{mode: string, tier: string|null, source?: string}|null>} results
 *   Parallel array to `cases`; null = the run failed to produce a classification.
 * @param {object} [thresholds]
 * @returns {{
 *   total: number, modeCorrect: number, modeAccuracy: number,
 *   tierEligible: number, tierCorrect: number, tierAccuracy: number|null,
 *   bySource: Record<string, number>,
 *   failures: Array<{prompt: string, expected: string, got: string, kind: 'mode'|'tier'|'error'}>,
 *   status: 'ok'|'warn'|'alert',
 * }}
 */
export function scoreGolden(cases, results, thresholds = {}) {
  const t = { ...DEFAULT_GOLDEN_THRESHOLDS, ...thresholds };
  const failures = [];
  const bySource = {};
  let modeCorrect = 0;
  let tierEligible = 0;
  let tierCorrect = 0;

  cases.forEach((c, i) => {
    const r = results[i];
    if (!r || typeof r.mode !== "string") {
      failures.push({ prompt: c.prompt, expected: c.mode, got: "(no result)", kind: "error" });
      return;
    }
    if (r.source) bySource[r.source] = (bySource[r.source] || 0) + 1;

    if (r.mode !== c.mode) {
      failures.push({
        prompt: c.prompt,
        expected: c.mode,
        got: `${r.mode}${r.tier ? ` ${r.tier}` : ""}`,
        kind: "mode",
      });
      return;
    }
    modeCorrect++;

    if (c.mode === "ALGORITHM" && Array.isArray(c.tiers) && c.tiers.length) {
      tierEligible++;
      if (c.tiers.includes(r.tier)) {
        tierCorrect++;
      } else {
        failures.push({
          prompt: c.prompt,
          expected: `ALGORITHM ${c.tiers.join("|")}`,
          got: `ALGORITHM ${r.tier}`,
          kind: "tier",
        });
      }
    }
  });

  const total = cases.length;
  const modeAccuracy = total ? modeCorrect / total : 0;
  const tierAccuracy = tierEligible ? tierCorrect / tierEligible : null;

  let status = "ok";
  if (modeAccuracy < t.modeAlert) status = "alert";
  else if (modeAccuracy < t.modeWarn) status = "warn";
  else if (tierAccuracy !== null && tierAccuracy < t.tierWarn) status = "warn";

  return { total, modeCorrect, modeAccuracy, tierEligible, tierCorrect, tierAccuracy, bySource, failures, status };
}
