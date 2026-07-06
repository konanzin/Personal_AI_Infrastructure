#!/usr/bin/env bun
/**
 * KnowledgeHarvester.ts - maintenance and light harvesting for MEMORY/KNOWLEDGE.
 *
 * Implemented surface:
 *   status      Archive health summary.
 *   validate    Schema and link sanity checks.
 *   index       Regenerate domain/root MOC files.
 *   harvest     Convert review-queue/work/research candidates into notes.
 *   contradictions  List tag-overlap pairs for semantic review.
 */

import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, writeFileSync } from "fs";
import { basename, dirname, join, relative } from "path";
import { homedir } from "os";
import { parseArgs } from "util";
import { buildKnowledgeGraph, getKnowledgeDir, getPaiDir, readKnowledgeNotes } from "./lib/knowledge.ts";

type Candidate = {
  sourcePath: string;
  title: string;
  content: string;
  domain: string;
  type: "person" | "company" | "idea" | "research";
  tags: string[];
};

const PAI_DIR = process.env.PAI_DIR || getPaiDir() || join(homedir(), ".config", "opencode", "PAI");
const KNOWLEDGE_DIR = getKnowledgeDir(join(PAI_DIR, "MEMORY", "KNOWLEDGE"));
const WORK_DIR = join(PAI_DIR, "MEMORY", "WORK");
const RESEARCH_DIR = join(PAI_DIR, "MEMORY", "RESEARCH");
const QUEUE_DIR = join(KNOWLEDGE_DIR, "_harvest-queue");
const STATE_FILE = join(KNOWLEDGE_DIR, ".harvest-state.json");
const DOMAINS = ["People", "Companies", "Ideas", "Research"];

function print(data: unknown, json: boolean) {
  if (json) console.log(JSON.stringify(data, null, 2));
  else if (typeof data === "string") console.log(data);
  else console.log(JSON.stringify(data, null, 2));
}

function slugify(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 80) || "knowledge-note";
}

function yamlScalar(content: string, key: string): string | null {
  const match = content.match(new RegExp(`^${key}:\\s*(.+)$`, "im"));
  return match ? match[1].trim().replace(/^["']|["']$/g, "") : null;
}

function splitFrontmatter(content: string): { frontmatter: string; body: string } {
  if (!content.startsWith("---")) return { frontmatter: "", body: content };
  const end = content.indexOf("\n---", 3);
  if (end === -1) return { frontmatter: "", body: content };
  const after = content.indexOf("\n", end + 4);
  return { frontmatter: content.slice(3, end).trim(), body: after === -1 ? "" : content.slice(after + 1) };
}

function readState(): { harvestedPaths: string[]; lastHarvest: string | null; totalHarvested: number } {
  if (!existsSync(STATE_FILE)) return { harvestedPaths: [], lastHarvest: null, totalHarvested: 0 };
  try {
    const parsed = JSON.parse(readFileSync(STATE_FILE, "utf-8"));
    return {
      harvestedPaths: Array.isArray(parsed.harvestedPaths) ? parsed.harvestedPaths : [],
      lastHarvest: parsed.lastHarvest || null,
      totalHarvested: Number(parsed.totalHarvested) || 0,
    };
  } catch {
    return { harvestedPaths: [], lastHarvest: null, totalHarvested: 0 };
  }
}

function writeState(state: ReturnType<typeof readState>) {
  mkdirSync(dirname(STATE_FILE), { recursive: true });
  writeFileSync(STATE_FILE, `${JSON.stringify(state, null, 2)}\n`, "utf-8");
}

function walk(dir: string, predicate: (path: string) => boolean): string[] {
  if (!existsSync(dir)) return [];
  const out: string[] = [];
  const visit = (current: string) => {
    for (const entry of readdirSync(current, { withFileTypes: true })) {
      const full = join(current, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === "node_modules" || entry.name === ".git" || entry.name.startsWith("_")) continue;
        visit(full);
      } else if (entry.isFile() && predicate(full)) {
        out.push(full);
      }
    }
  };
  visit(dir);
  return out.sort();
}

function tagsFromText(text: string): string[] {
  const tags = new Set<string>();
  const fm = splitFrontmatter(text).frontmatter;
  const inline = fm.match(/^tags:\s*\[([^\]]*)\]/im)?.[1];
  if (inline) {
    for (const tag of inline.split(",")) {
      const cleaned = slugify(tag.replace(/["']/g, ""));
      if (cleaned) tags.add(cleaned);
    }
  }
  for (const keyword of ["memory", "architecture", "research", "security", "decision", "preference", "problem", "milestone"]) {
    if (text.toLowerCase().includes(keyword)) tags.add(keyword);
  }
  return [...tags].slice(0, 8);
}

function classifyDomain(text: string): Candidate["domain"] {
  const lower = text.toLowerCase();
  if (/\b(person|profile|contact|linkedin|biography)\b/.test(lower)) return "People";
  if (/\b(company|startup|organization|revenue|employees|founded)\b/.test(lower)) return "Companies";
  if (/\b(research|methodology|findings|investigation|sources?)\b/.test(lower)) return "Research";
  return "Ideas";
}

function typeFor(domain: string): Candidate["type"] {
  if (domain === "People") return "person";
  if (domain === "Companies") return "company";
  if (domain === "Research") return "research";
  return "idea";
}

function extractSection(content: string, heading: string): string | null {
  const match = content.match(new RegExp(`^## ${heading}\\s*\\n([\\s\\S]*?)(?=\\n## |$)`, "im"));
  return match ? match[1].trim() : null;
}

function scanQueue(state: ReturnType<typeof readState>): Candidate[] {
  if (!existsSync(QUEUE_DIR)) return [];
  const candidates: Candidate[] = [];
  for (const file of readdirSync(QUEUE_DIR)) {
    if (!file.endsWith(".json")) continue;
    const path = join(QUEUE_DIR, file);
    if (state.harvestedPaths.includes(path)) continue;
    try {
      const data = JSON.parse(readFileSync(path, "utf-8"));
      const domain = DOMAINS.includes(data.domain) ? data.domain : "Ideas";
      candidates.push({
        sourcePath: path,
        title: data.title || file.replace(/\.json$/, ""),
        content: data.content || "",
        domain,
        type: data.type || typeFor(domain),
        tags: Array.isArray(data.tags) ? data.tags.map(slugify).filter(Boolean) : [],
      });
    } catch {
      // ignore malformed queue candidates
    }
  }
  return candidates;
}

function scanWork(state: ReturnType<typeof readState>): Candidate[] {
  return walk(WORK_DIR, (path) => /\/ISA\.md$/i.test(path))
    .filter((path) => !state.harvestedPaths.includes(path))
    .flatMap((path) => {
      const content = readFileSync(path, "utf-8");
      const phase = yamlScalar(content, "phase") || yamlScalar(content, "status") || "";
      if (!/complete|learn|completed/i.test(phase)) return [];
      const decisions = extractSection(content, "Decisions");
      const verification = extractSection(content, "Verification");
      const changelog = extractSection(content, "Changelog");
      const body = [decisions, verification, changelog].filter(Boolean).join("\n\n").trim();
      if (!body) return [];
      const title = yamlScalar(content, "title") || yamlScalar(content, "task") || basename(dirname(path));
      const domain = classifyDomain(content);
      return [{
        sourcePath: path,
        title,
        content: body,
        domain,
        type: typeFor(domain),
        tags: tagsFromText(content),
      }];
    });
}

function scanResearch(state: ReturnType<typeof readState>): Candidate[] {
  return walk(RESEARCH_DIR, (path) => path.endsWith(".md"))
    .filter((path) => !state.harvestedPaths.includes(path))
    .flatMap((path) => {
      const content = readFileSync(path, "utf-8");
      if (content.trim().length < 120) return [];
      const domain = classifyDomain(content);
      return [{
        sourcePath: path,
        title: yamlScalar(content, "title") || basename(path, ".md").replace(/[_-]/g, " "),
        content: splitFrontmatter(content).body.slice(0, 6000),
        domain,
        type: typeFor(domain),
        tags: tagsFromText(content),
      }];
    });
}

function writeNote(candidate: Candidate): string {
  const domain = DOMAINS.includes(candidate.domain) ? candidate.domain : "Ideas";
  const dir = join(KNOWLEDGE_DIR, domain);
  mkdirSync(dir, { recursive: true });
  const path = join(dir, `${slugify(candidate.title)}.md`);
  if (existsSync(path)) return path;
  const today = new Date().toISOString().slice(0, 10);
  writeFileSync(path, `---
title: "${candidate.title.replace(/"/g, '\\"')}"
slug: ${slugify(candidate.title)}
type: ${candidate.type}
domain: ${domain.toLowerCase()}
tags: [${candidate.tags.map(slugify).filter(Boolean).join(", ")}]
created: ${today}
updated: ${today}
harvested_from: ${candidate.sourcePath}
---

# ${candidate.title}

${candidate.content}
`, "utf-8");
  return path;
}

function domainIndex(domain: string, notes: ReturnType<typeof readKnowledgeNotes>): string {
  const today = new Date().toISOString().slice(0, 10);
  const domainNotes = notes.filter((note) => note.domain.toLowerCase() === domain.toLowerCase());
  const recent = [...domainNotes].sort((a, b) => String(b.updated || "").localeCompare(String(a.updated || ""))).slice(0, 20);
  const byTag = new Map<string, string[]>();
  for (const note of domainNotes) {
    for (const tag of note.tags) {
      byTag.set(tag, [...(byTag.get(tag) || []), note.slug]);
    }
  }
  const tagLines = [...byTag.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([tag, slugs]) => `- ${tag}: ${slugs.map((slug) => `[[${slug}]]`).join(", ")}`)
    .join("\n");

  return `---
title: "${domain}"
type: moc
domain: ${domain.toLowerCase()}
updated: ${today}
---

# ${domain}

## Recently Updated
${recent.map((note) => `- [[${note.slug}]] - ${note.title}`).join("\n") || "- (none)"}

## By Tag
${tagLines || "- (none)"}

---
Auto-generated by KnowledgeHarvester. ${domainNotes.length} note(s).
`;
}

function writeIndexes() {
  for (const domain of DOMAINS) mkdirSync(join(KNOWLEDGE_DIR, domain), { recursive: true });
  const notes = readKnowledgeNotes(KNOWLEDGE_DIR);
  for (const domain of DOMAINS) {
    writeFileSync(join(KNOWLEDGE_DIR, domain, "_index.md"), domainIndex(domain, notes), "utf-8");
  }
  const today = new Date().toISOString().slice(0, 10);
  const counts = DOMAINS.map((domain) => ({ domain, count: notes.filter((note) => note.domain.toLowerCase() === domain.toLowerCase()).length }));
  writeFileSync(join(KNOWLEDGE_DIR, "_index.md"), `---
title: "Knowledge Archive"
type: moc
domain: root
updated: ${today}
---

# Knowledge Archive

| Domain | Notes |
|---|---:|
${counts.map((item) => `| [[${item.domain}/_index|${item.domain}]] | ${item.count} |`).join("\n")}

Total notes: ${notes.length}
`, "utf-8");
  return { notes: notes.length, domains: counts };
}

function status() {
  const notes = readKnowledgeNotes(KNOWLEDGE_DIR);
  const graph = buildKnowledgeGraph(notes);
  const state = readState();
  const byDomain: Record<string, number> = {};
  const byType: Record<string, number> = {};
  for (const note of notes) {
    byDomain[note.domain] = (byDomain[note.domain] || 0) + 1;
    byType[note.type] = (byType[note.type] || 0) + 1;
  }
  return {
    status: notes.length > 0 ? "ok" : "empty_archive",
    total_notes: notes.length,
    by_domain: byDomain,
    by_type: byType,
    edges: graph.edges.length,
    missing_links: graph.missingTargets.map((edge) => ({ source: edge.source, target: edge.target, type: edge.type })),
    last_harvest: state.lastHarvest,
    total_harvested: state.totalHarvested,
  };
}

function validate() {
  const failures: Array<{ file: string; message: string }> = [];
  const files = walk(KNOWLEDGE_DIR, (path) => path.endsWith(".md") && !basename(path).startsWith("_"));
  for (const file of files) {
    const content = readFileSync(file, "utf-8");
    const { frontmatter, body } = splitFrontmatter(content);
    if (!frontmatter) failures.push({ file: relative(KNOWLEDGE_DIR, file), message: "missing frontmatter" });
    if (!yamlScalar(content, "title")) failures.push({ file: relative(KNOWLEDGE_DIR, file), message: "missing title" });
    if (!yamlScalar(content, "type")) failures.push({ file: relative(KNOWLEDGE_DIR, file), message: "missing type" });
    if (body.trim().length < 20) failures.push({ file: relative(KNOWLEDGE_DIR, file), message: "body too short" });
  }
  const graph = buildKnowledgeGraph(readKnowledgeNotes(KNOWLEDGE_DIR));
  for (const edge of graph.missingTargets) {
    failures.push({ file: edge.source, message: `missing link target: ${edge.target}` });
  }
  return { status: failures.length === 0 ? "pass" : "fail", checked: files.length, failures };
}

function contradictions() {
  const notes = readKnowledgeNotes(KNOWLEDGE_DIR);
  const pairs: Array<{
    a: { slug: string; title: string; domain: string };
    b: { slug: string; title: string; domain: string };
    shared_tags: string[];
  }> = [];

  for (let i = 0; i < notes.length; i++) {
    for (let j = i + 1; j < notes.length; j++) {
      const shared = notes[i].tags.filter((tag) => notes[j].tags.includes(tag));
      if (shared.length < 2) continue;
      pairs.push({
        a: { slug: notes[i].slug, title: notes[i].title, domain: notes[i].domain },
        b: { slug: notes[j].slug, title: notes[j].title, domain: notes[j].domain },
        shared_tags: shared,
      });
    }
  }

  pairs.sort((a, b) => b.shared_tags.length - a.shared_tags.length);
  return { status: "ok", pairs: pairs.slice(0, 50), total_pairs: pairs.length };
}

function harvest(source: string | undefined, dryRun: boolean, limit: number) {
  const state = readState();
  let candidates: Candidate[] = [];
  if (!source || source === "queue") candidates.push(...scanQueue(state));
  if (!source || source === "work") candidates.push(...scanWork(state));
  if (!source || source === "research") candidates.push(...scanResearch(state));

  const seen = new Set<string>();
  candidates = candidates
    .filter((candidate) => {
      const key = `${candidate.domain}/${slugify(candidate.title)}`;
      if (seen.has(key) || state.harvestedPaths.includes(candidate.sourcePath)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, limit);

  const written = dryRun ? [] : candidates.map((candidate) => {
    const path = writeNote(candidate);
    if (candidate.sourcePath.startsWith(QUEUE_DIR) && existsSync(candidate.sourcePath)) {
      // W2.12: never destroy the source — move processed queue items aside so a
      // bad harvest is reversible (the old unlinkSync deleted them outright).
      const processedDir = join(QUEUE_DIR, ".processed");
      mkdirSync(processedDir, { recursive: true });
      renameSync(candidate.sourcePath, join(processedDir, basename(candidate.sourcePath)));
    }
    state.harvestedPaths.push(candidate.sourcePath);
    state.totalHarvested++;
    return path;
  });

  if (!dryRun && written.length > 0) {
    state.lastHarvest = new Date().toISOString();
    writeState(state);
    writeIndexes();
  }

  return { status: "ok", dry_run: dryRun, source: source || "all", candidates, written };
}

const { values, positionals } = parseArgs({
  args: process.argv.slice(2),
  options: {
    source: { type: "string", short: "s" },
    "dry-run": { type: "boolean" },
    limit: { type: "string", short: "n" },
    json: { type: "boolean" },
    help: { type: "boolean", short: "h" },
  },
  allowPositionals: true,
});

if (values.help) {
  console.log(`Usage:
  bun PAI/TOOLS/KnowledgeHarvester.ts status [--json]
  bun PAI/TOOLS/KnowledgeHarvester.ts validate [--json]
  bun PAI/TOOLS/KnowledgeHarvester.ts index [--json]
  bun PAI/TOOLS/KnowledgeHarvester.ts contradictions [--json]
  bun PAI/TOOLS/KnowledgeHarvester.ts harvest [--source queue|work|research] [--dry-run] [--json]`);
  process.exit(0);
}

const command = positionals[0] || "status";
const json = Boolean(values.json);

if (command === "status") {
  print(status(), json);
} else if (command === "validate") {
  const result = validate();
  print(result, json);
  process.exit(result.status === "pass" ? 0 : 1);
} else if (command === "index") {
  mkdirSync(KNOWLEDGE_DIR, { recursive: true });
  print({ status: "ok", ...writeIndexes() }, json);
} else if (command === "contradictions") {
  print(contradictions(), json);
} else if (command === "harvest") {
  mkdirSync(KNOWLEDGE_DIR, { recursive: true });
  print(harvest(values.source, Boolean(values["dry-run"]), values.limit ? Number(values.limit) : 5), json);
} else {
  console.error(`Unknown command: ${command}`);
  process.exit(1);
}
