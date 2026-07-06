#!/usr/bin/env bun
/**
 * eval-escalation-golden.js — measure EXECUTOR escalation behavior under the
 * W1.2 suggestion posture (the guard the 2026-07-05 audit found missing).
 *
 * The classifier golden proves the classifier labels prompts correctly. This
 * proves the primary model, shown the EXACT suggestion prose production
 * injects (formatClassificationContext), (a) overrides a wrong-LOW suggestion
 * — the 2026-04 under-escalation incident class, (b) overrides a wrong-HIGH
 * suggestion instead of paying full ceremony for a typo fix, and (c) adopts
 * correct suggestions instead of fighting them.
 *
 * Honest scope: this drives the decision through `opencode run --pure` with a
 * condensed executor context — a proxy for the full session harness, but the
 * classification block is the verbatim production rendering, which is the
 * surface W1.2 changed and the one under test.
 *
 * ON-DEMAND ONLY: every case costs one LLM call; NOT part of `bun test`.
 * Run after changing formatClassificationContext, the mode rules prose, or the
 * session model — and before merging any W2.2 (classifier-as-gate) change.
 *
 * Usage:
 *   bun bin/eval-escalation-golden.js --model <provider/model>   # REQUIRED: the executor model to probe
 *   bun bin/eval-escalation-golden.js --model X --kind under     # one kind: under|tier-under|over|control|none
 *   bun bin/eval-escalation-golden.js --model X --limit 5        # quick smoke
 *   bun bin/eval-escalation-golden.js --model X --runs 3         # majority vote per case
 *   bun bin/eval-escalation-golden.js --model X --concurrency 2  # in-flight opencode runs (default 2)
 *   bun bin/eval-escalation-golden.js --model X --json           # machine-readable
 *
 * Exit codes: 0 ok · 1 warn · 2 alert.
 */
import {
  execOpencodeRun,
  formatClassificationContext,
} from "../plugins/lib/mode-classifier.lib.js";
import { GOLDEN_SET } from "../plugins/lib/classifier-golden.lib.js";
import {
  buildEscalationCases,
  buildExecutorPrompt,
  parseDecision,
  scoreEscalation,
  DEFAULT_ESCALATION_THRESHOLDS,
} from "../plugins/lib/escalation-golden.lib.js";
import { aggregateRuns } from "../plugins/lib/classifier-golden.lib.js";

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const val = (f, d) => {
  const i = args.indexOf(f);
  return i >= 0 && args[i + 1] ? args[i + 1] : d;
};

const model = val("--model", null);
if (!model) {
  // The executor model is a session choice, not a config file — an implicit
  // default here would silently measure the wrong model. Fail loudly instead.
  console.error("usage: bun bin/eval-escalation-golden.js --model <provider/model> [--kind under|over|control] [--limit N] [--runs N] [--json]");
  process.exit(2);
}
const timeoutMs = parseInt(val("--timeout-ms", "45000"), 10);
const kindFilter = val("--kind", null);
const runsPerCase = Math.max(1, parseInt(val("--runs", "1"), 10) || 1);

let cases = buildEscalationCases(GOLDEN_SET);
if (kindFilter) cases = cases.filter((c) => c.kind === kindFilter);
const limit = parseInt(val("--limit", String(cases.length)), 10);
cases = cases.slice(0, limit);

// Each in-flight case is a full `opencode run` instance (heavy: node + session
// state). 4 concurrent instances exhausted a workstation's tmpfs quota once
// (2026-07-06) — default conservatively and let --concurrency raise it.
const CONCURRENCY = Math.max(1, parseInt(val("--concurrency", "2"), 10) || 2);

async function decideCase(c) {
  // kind 'none' has no suggestion: the classification block is omitted and
  // the executor self-selects — the W2.2 end-state under measurement.
  const ctx = c.suggestion ? formatClassificationContext(c.suggestion) : undefined;
  const prompt = buildExecutorPrompt(c, ctx);
  const out = await execOpencodeRun(model, prompt, timeoutMs);
  return parseDecision(out);
}

async function run() {
  const runsMatrix = cases.map(() => new Array(runsPerCase).fill(null));
  const jobs = [];
  for (let i = 0; i < cases.length; i++) {
    for (let k = 0; k < runsPerCase; k++) jobs.push({ i, k });
  }
  let next = 0;
  let done = 0;

  async function worker() {
    while (next < jobs.length) {
      const { i, k } = jobs[next++];
      try {
        runsMatrix[i][k] = await decideCase(cases[i]);
      } catch (e) {
        runsMatrix[i][k] = null;
        console.error(`  ✗ case ${i} run ${k} errored: ${e.message}`);
      }
      done++;
      if (!has("--json") && !has("--quiet")) {
        process.stderr.write(`\r  decided ${done}/${jobs.length}…`);
      }
    }
  }

  await Promise.all(
    Array.from({ length: Math.min(CONCURRENCY, jobs.length) }, () => worker()),
  );
  if (!has("--json") && !has("--quiet")) process.stderr.write("\n");
  return runsMatrix;
}

const runsMatrix = await run();
const results = runsMatrix.map((runs) => aggregateRuns(runs).result);
const report = scoreEscalation(cases, results, DEFAULT_ESCALATION_THRESHOLDS);
const exitCode = report.status === "alert" ? 2 : report.status === "warn" ? 1 : 0;
const pct = (x) => (x == null ? "n/a" : `${(x * 100).toFixed(0)}%`);

if (has("--json")) {
  console.log(JSON.stringify({ ...report, model, runsPerCase, kindFilter }, null, 2));
  process.exit(exitCode);
}

const icon = { ok: "✅", warn: "⚠️", alert: "🚨" }[report.status];
console.log(`${icon} escalation golden eval: ${report.status.toUpperCase()}  [executor via ${model}]`);
console.log(`   under-correction (wrong-LOW mode overridden UP — the incident class): ${report.byKind.under.correct}/${report.byKind.under.total} (${pct(report.byKind.under.rate)})`);
console.log(`   tier-under      (wrong-LOW tier corrected into accepted set): ${report.byKind["tier-under"].correct}/${report.byKind["tier-under"].total} (${pct(report.byKind["tier-under"].rate)})`);
console.log(`   over-correction (wrong-HIGH suggestion overridden DOWN): ${report.byKind.over.correct}/${report.byKind.over.total} (${pct(report.byKind.over.rate)})`);
console.log(`   control adoption (correct suggestion adopted): ${report.byKind.control.correct}/${report.byKind.control.total} (${pct(report.byKind.control.rate)})`);
console.log(`   none / self-selection (no classifier block — the W2.2 gate): ${report.byKind.none.correct}/${report.byKind.none.total} (${pct(report.byKind.none.rate)})`);
if (report.failures.length) {
  console.log("   FAILURES:");
  for (const f of report.failures) {
    console.log(`     - [${f.kind}] "${f.prompt}"`);
    console.log(`         expected ${f.expected} · got ${f.got}`);
  }
}
process.exit(exitCode);
