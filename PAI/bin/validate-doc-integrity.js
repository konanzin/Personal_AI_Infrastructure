#!/usr/bin/env bun
import { existsSync, readdirSync, readFileSync, statSync } from "fs";
import { dirname, join, relative, resolve } from "path";
import { fileURLToPath } from "url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..", "..");

let root = process.env.OPENCODE_DIR || join(process.env.HOME || "", ".config", "opencode");
let json = false;
let repoMode = false;

for (let i = 2; i < process.argv.length; i++) {
  const arg = process.argv[i];
  if (arg === "--json") json = true;
  else if (arg === "--repo") {
    repoMode = true;
    root = repoRoot;
  } else if (arg === "--root") {
    root = resolve(process.argv[++i] || "");
  } else if (arg === "--help" || arg === "-h") {
    console.log(`Usage: validate-doc-integrity.js [--repo] [--root DIR] [--json]

Checks active PAI/OpenCode docs and prompts for promises to missing runtime
surfaces. Legacy/reference docs are allowed when clearly marked as such.`);
    process.exit(0);
  } else {
    console.error(`Unknown argument: ${arg}`);
    process.exit(2);
  }
}

root = resolve(root);
repoMode ||= existsSync(join(root, "opencode")) && existsSync(join(root, "PAI"));

const paiDir = repoMode ? join(root, "PAI") : join(root, "PAI");
const opencodeDir = repoMode ? join(root, "opencode") : root;
const failures = [];
const warnings = [];

function read(path) {
  return readFileSync(path, "utf-8");
}

function addFailure(file, line, rule, message) {
  failures.push({ file: relative(root, file), line, rule, message });
}

function addWarning(file, line, rule, message) {
  warnings.push({ file: relative(root, file), line, rule, message });
}

function lineFor(content, index) {
  return content.slice(0, index).split("\n").length;
}

function contextFor(content, index, len = 420) {
  const start = Math.max(0, index - len);
  const end = Math.min(content.length, index + len);
  return content.slice(start, end);
}

function hasAny(text, words) {
  const lower = text.toLowerCase();
  return words.some((word) => lower.includes(word));
}

function isLegacyReference(content, relPath) {
  const header = content.split("\n").slice(0, 16).join("\n").toLowerCase();
  if (relPath.includes("/plans/")) return true;
  if (relPath.includes("PAI_ORIGINAL_TO_OPENCODE_PARITY_AUDIT.md")) return true;
  if (relPath.includes("CHANGELOG")) return true;
  if (relPath.includes("changelog")) return true;
  if (header.includes("legacy/reference material")) return true;
  if (header.includes("legacy desktop pulse docs")) return true;
  return false;
}

function latestAlgorithmPath() {
  const latestPath = join(paiDir, "ALGORITHM", "LATEST");
  if (!existsSync(latestPath)) return null;
  const latest = read(latestPath).trim();
  const target = join(paiDir, "ALGORITHM", `${latest}.md`);
  return existsSync(target) ? target : null;
}

function walk(dir, predicate, out = []) {
  if (!existsSync(dir)) return out;
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      if (["node_modules", ".git", ".next", "out"].includes(entry)) continue;
      walk(full, predicate, out);
    } else if (predicate(full)) {
      out.push(full);
    }
  }
  return out;
}

function collectFiles() {
  const files = new Set();
  const add = (p) => existsSync(p) && files.add(resolve(p));
  const addDir = (dir, exts) => {
    for (const f of walk(dir, (p) => exts.some((ext) => p.endsWith(ext)))) files.add(resolve(f));
  };

  add(join(paiDir, "CLAUDE.md"));
  add(join(paiDir, "RUNTIME_CONSTITUTION.md"));
  const latest = latestAlgorithmPath();
  if (latest) add(latest);
  addDir(join(paiDir, "DOCUMENTATION"), [".md"]);
  addDir(join(paiDir, "PULSE"), [".md", ".toml"]);

  if (repoMode) {
    add(join(opencodeDir, "config", "opencode.jsonc.template"));
    add(join(opencodeDir, "docs", "README-OPENCODE.md"));
    add(join(opencodeDir, "docs", "NOTIFICATIONS_STREAM.md"));
    add(join(opencodeDir, "docs", "OBSERVABILITY_CONTRACTS.md"));
    addDir(join(opencodeDir, "agents"), [".md"]);
    addDir(join(opencodeDir, "commands"), [".md"]);
  } else {
    add(join(opencodeDir, "opencode.jsonc"));
    add(join(opencodeDir, "docs", "README-OPENCODE.md"));
    add(join(opencodeDir, "docs", "NOTIFICATIONS_STREAM.md"));
    add(join(opencodeDir, "docs", "OBSERVABILITY_CONTRACTS.md"));
    addDir(join(opencodeDir, "agents"), [".md"]);
    addDir(join(opencodeDir, "commands"), [".md"]);
  }

  return [...files].sort();
}

const fallbackWords = [
  "optional",
  "deferred",
  "unavailable",
  "if missing",
  "when missing",
  "verify",
  "guard",
  "fallback",
  "not implemented",
  "does not ship",
  "legacy",
  "reference",
  "out of scope",
  "planned",
  "absent",
];

const historicalWords = [
  "legacy",
  "reference",
  "historical",
  "original",
  "upstream",
  "audit",
  "old",
  "not active",
  "no longer",
  "does not ship",
  "out of scope",
  "absent",
  "removed",
  "patch",
  "backward compat",
];

function validateFile(file) {
  const content = read(file);
  const relPath = relative(root, file);
  const legacy = isLegacyReference(content, relPath);

  const checkContextual = (regex, rule, messageFor, allowWords) => {
    for (const match of content.matchAll(regex)) {
      const index = match.index ?? 0;
      const context = contextFor(content, index, 1000);
      if (legacy || hasAny(context, allowWords)) continue;
      const message = messageFor(match);
      if (message) addFailure(file, lineFor(content, index), rule, message);
    }
  };

  checkContextual(
    /(?:~\/\.config\/opencode\/PAI\/|PAI\/)?TOOLS\/([A-Za-z0-9_.-]+\.ts)/g,
    "missing-tool",
    (match) => {
      const tool = match[1];
      const exists = existsSync(join(paiDir, "TOOLS", tool));
      return exists ? null : `References missing PAI tool ${tool} without an explicit optional/deferred fallback.`;
    },
    fallbackWords,
  );

  checkContextual(
    /\b([A-Za-z0-9_.-]+\.hook\.ts)\b/g,
    "missing-hook",
    (match) => {
      const hook = match[1];
      const exists = existsSync(join(paiDir, "hooks", hook));
      return exists ? null : `References missing Claude Code hook ${hook} as active runtime.`;
    },
    historicalWords,
  );

  checkContextual(
    /\bPAI_SYSTEM_PROMPT(?:\.md)?\b/g,
    "missing-system-prompt",
    () => "References PAI_SYSTEM_PROMPT as active authority; OpenCode uses RUNTIME_CONSTITUTION.md and plugin injection.",
    historicalWords,
  );

  checkContextual(
    /(?:~\/|\$HOME\/|\$\{HOME\}\/)?\.claude\b/g,
    "legacy-claude-path",
    () => "References .claude path without marking it as legacy/upstream/backward compatibility.",
    historicalWords,
  );

  checkContextual(
    /~\/\.config\/opencode\/PAI\/PAI\/|PAI\/PAI\//g,
    "duplicated-pai-path",
    () => "References duplicated PAI/PAI path without marking it as legacy.",
    historicalWords,
  );

  if (legacy) {
    addWarning(file, 1, "legacy-doc-skipped", "Document marked legacy/reference; active runtime promises were not enforced inside it.");
  }
}

for (const file of collectFiles()) validateFile(file);

const result = {
  status: failures.length === 0 ? "pass" : "fail",
  failures,
  warnings,
  root,
};

if (json) {
  console.log(JSON.stringify(result, null, 2));
} else if (failures.length === 0) {
  console.log("PASS: doc integrity checks passed");
  if (warnings.length > 0) console.log(`WARN: ${warnings.length} legacy/reference docs skipped`);
} else {
  console.error("FAIL: doc integrity checks failed");
  for (const failure of failures) {
    console.error(`${failure.file}:${failure.line}: ${failure.rule}: ${failure.message}`);
  }
  if (warnings.length > 0) console.error(`WARN: ${warnings.length} legacy/reference docs skipped`);
}

process.exit(failures.length === 0 ? 0 : 1);
