#!/usr/bin/env bun
import {
  appendJsonl,
  getPaiDir,
  nowIso,
  printJson,
  readTextIfExists,
  resolveExecutable,
  runCommand,
  truncate,
  workFile,
  writeText,
} from "./lib/tool-runtime.ts";
import { mkdirSync } from "fs";
import { join } from "path";

interface CatoEngineConfig {
  bin?: string;
  model?: string;
}

// Engine is per-machine config, not identity: USER/Config/cato.json may name the
// audit CLI and model; defaults preserve the historical codex/gpt-5.4 behavior.
function readEngineConfig(): CatoEngineConfig {
  const raw = readTextIfExists(join(getPaiDir(), "USER", "Config", "cato.json"));
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return typeof parsed === "object" && parsed !== null ? (parsed as CatoEngineConfig) : {};
  } catch {
    return {};
  }
}

function parseArgs(args: string[], engineConfig: CatoEngineConfig) {
  const options = {
    slug: "",
    advisorVerdict: "",
    model: engineConfig.model || "gpt-5.4",
    timeoutMs: 120_000,
    cwd: process.cwd(),
  };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") {
      console.log("Usage: bun CrossVendorAudit.ts --slug SLUG --advisor-verdict JSON_OR_TEXT [--model gpt-5.4]");
      process.exit(0);
    }
    if (arg === "--slug") options.slug = args[++i] || "";
    else if (arg === "--advisor-verdict") options.advisorVerdict = args[++i] || "";
    else if (arg === "--model") options.model = args[++i] || options.model;
    else if (arg === "--timeout-ms") options.timeoutMs = Number(args[++i]) || options.timeoutMs;
    else if (arg === "--cwd" || arg === "--cd") options.cwd = args[++i] || options.cwd;
    else {
      console.error(`Unknown option: ${arg}`);
      process.exit(2);
    }
  }
  return options;
}

function findingsPath() {
  const dir = join(getPaiDir(), "MEMORY", "VERIFICATION");
  mkdirSync(dir, { recursive: true });
  return join(dir, "cato-findings.jsonl");
}

const engineConfig = readEngineConfig();
const options = parseArgs(process.argv.slice(2), engineConfig);
const started = Date.now();
const finalFile = workFile("cato", options.slug || "adhoc", "final.json");
const codex = await resolveExecutable([
  process.env.CATO_BIN,
  engineConfig.bin,
  process.env.CODEX_BIN,
  `${process.env.HOME}/.bun/bin/codex`,
  `${process.env.HOME}/.local/bin/codex`,
  "codex",
], "PAI_DISABLE_CODEX");

const log = (payload: Record<string, unknown>) => {
  appendJsonl(findingsPath(), {
    timestamp: nowIso(),
    slug: options.slug || null,
    ...payload,
  });
};

if (!options.slug) {
  const payload = { verdict: "skipped", reason: "missing --slug" };
  log(payload);
  printJson(payload);
  process.exit(0);
}

if (!codex) {
  const payload = { verdict: "skipped", reason: "audit engine CLI not found (default codex; configure USER/Config/cato.json)" };
  log(payload);
  printJson(payload);
  process.exit(0);
}

const workDir = join(getPaiDir(), "MEMORY", "WORK", options.slug);
const isa = readTextIfExists(join(workDir, "ISA.md")) || readTextIfExists(join(workDir, "PRD.md"));
const toolActivity = readTextIfExists(join(getPaiDir(), "MEMORY", "STATE", "tool-activity.jsonl"))
  .split(/\r?\n/)
  .slice(-200)
  .join("\n");

const prompt = `You are Cato, a read-only cross-vendor verifier.

Return ONLY compact JSON with:
{"verdict":"pass|concerns|fail","criticality":"high|medium|low","findings":[],"blind_spots_surfaced":[],"agrees_with_advisor":"yes|no|partial","model_used":"${options.model}","tokens_used":null,"cost_usd_est":null}

Audit slug: ${options.slug}

Advisor verdict:
${options.advisorVerdict || "(none)"}

ISA:
${truncate(isa || "(ISA not found)", 30000)}

Recent tool activity:
${truncate(toolActivity || "(none)", 20000)}
`;

const result = await runCommand(codex, [
  "exec",
  "--json",
  "--model",
  options.model,
  "--sandbox",
  "read-only",
  "--skip-git-repo-check",
  "--cd",
  options.cwd,
  "-o",
  finalFile,
  "-",
], {
  stdin: prompt,
  timeoutMs: options.timeoutMs,
  cwd: options.cwd,
});

if (result.timedOut || result.code !== 0) {
  const payload = {
    verdict: "skipped",
    reason: result.timedOut ? `codex timed out after ${options.timeoutMs}ms` : truncate(result.stderr || "codex failed", 300),
  };
  log(payload);
  printJson(payload);
  process.exit(0);
}

const finalText = readTextIfExists(finalFile).trim() || result.stdout.trim();
let payload: Record<string, unknown>;
try {
  payload = JSON.parse(finalText);
} catch {
  payload = {
    verdict: "skipped",
    reason: "codex response was not valid JSON",
    raw_response: truncate(finalText, 1000),
  };
}

writeText(finalFile, JSON.stringify(payload, null, 2));
log({ ...payload, duration_ms: Date.now() - started });
printJson(payload);
