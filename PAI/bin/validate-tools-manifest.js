#!/usr/bin/env bun
import { existsSync, readdirSync, readFileSync, statSync } from "fs";
import { basename, dirname, join, relative, resolve } from "path";
import { fileURLToPath } from "url";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(scriptDir, "..", "..");

let root = process.env.OPENCODE_DIR || join(process.env.HOME || "", ".config", "opencode");
let repoMode = false;
let json = false;

for (let i = 2; i < process.argv.length; i++) {
  const arg = process.argv[i];
  if (arg === "--repo") {
    repoMode = true;
    root = repoRoot;
  } else if (arg === "--root") {
    root = resolve(process.argv[++i] || "");
  } else if (arg === "--json") {
    json = true;
  } else if (arg === "--help" || arg === "-h") {
    console.log(`Usage: validate-tools-manifest.js [--repo] [--root DIR] [--json]

Validates PAI/TOOLS/manifest.json against installed/repo tool files.`);
    process.exit(0);
  } else {
    console.error(`Unknown argument: ${arg}`);
    process.exit(2);
  }
}

root = resolve(root);
repoMode ||= existsSync(join(root, "opencode")) && existsSync(join(root, "PAI"));

const paiDir = join(root, "PAI");
const toolsDir = join(paiDir, "TOOLS");
const manifestPath = join(toolsDir, "manifest.json");
const testRoot = repoMode ? join(root, "opencode", "tests") : join(paiDir, "tests");
const failures = [];
const warnings = [];

function fail(message, file = manifestPath) {
  failures.push({ file: relative(root, file), message });
}

function warn(message, file = manifestPath) {
  warnings.push({ file: relative(root, file), message });
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

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf-8"));
  } catch (error) {
    fail(`Invalid JSON: ${error instanceof Error ? error.message : String(error)}`, path);
    return null;
  }
}

function readAll(files) {
  return files.map((file) => readFileSync(file, "utf-8")).join("\n");
}

if (!existsSync(manifestPath)) {
  fail("PAI/TOOLS/manifest.json missing");
} else {
  const manifest = readJson(manifestPath);
  const tools = manifest?.tools && typeof manifest.tools === "object" ? manifest.tools : null;
  if (!tools) {
    fail("manifest.tools must be an object");
  } else {
    const allowed = new Set(["implemented", "deferred", "optional", "retired"]);
    const declared = new Set(Object.keys(tools));
    const actual = new Set(
      existsSync(toolsDir)
        ? walk(toolsDir, (file) => file.endsWith(".ts") && !file.includes(`${toolsDir}/lib/`)).map((file) => basename(file))
        : [],
    );
    const testsText = readAll(walk(testRoot, (file) => /\.(test|spec)\.ts$/.test(file)));

    for (const [name, meta] of Object.entries(tools)) {
      if (!/^[A-Za-z0-9_.-]+\.ts$/.test(name)) {
        fail(`Invalid tool name: ${name}`);
        continue;
      }

      const status = meta?.status;
      const filePath = join(toolsDir, name);
      if (!allowed.has(status)) {
        fail(`${name}: invalid status ${JSON.stringify(status)}`);
      }

      if (status === "implemented" && !existsSync(filePath)) {
        fail(`${name}: status is implemented but file is missing`, filePath);
      }

      if ((status === "deferred" || status === "optional") && !meta.fallback) {
        fail(`${name}: ${status} tools must document fallback`);
      }

      if (status === "implemented" && !Array.isArray(meta.smoke)) {
        fail(`${name}: implemented tools must list smoke commands`);
      }

      if (status === "implemented" && repoMode && !testsText.includes(name)) {
        warn(`${name}: no direct repo test reference found`);
      }
    }

    for (const file of actual) {
      if (!declared.has(file)) {
        fail(`${file}: exists under PAI/TOOLS but is absent from manifest`, join(toolsDir, file));
      }
    }
  }
}

const result = {
  status: failures.length === 0 ? "pass" : "fail",
  failures,
  warnings,
  root,
};

if (json) {
  console.log(JSON.stringify(result, null, 2));
} else if (failures.length === 0) {
  console.log("PASS: tools manifest checks passed");
  if (warnings.length > 0) console.log(`WARN: ${warnings.length} warning(s)`);
} else {
  console.error("FAIL: tools manifest checks failed");
  for (const item of failures) console.error(`${item.file}: ${item.message}`);
  if (warnings.length > 0) console.error(`WARN: ${warnings.length} warning(s)`);
}

process.exit(failures.length === 0 ? 0 : 1);
