#!/usr/bin/env bun
/**
 * SessionHarvester.ts - mine session transcripts for learning and knowledge candidates.
 *
 * The OpenCode port keeps this tool conservative: dry-run is first-class, and
 * --mine writes only review candidates under KNOWLEDGE/_harvest-queue/.
 */

import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "fs";
import { basename, join } from "path";
import { homedir } from "os";
import { parseArgs } from "util";

type MemoryType = "decision" | "preference" | "milestone" | "problem";

type MinedMemory = {
  sessionId: string;
  timestamp: string;
  memoryType: MemoryType;
  content: string;
  context: string;
  patternHits: number;
  sourcePattern: string;
  sourceLine: number;
};

type HarvestedLearning = {
  sessionId: string;
  timestamp: string;
  category: "SYSTEM" | "ALGORITHM";
  type: "correction" | "error" | "insight";
  context: string;
  content: string;
  source: string;
};

const PAI_DIR = process.env.PAI_DIR || join(homedir(), ".config", "opencode", "PAI");
const LEARNING_DIR = join(PAI_DIR, "MEMORY", "LEARNING");
const HARVEST_QUEUE_DIR = join(PAI_DIR, "MEMORY", "KNOWLEDGE", "_harvest-queue");

const CORRECTION_PATTERNS = [
  /actually,?\s+/i,
  /wait,?\s+/i,
  /no,?\s+i meant/i,
  /let me clarify/i,
  /that's not (quite )?right/i,
  /you misunderstood/i,
  /my mistake/i,
];

const ERROR_PATTERNS = [
  /error:/i,
  /failed:/i,
  /exception:/i,
  /stderr:/i,
  /command failed/i,
  /permission denied/i,
  /not found/i,
];

const INSIGHT_PATTERNS = [
  /learned that/i,
  /realized that/i,
  /discovered that/i,
  /key insight/i,
  /important:/i,
  /note to self/i,
  /for next time/i,
  /lesson:/i,
];

const MINING_PATTERNS: Record<MemoryType, RegExp[]> = {
  decision: [
    /(?:we|i) (?:decided|chose|went with|picked|selected)\b/i,
    /(?:let'?s|going to) (?:use|go with|switch to|adopt)\b/i,
    /(?:the )?(?:decision|choice|call) (?:is|was) to\b/i,
    /(?:trade-?off|chose .+ over|prefer .+ to)\b/i,
  ],
  preference: [
    /(?:always|never|don'?t) (?:use|do|add|create|write|make)\b/i,
    /(?:prefer|like|want|hate|avoid)\s+(?:to |using |when )/i,
    /(?:the rule|the convention|our standard) is\b/i,
    /(?:must|should|shall) (?:always|never)\b/i,
  ],
  milestone: [
    /(?:it |that |this )(?:works?|worked|shipped|deployed|launched)\b/i,
    /(?:finally|successfully) (?:got|made|built|shipped|deployed|fixed)\b/i,
    /(?:pushed|merged|released|published|completed|finished)\b/i,
  ],
  problem: [
    /(?:the )?(?:issue|problem|bug|failure|crash) (?:is|was|seems)\b/i,
    /(?:broke|broken|breaking|fails?|failed|crashing)\b/i,
    /(?:can'?t|couldn'?t|unable to|won'?t|doesn'?t work)\b/i,
    /(?:root cause|caused by|the reason|turns out)\b/i,
  ],
};

function defaultSessionDirs(): string[] {
  const dirs = [
    process.env.PAI_SESSION_DIR,
    process.env.OPENCODE_PROJECTS_DIR,
    join(homedir(), ".config", "opencode", "projects"),
    join(homedir(), ".claude", "projects"),
  ].filter((value): value is string => Boolean(value));
  return [...new Set(dirs)];
}

function walkJsonl(root: string): string[] {
  if (!existsSync(root)) return [];
  const out: string[] = [];
  const walk = (dir: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === "node_modules" || entry.name === ".git") continue;
        walk(full);
      } else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
        out.push(full);
      }
    }
  };
  walk(root);
  return out;
}

function getSessionFiles(options: { recent?: number; all?: boolean; sessionId?: string; sessionsDir?: string }): string[] {
  const roots = options.sessionsDir ? [options.sessionsDir] : defaultSessionDirs();
  const files = roots
    .flatMap(walkJsonl)
    .map((path) => ({ path, mtime: statSync(path).mtime.getTime() }))
    .sort((a, b) => b.mtime - a.mtime);

  if (options.sessionId) {
    return files.filter((file) => basename(file.path).includes(options.sessionId!)).map((file) => file.path);
  }

  if (options.all) {
    const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
    return files.filter((file) => file.mtime >= sevenDaysAgo).map((file) => file.path);
  }

  return files.slice(0, options.recent || 10).map((file) => file.path);
}

function extractText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .map((part: any) => {
      if (typeof part === "string") return part;
      if (part?.type === "text" && typeof part.text === "string") return part.text;
      return "";
    })
    .filter(Boolean)
    .join("\n");
}

function textFromEntry(entry: any): { role: string; text: string; timestamp: string } | null {
  // Prefer explicit role fields; fall back to `type` only as a last resort.
  // OpenCode transcripts use type="message"/"system" with the real role under
  // `role`/`message.role`, so reading `type` first mislabels every turn and
  // silently skips correction/error/insight detection.
  const rawRole = entry?.role ?? entry?.message?.role ?? entry?.type ?? "unknown";
  const role = rawRole === "human" ? "user" : rawRole;
  const content = entry?.message?.content ?? entry?.content ?? entry?.text;
  const text = extractText(content).trim();
  if (!text || text.length < 20) return null;
  return { role, text, timestamp: entry?.timestamp || new Date().toISOString() };
}

function matchPattern(text: string, patterns: RegExp[]): string | null {
  for (const pattern of patterns) {
    if (pattern.test(text)) return pattern.source;
  }
  return null;
}

function categoryFor(text: string): "SYSTEM" | "ALGORITHM" {
  const lower = text.toLowerCase();
  if (/hook|plugin|config|deploy|path|typescript|javascript|bun|npm|import|module/.test(lower)) return "SYSTEM";
  return "ALGORITHM";
}

function readEntries(sessionPath: string): any[] {
  return readFileSync(sessionPath, "utf-8")
    .split(/\r?\n/)
    .filter((line) => line.trim())
    .flatMap((line) => {
      try {
        return [JSON.parse(line)];
      } catch {
        return [];
      }
    });
}

function harvestLearnings(sessionPath: string): HarvestedLearning[] {
  const sessionId = basename(sessionPath, ".jsonl");
  const learnings: HarvestedLearning[] = [];
  let previousContext = "";

  for (const entry of readEntries(sessionPath)) {
    const extracted = textFromEntry(entry);
    if (!extracted) continue;
    const { role, text, timestamp } = extracted;

    if (role === "user") {
      const source = matchPattern(text, CORRECTION_PATTERNS);
      if (source) {
        learnings.push({
          sessionId,
          timestamp,
          category: categoryFor(text),
          type: "correction",
          context: previousContext.slice(0, 300),
          content: text.slice(0, 700),
          source,
        });
      }
    }

    if (role === "assistant") {
      const errorSource = matchPattern(text, ERROR_PATTERNS);
      const insightSource = matchPattern(text, INSIGHT_PATTERNS);
      if (errorSource) {
        learnings.push({
          sessionId,
          timestamp,
          category: categoryFor(text),
          type: "error",
          context: previousContext.slice(0, 300),
          content: text.slice(0, 700),
          source: errorSource,
        });
      }
      if (insightSource) {
        learnings.push({
          sessionId,
          timestamp,
          category: categoryFor(text),
          type: "insight",
          context: previousContext.slice(0, 300),
          content: text.slice(0, 700),
          source: insightSource,
        });
      }
    }

    previousContext = text;
  }

  return learnings;
}

function mineMemories(sessionPath: string): MinedMemory[] {
  const sessionId = basename(sessionPath, ".jsonl");
  const memories: MinedMemory[] = [];
  const entries = readEntries(sessionPath);

  entries.forEach((entry, index) => {
    const extracted = textFromEntry(entry);
    if (!extracted) return;
    const { text, timestamp } = extracted;

    for (const [memoryType, patterns] of Object.entries(MINING_PATTERNS) as [MemoryType, RegExp[]][]) {
      const matches = patterns.filter((pattern) => pattern.test(text));
      if (matches.length === 0) continue;
      // W2.12: no fabricated confidence — 0.35+0.15/hit was arithmetic wearing
      // a probability costume. The honest datum is the raw hit count; judgment
      // about whether a candidate matters belongs to whoever reviews the queue.
      const patternHits = matches.length;
      memories.push({
        sessionId,
        timestamp,
        memoryType,
        content: text.slice(0, 700),
        context: text.slice(0, 400),
        patternHits,
        sourcePattern: matches[0].source,
        sourceLine: index + 1,
      });
    }
  });

  const seen = new Set<string>();
  return memories
    .sort((a, b) => b.patternHits - a.patternHits)
    .filter((memory) => {
      const key = `${memory.memoryType}:${memory.content.slice(0, 120).toLowerCase()}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

function safeSlug(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 60) || "session-memory";
}

function writeQueue(memory: MinedMemory): string {
  mkdirSync(HARVEST_QUEUE_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const file = `mine_${stamp}_${memory.memoryType}_${safeSlug(memory.sessionId).slice(0, 16)}_L${memory.sourceLine}.json`;
  const path = join(HARVEST_QUEUE_DIR, file);
  writeFileSync(path, `${JSON.stringify({
    title: `${memory.memoryType}: ${memory.content.slice(0, 80)}`,
    content: `## ${memory.memoryType}\n\n${memory.content}\n\n## Context\n\n${memory.context}`,
    domain: "Ideas",
    type: "idea",
    tags: [memory.memoryType, "mined"],
    pattern_hits: memory.patternHits,
    sourcePattern: memory.sourcePattern,
    sourcePath: memory.sessionId,
    sourceLine: memory.sourceLine,
    minedAt: new Date().toISOString(),
  }, null, 2)}\n`, "utf-8");
  return path;
}

function writeLearning(learning: HarvestedLearning): string {
  const date = new Date(learning.timestamp);
  const month = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
  const dir = join(LEARNING_DIR, learning.category, month);
  mkdirSync(dir, { recursive: true });
  const file = `${date.toISOString().slice(0, 10)}_${learning.type}_${safeSlug(learning.sessionId).slice(0, 16)}.md`;
  const path = join(dir, file);
  if (existsSync(path)) return path;
  writeFileSync(path, `# ${learning.type} learning

Session: ${learning.sessionId}
Timestamp: ${learning.timestamp}
Category: ${learning.category}
Source: ${learning.source}

## Context

${learning.context}

## Learning

${learning.content}
`, "utf-8");
  return path;
}

const { values } = parseArgs({
  args: process.argv.slice(2),
  options: {
    recent: { type: "string" },
    all: { type: "boolean" },
    session: { type: "string" },
    "sessions-dir": { type: "string" },
    "dry-run": { type: "boolean" },
    mine: { type: "boolean", short: "m" },
    json: { type: "boolean" },
    help: { type: "boolean", short: "h" },
  },
});

if (values.help) {
  console.log(`Usage:
  bun PAI/TOOLS/SessionHarvester.ts --recent 10 [--dry-run] [--json]
  bun PAI/TOOLS/SessionHarvester.ts --mine --recent 10 [--dry-run] [--json]
  bun PAI/TOOLS/SessionHarvester.ts --sessions-dir <dir> --mine --json`);
  process.exit(0);
}

const sessionFiles = getSessionFiles({
  recent: values.recent ? Number(values.recent) : undefined,
  all: Boolean(values.all),
  sessionId: values.session,
  sessionsDir: values["sessions-dir"],
});

if (sessionFiles.length === 0) {
  const result = { status: "no_sessions", sessions: 0, candidates: [], learnings: [] };
  console.log(values.json ? JSON.stringify(result, null, 2) : "No sessions found to harvest");
  process.exit(0);
}

if (values.mine) {
  const candidates = sessionFiles.flatMap(mineMemories);
  const written = values["dry-run"] ? [] : candidates.map(writeQueue);
  const result = { status: "ok", mode: "mine", sessions: sessionFiles.length, candidates, written };
  console.log(values.json ? JSON.stringify(result, null, 2) : `${candidates.length} candidate(s) ${values["dry-run"] ? "found" : "queued"}`);
  process.exit(0);
}

const learnings = sessionFiles.flatMap(harvestLearnings);
const written = values["dry-run"] ? [] : learnings.map(writeLearning);
const result = { status: "ok", mode: "learn", sessions: sessionFiles.length, learnings, written };
console.log(values.json ? JSON.stringify(result, null, 2) : `${learnings.length} learning(s) ${values["dry-run"] ? "found" : "written"}`);
