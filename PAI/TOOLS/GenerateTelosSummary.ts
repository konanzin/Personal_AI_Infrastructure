#!/usr/bin/env bun
/**
 * GenerateTelosSummary.ts — Reads TELOS source files and generates a compressed
 * ~60-line summary for boot context loading.
 *
 * Ported from PAI v5.0.0 (Claude Code) to OpenCode conventions: paths resolve
 * via getPaiDir(); supports --json and --dry-run; returns a structured
 * `unavailable` result when the core sources (MISSION/GOALS/PROBLEMS) are all
 * missing, instead of writing an authoritative-looking empty summary.
 *
 * Usage:
 *   bun PAI/TOOLS/GenerateTelosSummary.ts [--json] [--dry-run]
 *
 * Reads:  ${PAI_DIR}/USER/TELOS/*.md
 * Writes: ${PAI_DIR}/USER/TELOS/PRINCIPAL_TELOS.md
 */

import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { getPaiDir, writeText, printJson } from "./lib/tool-runtime";

const TELOS_DIR = join(getPaiDir(), "USER", "TELOS");
const OUTPUT_PATH = join(TELOS_DIR, "PRINCIPAL_TELOS.md");

interface ParsedItem {
  id: string;
  text: string;
}

function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  const cut = text.substring(0, max).replace(/\s+\S*$/, "");
  return cut + "...";
}

function readTelosFile(filename: string): string {
  const path = join(TELOS_DIR, filename);
  if (!existsSync(path)) return "";
  return readFileSync(path, "utf-8");
}

function parseItems(content: string): ParsedItem[] {
  const items: ParsedItem[] = [];
  for (const line of content.split("\n")) {
    const match = line.match(/^-\s+\*?\*?(\w+)\*?\*?:\s*(.+)/);
    if (match) items.push({ id: match[1], text: match[2].trim() });
  }
  return items;
}

function parseMissions(): string[] {
  return parseItems(readTelosFile("MISSION.md")).map((i) => `- **${i.id}**: ${truncate(i.text, 75)}`);
}

function parseGoals(): { active: string[]; deferred: string[] } {
  const items = parseItems(readTelosFile("GOALS.md"));
  const active: string[] = [];
  const deferred: string[] = [];
  for (const item of items) {
    const num = parseInt(item.id.replace(/\D/g, ""), 10);
    const firstSentence = item.text.split(/\s—\s|(?<!\w\.\w)(?<=\w)\.\s/)[0].trim();
    if (num >= 9 || [0, 1].includes(num)) {
      active.push(`- **${item.id}**: ${truncate(firstSentence, 70)}`);
    } else {
      deferred.push(`- **${item.id}**: ${truncate(firstSentence, 50)}`);
    }
  }
  return { active, deferred };
}

function parseProblems(): string[] {
  const content = readTelosFile("PROBLEMS.md");
  const lines: string[] = [];
  const headers = [...content.matchAll(/^##\s+(P\d+):\s*(.+?)(?:\s*\(.*\))?\s*$/gm)];
  for (const match of headers) {
    const title = match[2].trim();
    const short = title.length > 60 ? title.substring(0, 57) + "..." : title;
    lines.push(`- **${match[1]}**: ${short}`);
  }
  if (lines.length === 0) {
    for (const item of parseItems(content)) {
      const title = item.text.split(/[—-]/)[0].trim().replace(/\*\*/g, "");
      lines.push(`- **${item.id}**: ${title}`);
    }
  }
  return lines;
}

function parseStrategies(): string[] {
  const content = readTelosFile("STRATEGIES.md");
  const lines: string[] = [];
  for (const match of content.matchAll(/^#{2,3}\s+(S\d+):\s*(.+?)(?:\s*\(.*\))?\s*$/gm)) {
    const short = match[2].length > 60 ? match[2].substring(0, 57) + "..." : match[2];
    lines.push(`- **${match[1]}**: ${short}`);
  }
  return lines;
}

function parseNarratives(): { primary: string[]; secondary: string[] } {
  const items = parseItems(readTelosFile("NARRATIVES.md"));
  const primary: string[] = [];
  const secondary: string[] = [];
  for (const item of items) {
    const num = parseInt(item.id.replace(/\D/g, ""), 10);
    if ([0, 1, 7].includes(num)) {
      primary.push(`- **${item.id}**: ${truncate(item.text, 75)}`);
    } else {
      secondary.push(`${item.id}: ${truncate(item.text, 60)}`);
    }
  }
  return { primary, secondary };
}

function parseChallenges(): string[] {
  return parseItems(readTelosFile("CHALLENGES.md")).map((i) => `- **${i.id}**: ${truncate(i.text, 90)}`);
}

function parseWrong(): string[] {
  const out: string[] = [];
  for (const line of readTelosFile("WRONG.md").split("\n")) {
    const m = line.match(/^-\s+(.+)$/);
    if (m) out.push(`- ${truncate(m[1].trim(), 110)}`);
  }
  return out;
}

function parseTraumas(): string[] {
  return parseItems(readTelosFile("TRAUMAS.md")).map((i) => `- **${i.id}**: ${truncate(i.text, 90)}`);
}

function parseModels(): string[] {
  return parseItems(readTelosFile("MODELS.md")).slice(0, 3).map((i) => {
    const first = i.text.split(/\.\s/)[0].trim();
    return `- ${truncate(first, 65)}`;
  });
}

function generate(): string {
  const now = new Date().toISOString();
  const missions = parseMissions();
  const goals = parseGoals();
  const problems = parseProblems();
  const strategies = parseStrategies();
  const narratives = parseNarratives();
  const challenges = parseChallenges();
  const wrong = parseWrong();
  const traumas = parseTraumas();
  const models = parseModels();

  const lines: string[] = [
    "# Principal TELOS — {{PRINCIPAL_FULL_NAME}}",
    "",
    "> Auto-generated from TELOS source files. Do not edit manually.",
    `> Generated: ${now} | Sources: MISSION, GOALS, PROBLEMS, STRATEGIES, NARRATIVES, CHALLENGES, WRONG, TRAUMAS, MODELS`,
    "",
    "## Missions",
    "",
    ...missions,
    "",
    "## Active Goals (2026)",
    "",
    ...goals.active,
  ];

  if (goals.deferred.length > 0) {
    const deferredIds = goals.deferred
      .map((line) => line.match(/\*\*(\w+)\*\*/)?.[1])
      .filter(Boolean)
      .join(", ");
    lines.push("", `_Deferred (full text in TELOS/GOALS.md): ${deferredIds}_`);
  }

  lines.push("", "## Problems Being Solved", "", ...problems, "", "## Strategies", "", ...strategies, "", "## Active Narratives", "", ...narratives.primary);
  if (narratives.secondary.length > 0) lines.push(...narratives.secondary.map((n) => `- ${n}`));
  lines.push("", "## Personal Challenges", "", ...challenges);
  if (traumas.length > 0) lines.push("", "## Formative Experiences (Traumas)", "", ...traumas);
  if (wrong.length > 0) lines.push("", "## Things I've Been Wrong About (Mistakes)", "", ...wrong);
  lines.push(
    "",
    "## Core Models",
    "",
    ...models,
    "",
    "## Context Filter",
    "",
    "When steering work, bias toward: human flourishing, Human 3.0 transition, AI augmentation strategies, becoming one's full self, correct framing.",
  );

  return lines.join("\n") + "\n";
}

function main() {
  const args = process.argv.slice(2);
  const json = args.includes("--json");
  const dryRun = args.includes("--dry-run");

  // A TELOS summary is only authoritative if the core sources exist.
  const hasCore = ["MISSION.md", "GOALS.md", "PROBLEMS.md"].some((f) => readTelosFile(f).trim().length > 0);
  if (!hasCore) {
    const result = { status: "unavailable", reason: "No TELOS core sources (MISSION/GOALS/PROBLEMS) found", telos_dir: TELOS_DIR };
    if (json) printJson(result);
    else console.log(`TELOS summary unavailable: ${result.reason}`);
    return;
  }

  const summary = generate();
  const lineCount = summary.split("\n").length;
  if (!dryRun) writeText(OUTPUT_PATH, summary);

  const result = { status: "ok", dry_run: dryRun, line_count: lineCount, output: OUTPUT_PATH };
  if (json) printJson(result);
  else console.log(`${dryRun ? "Would generate" : "Generated"} PRINCIPAL_TELOS.md (${lineCount} lines) at ${OUTPUT_PATH}`);
}

main();
