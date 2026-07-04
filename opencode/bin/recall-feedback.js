#!/usr/bin/env bun
/**
 * recall-feedback.js — ON-DEMAND recall of low-rating feedback (see
 * plugins/lib/feedback-recall.lib.js). Reads the LEARNING archive and prints the
 * recent low ratings + recurring themes. It does NOT change any behavior or inject
 * anything into a prompt — it only surfaces what you already told the system, when
 * you ask. Invoked by the `/feedback` command or run directly.
 *
 * Usage:
 *   bun bin/recall-feedback.js [--limit N] [--since-days D] [--query TEXT] [--json]
 *
 * Exit code is always 0 — recall is informational, not a gate.
 * Paths mirror the plugin: $PAI_DIR or ~/.config/opencode/PAI.
 */
import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import { analyzeFeedback, LOW_RATING_MAX } from "../plugins/lib/feedback-recall.lib.js";

const args = process.argv.slice(2);
const has = (f) => args.includes(f);
const val = (f, d) => {
  const i = args.indexOf(f);
  return i >= 0 && args[i + 1] ? args[i + 1] : d;
};

const PAI_DIR = process.env.PAI_DIR || join(homedir(), ".config", "opencode", "PAI");
const ratingsPath = join(PAI_DIR, "MEMORY", "LEARNING", "SIGNALS", "ratings.jsonl");

const limit = parseInt(val("--limit", "10"), 10);
const sinceDays = args.includes("--since-days") ? parseInt(val("--since-days", "0"), 10) : null;
const query = args.includes("--query") ? val("--query", "") : null;
// Date.now() is fine in a standalone CLI (unlike workflow scripts).
const sinceMs = sinceDays != null ? Date.now() - sinceDays * 86400_000 : null;

function readJsonl(path) {
  if (!existsSync(path)) return [];
  return readFileSync(path, "utf-8")
    .split("\n")
    .filter(Boolean)
    .map((l) => {
      try {
        return JSON.parse(l);
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

const ratings = readJsonl(ratingsPath);
const report = analyzeFeedback(ratings, { limit, maxRating: LOW_RATING_MAX, sinceMs, query });

if (has("--json")) {
  console.log(JSON.stringify({ ...report, ratingsPath }, null, 2));
  process.exit(0);
}

if (report.total === 0) {
  console.log("No ratings recorded yet (LEARNING/SIGNALS/ratings.jsonl is empty or absent).");
  process.exit(0);
}

console.log(`📋 Low-rating feedback (≤${LOW_RATING_MAX}/10)` + (query ? ` matching "${query}"` : "") + (sinceDays != null ? ` from the last ${sinceDays}d` : ""));
console.log(`   ${report.lowTotal} low of ${report.total} total ratings; showing ${report.returned}`);
if (report.themes.length) {
  console.log(`   recurring themes: ${report.themes.map((t) => `${t.term}(${t.count})`).join(", ")}`);
}
console.log("");
for (const r of report.recent) {
  const when = r.when ? r.when.replace("T", " ").replace(/\..*/, "") : "unknown time";
  console.log(`  ${r.rating}/10  ${when}${r.session_id ? `  [${r.session_id}]` : ""}`);
  if (r.comment) console.log(`        “${r.comment}”`);
}
if (report.lowTotal > report.returned) {
  console.log(`\n  … ${report.lowTotal - report.returned} more. Use --limit to see them.`);
}
process.exit(0);
