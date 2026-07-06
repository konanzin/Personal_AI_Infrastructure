#!/usr/bin/env bun
/**
 * eval-classifier-golden.js — measure classification CORRECTNESS on the production
 * LLM path (the O3 true metric; see docs/HARNESS_QUALITY.md §1).
 *
 * The health monitor proves the LLM path is alive; this proves it is right. It
 * drives classifyPromptWithLLM — the exact function pai-hooks.js calls — over the
 * golden set in plugins/lib/classifier-golden.lib.js and scores mode/tier accuracy.
 *
 * ON-DEMAND ONLY: every case costs one LLM call, so this is NOT part of `bun test`.
 * Run it after changing the classifier model, the classification prompt, or the
 * parser — or on a schedule if you want drift caught automatically.
 *
 * Usage:
 *   bun bin/eval-classifier-golden.js                  # production config (classifier.json + env)
 *   bun bin/eval-classifier-golden.js --model <provider/model>      # eval a specific model
 *   bun bin/eval-classifier-golden.js --heuristic      # score the offline heuristic path (free)
 *   bun bin/eval-classifier-golden.js --limit 5        # quick smoke on the first N cases
 *   bun bin/eval-classifier-golden.js --runs 3         # N runs per case, majority vote (recommended
 *                                                      #   for before/after comparisons — a single run
 *                                                      #   is one nondeterministic sample per case)
 *   bun bin/eval-classifier-golden.js --json           # machine-readable report
 *
 * Exit codes: 0 ok · 1 warn · 2 alert  (usable from cron & CI).
 */
import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import {
  classifyPrompt,
  classifyPromptWithLLM,
  resolveClassifierConfig,
  normalizeClassification,
} from "../plugins/lib/mode-classifier.lib.js";
import {
  GOLDEN_SET,
  scoreGolden,
  aggregateRuns,
  DEFAULT_GOLDEN_THRESHOLDS,
} from "../plugins/lib/classifier-golden.lib.js";

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const val = (f, d) => {
  const i = args.indexOf(f);
  return i >= 0 && args[i + 1] ? args[i + 1] : d;
};

const PAI_DIR = process.env.PAI_DIR || join(homedir(), ".config", "opencode", "PAI");
const configPath = join(PAI_DIR, "USER", "Config", "classifier.json");

function readConfigFile(path) {
  if (!existsSync(path)) return {};
  try {
    return JSON.parse(readFileSync(path, "utf-8"));
  } catch {
    return {};
  }
}

const config = resolveClassifierConfig(readConfigFile(configPath), process.env);
const model = val("--model", config.model);
const timeoutMs = parseInt(val("--timeout-ms", String(config.timeoutMs)), 10);
const limit = parseInt(val("--limit", String(GOLDEN_SET.length)), 10);
const heuristicOnly = has("--heuristic");
const cases = GOLDEN_SET.slice(0, limit);
// Heuristic is pure and deterministic — repeated runs are pointless, force 1.
const runsPerCase = heuristicOnly ? 1 : Math.max(1, parseInt(val("--runs", "1"), 10) || 1);

// Concurrency pool — each LLM case is an `opencode run` subprocess (~seconds each).
const CONCURRENCY = 4;

async function classifyCase(prompt) {
  if (heuristicOnly) return normalizeClassification(classifyPrompt(prompt));
  // No fallback override: classifyPromptWithLLM resolves it exactly like
  // production does (PAI_CLASSIFIER_FALLBACK env, default 'fail-safe'), so the
  // eval measures whatever the running config would actually do on LLM failure —
  // degraded cases surface via non-llm `sources` in the report either way.
  // noCache: the 5-min LRU would replay run 1 for every repeat of the same prompt.
  return classifyPromptWithLLM(prompt, { model, timeoutMs, noCache: true });
}

async function run() {
  // runsMatrix[caseIndex][runIndex] — jobs are flattened so the pool stays busy
  // across both dimensions.
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
        runsMatrix[i][k] = await classifyCase(cases[i].prompt);
      } catch (e) {
        runsMatrix[i][k] = null;
        console.error(`  ✗ case ${i} run ${k} errored: ${e.message}`);
      }
      done++;
      if (!has("--json") && !has("--quiet")) {
        process.stderr.write(`\r  classified ${done}/${jobs.length}…`);
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
const aggregated = runsMatrix.map((runs) => aggregateRuns(runs));
const results = aggregated.map((a) => a.result);
const flaky = aggregated
  .map((a, i) => (a.disagreed ? { prompt: cases[i].prompt, votes: a.votes } : null))
  .filter(Boolean);
// Sources across ALL raw runs (not just the aggregated winners) — degradation
// during the eval should be visible even when the majority vote papered over it.
const rawSources = {};
for (const runs of runsMatrix) {
  for (const r of runs) {
    if (r?.source) rawSources[r.source] = (rawSources[r.source] || 0) + 1;
  }
}
const report = scoreGolden(cases, results, DEFAULT_GOLDEN_THRESHOLDS);
const exitCode = report.status === "alert" ? 2 : report.status === "warn" ? 1 : 0;
const pct = (x) => (x == null ? "n/a" : `${(x * 100).toFixed(0)}%`);
const path = heuristicOnly ? "heuristic (offline)" : `LLM via ${model}`;

if (has("--json")) {
  console.log(JSON.stringify({
    ...report,
    path,
    model: heuristicOnly ? null : model,
    cases: cases.length,
    runsPerCase,
    rawSources,
    flaky,
  }, null, 2));
  process.exit(exitCode);
}

const icon = { ok: "✅", warn: "⚠️", alert: "🚨" }[report.status];
console.log(`${icon} classifier golden eval: ${report.status.toUpperCase()}  [${path}]`);
console.log(`   MODE accuracy: ${report.modeCorrect}/${report.total} (${pct(report.modeAccuracy)})${runsPerCase > 1 ? ` — majority of ${runsPerCase} runs/case` : " — SINGLE run/case; use --runs 3 for a comparable number"}`);
console.log(`   TIER accuracy: ${report.tierCorrect}/${report.tierEligible} (${pct(report.tierAccuracy)}) — accepted-set membership, ALGORITHM cases only`);
const srcs = Object.entries(rawSources).map(([s, n]) => `${s}:${n}`).join("  ");
console.log(`   sources (all ${cases.length * runsPerCase} runs): ${srcs || "(none)"}`);
if (flaky.length) {
  console.log(`   FLAKY (runs disagreed on mode — these cases are one sample from flipping):`);
  for (const f of flaky) {
    const v = Object.entries(f.votes).map(([m, n]) => `${m}:${n}`).join(" ");
    console.log(`     - "${f.prompt}" → ${v}`);
  }
}
if (report.failures.length) {
  console.log("   FAILURES:");
  for (const f of report.failures) {
    console.log(`     - [${f.kind}] "${f.prompt}"`);
    console.log(`         expected ${f.expected} · got ${f.got}`);
  }
}
if (!heuristicOnly && Object.keys(rawSources).some((s) => s !== "llm")) {
  console.log("   → non-llm sources above mean the LLM path degraded DURING the eval; run bin/monitor-classifier-health.js.");
}
process.exit(exitCode);
