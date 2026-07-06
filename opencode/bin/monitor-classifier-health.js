#!/usr/bin/env bun
/**
 * monitor-classifier-health.js — turns mode-classifier.jsonl from a write-only log
 * into a live health signal (see plugins/lib/classifier-health.lib.js).
 *
 * Reports the share of classifications that degraded off the intended path. When the
 * config expects the LLM classifier (useLLM=true, the default) but classifications
 * are coming back 'heuristic'/'fail-safe', the production path has silently broken.
 *
 * Usage:
 *   bun bin/monitor-classifier-health.js [--window N] [--json] [--quiet]
 *
 * Exit codes: 0 ok / insufficient · 1 warn · 2 alert  (usable from cron & CI).
 * Resolution order for paths mirrors the plugin: $PAI_DIR or ~/.config/opencode/PAI.
 */
import { readFileSync, existsSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { homedir } from "os";
import {
  analyzeClassifierHealth,
  DEFAULT_THRESHOLDS,
} from "../plugins/lib/classifier-health.lib.js";
import { resolveClassifierConfig } from "../plugins/lib/mode-classifier.lib.js";

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const val = (f, d) => {
  const i = args.indexOf(f);
  return i >= 0 && args[i + 1] ? args[i + 1] : d;
};

const PAI_DIR =
  process.env.PAI_DIR ||
  join(homedir(), ".config", "opencode", "PAI");
const streamPath = join(PAI_DIR, "MEMORY", "OBSERVABILITY", "mode-classifier.jsonl");
const configPath = join(PAI_DIR, "USER", "Config", "classifier.json");
const window = parseInt(val("--window", "50"), 10);

function readJsonl(path) {
  if (!existsSync(path)) return [];
  return readFileSync(path, "utf-8")
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

function readConfigFile(path) {
  if (!existsSync(path)) return {};
  try {
    return JSON.parse(readFileSync(path, "utf-8"));
  } catch {
    return {};
  }
}

const entries = readJsonl(streamPath);
const config = resolveClassifierConfig(readConfigFile(configPath), process.env);
const report = analyzeClassifierHealth(entries, {
  expectLLM: config.useLLM,
  window,
  thresholds: DEFAULT_THRESHOLDS,
  // Judge only telemetry-contract-v2 rows (per-row use_llm, cd86b05). Pre-v2 rows
  // used different labeling (meta-bypass coerced to 'fail-safe') and permanently
  // poison the window on low-traffic machines — the exact false alarm that kept
  // pai-health.service red from 2026-07-05 despite zero real LLM failures.
  requireIntentField: true,
});

const exitCode = report.status === "alert" ? 2 : report.status === "warn" ? 1 : 0;

if (has("--json")) {
  console.log(JSON.stringify({ ...report, expectLLM: config.useLLM, streamPath }, null, 2));
  process.exit(exitCode);
}

if (!has("--quiet")) {
  const icon = { ok: "✅", warn: "⚠️", alert: "🚨", insufficient: "ℹ️" }[report.status];
  console.log(`${icon} classifier health: ${report.status.toUpperCase()}`);
  console.log(
    `   window=${window}  considered=${report.considered}/${report.total}  expectLLM=${config.useLLM}`,
  );
  const srcs = Object.entries(report.bySource)
    .sort((a, b) => b[1] - a[1])
    .map(([s, n]) => `${s}:${n}`)
    .join("  ");
  console.log(`   sources: ${srcs || "(none)"}`);
  for (const r of report.reasons) console.log(`   • ${r}`);
  if (report.status === "alert" || report.status === "warn") {
    console.log(
      `   → check: is \`opencode run --pure --model ${config.model}\` still returning parseable MODE/TIER? See docs/HARNESS_QUALITY.md.`,
    );
  }
}

process.exit(exitCode);
