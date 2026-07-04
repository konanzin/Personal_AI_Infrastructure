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

  // ── Expansion (2026-07-04): cases mined from REAL usage in mode-classifier.jsonl.
  // Real usage is bilingual (PT-BR + EN) and heavy on trivial fully-specified
  // actions — exactly the boundary the first measurement showed failing
  // (trivial edits → ALGORITHM-E1). The set is deliberately NATIVE-heavy because
  // the NATIVE/ALGORITHM boundary is the routing decision under repair; keep that
  // skew in mind when comparing accuracy across set versions.

  // ── NATIVE — trivial fully-specified edits/actions (the failing class) ──
  { prompt: "delete the unused lodash import in src/utils.js", mode: "NATIVE", note: "single mechanical edit" },
  { prompt: "add node_modules/ to the .gitignore", mode: "NATIVE", note: "one-line append, fully specified" },
  { prompt: "change the button label from 'Send' to 'Submit' in Header.tsx", mode: "NATIVE", note: "single string change" },
  { prompt: "add a TODO comment above the parseConfig function saying 'validate schema here'", mode: "NATIVE", note: "single comment insertion" },
  { prompt: "run npm view react version and tell me what it prints", mode: "NATIVE", note: "single command execution (real-history shape)" },
  { prompt: "Use the bash tool to run exactly: npm view react version", mode: "NATIVE", note: "verbatim from real history — was misrouted ALGORITHM-E3" },
  { prompt: "pin the node version to 20 in .nvmrc", mode: "NATIVE", note: "single-file one-liner" },

  // ── NATIVE — PT-BR (real usage is bilingual; original set was 100% EN) ──
  { prompt: "rode o comando echo $PATH", mode: "NATIVE", note: "PT-BR: run one given command (real-history shape)" },
  { prompt: "renomeie o arquivo config.js para config.mjs", mode: "NATIVE", note: "PT-BR twin of the rename case" },
  { prompt: "mostra o git status desse repo", mode: "NATIVE", note: "PT-BR: single command" },
  { prompt: "corrige o typo 'recieve' no título do README", mode: "NATIVE", note: "PT-BR twin of the typo case" },
  { prompt: "manda a notificação de teste de novo", mode: "NATIVE", note: "PT-BR: retry one simple action (real-history shape)" },
  { prompt: "Como eu excluo os modelos kimi daqui?", mode: "NATIVE", note: "PT-BR: short how-do-I question (verbatim from real history)" },
  { prompt: "qual porta o postgres usa por padrão?", mode: "NATIVE", note: "PT-BR: one-fact question" },

  // ── NATIVE — short questions ──
  { prompt: "what's the difference between git fetch and git pull?", mode: "NATIVE", note: "short explanation, no work" },
  { prompt: "what does exit code 137 mean?", mode: "NATIVE", note: "one-fact question" },

  // ── MINIMAL — PT-BR + EN ──
  { prompt: "boa tarde", mode: "MINIMAL", note: "PT-BR greeting (verbatim from real history)" },
  { prompt: "obrigado, ficou ótimo", mode: "MINIMAL", note: "PT-BR thanks/confirmation, no new work" },
  { prompt: "beleza", mode: "MINIMAL", note: "PT-BR bare acknowledgment" },
  { prompt: "got it", mode: "MINIMAL", note: "bare acknowledgment" },
  { prompt: "9/10", mode: "MINIMAL", note: "bare rating" },

  // ── ALGORITHM — PT-BR ──
  { prompt: "investiga por que o app trava ao iniciar quando está offline e corrige", mode: "ALGORITHM", tiers: ["E3", "E4", "E5"], note: "PT-BR twin of repro + fix" },
  { prompt: "refatora o módulo de pagamento para suportar múltiplas moedas, com testes", mode: "ALGORITHM", tiers: ["E3", "E4", "E5"], note: "PT-BR twin of cross-cutting refactor" },

  // ── ALGORITHM — additional EN coverage ──
  { prompt: "set up a GitHub Actions workflow that runs the test suite on every push and blocks merges on failure", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "multi-step infra setup" },
  { prompt: "the API latency doubled since last week's deploy — find out why", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "investigation" },
  { prompt: "add dark mode support across the whole settings UI", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "cross-file feature" },
  { prompt: "write integration tests covering the checkout flow end to end", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "test-suite build-out" },
  { prompt: "profile the startup path and cut cold-start time in half", mode: "ALGORITHM", tiers: ["E3", "E4", "E5"], note: "perf work with a target" },

  // ── ALGORITHM — escalation-risk probes (2026-07-04, second review round).
  // The prompt now biases toward NATIVE under uncertainty; the risk that bias
  // introduces is UNDER-escalation on short vague imperatives that superficially
  // resemble the trivial-edit class. These cases measure exactly that side.
  { prompt: "fix the login bug", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "escalation-risk: short imperative, but cause/location must be discovered" },
  { prompt: "make the dashboard load faster", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "escalation-risk: perf work hiding behind a one-liner" },
  { prompt: "o build tá quebrado, arruma", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "escalation-risk PT-BR: vague fix request" },
  { prompt: "update all dependencies and fix whatever breaks", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "escalation-risk: unbounded follow-on work" },
  { prompt: "add error handling to the API client", mode: "ALGORITHM", tiers: ["E2", "E3"], note: "escalation-risk: scope must be discovered across call sites" },
  { prompt: "os testes estão intermitentes, resolve", mode: "ALGORITHM", tiers: ["E2", "E3", "E4"], note: "escalation-risk PT-BR: flakiness investigation" },
];

export const DEFAULT_GOLDEN_THRESHOLDS = {
  // Share of cases whose MODE matched. The primary routing signal.
  modeWarn: 0.85,
  modeAlert: 0.65,
  // Among ALGORITHM cases where the mode matched, share whose tier fell in the
  // accepted set. Secondary — tier misses waste effort, mode misses change behavior.
  tierWarn: 0.6,
};

const MODE_ESCALATION = { MINIMAL: 0, NATIVE: 1, ALGORITHM: 2 };

/**
 * Aggregate N classification runs of ONE case into a single result by majority
 * vote. Pure. Exists because a single LLM run is nondeterministic: with 1 run
 * per case, one lucky/unlucky sample moves accuracy by a whole case-width and
 * the ok/warn status can flap run-to-run.
 *
 * Vote policy:
 *   • mode: modal vote; ties break toward the MORE escalated mode (matches the
 *     production fail-safe doctrine, and biases the eval against us — a tie can
 *     only make the NATIVE-boundary numbers look worse, never better).
 *   • tier: modal tier among the runs that voted the winning mode; ties break
 *     toward the higher tier for the same reason.
 *   • source: modal source across valid runs (for degradation reporting).
 *
 * @param {Array<{mode: string, tier: string|null, source?: string}|null>} runs
 * @returns {{result: {mode: string, tier: string|null, source?: string}|null,
 *            disagreed: boolean, votes: Record<string, number>}}
 */
export function aggregateRuns(runs) {
  const valid = (runs || []).filter((r) => r && typeof r.mode === "string");
  if (!valid.length) return { result: null, disagreed: false, votes: {} };

  const votes = {};
  for (const r of valid) votes[r.mode] = (votes[r.mode] || 0) + 1;
  const mode = Object.entries(votes).sort(
    (a, b) => b[1] - a[1] || (MODE_ESCALATION[b[0]] ?? -1) - (MODE_ESCALATION[a[0]] ?? -1),
  )[0][0];

  const tierVotes = {};
  for (const r of valid) {
    if (r.mode === mode && r.tier) tierVotes[r.tier] = (tierVotes[r.tier] || 0) + 1;
  }
  const tierTop = Object.entries(tierVotes).sort(
    (a, b) => b[1] - a[1] || b[0].localeCompare(a[0]),
  )[0];
  const tier = tierTop ? tierTop[0] : null;

  const sourceVotes = {};
  for (const r of valid) {
    if (r.source) sourceVotes[r.source] = (sourceVotes[r.source] || 0) + 1;
  }
  const srcTop = Object.entries(sourceVotes).sort((a, b) => b[1] - a[1])[0];

  return {
    result: { mode, tier, ...(srcTop ? { source: srcTop[0] } : {}) },
    disagreed: Object.keys(votes).length > 1,
    votes,
  };
}

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
