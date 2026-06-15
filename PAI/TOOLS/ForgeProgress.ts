#!/usr/bin/env bun
import {
  appendJsonl,
  appendText,
  nowIso,
  printJson,
  readStdin,
  readTextIfExists,
  resolveExecutable,
  runCommand,
  truncate,
  workFile,
  writeText,
} from "./lib/tool-runtime.ts";

interface Options {
  slug: string;
  model: string;
  reasoningEffort: string;
  sandbox: string;
  timeoutMs: number;
  cwd: string;
}

function parseArgs(args: string[]): Options {
  const options: Options = {
    slug: "adhoc",
    model: "gpt-5.4",
    reasoningEffort: "high",
    sandbox: "workspace-write",
    timeoutMs: 300_000,
    cwd: process.cwd(),
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") {
      console.log("Usage: echo PROMPT | bun ForgeProgress.ts --slug SLUG [--model MODEL] [--reasoning-effort high] [--sandbox workspace-write] [--timeout-ms 300000]");
      process.exit(0);
    }
    if (arg === "--slug") options.slug = args[++i] || options.slug;
    else if (arg === "--model") options.model = args[++i] || options.model;
    else if (arg === "--reasoning-effort") options.reasoningEffort = args[++i] || options.reasoningEffort;
    else if (arg === "--sandbox") options.sandbox = args[++i] || options.sandbox;
    else if (arg === "--timeout-ms") options.timeoutMs = Number(args[++i]) || options.timeoutMs;
    else if (arg === "--cwd" || arg === "--cd") options.cwd = args[++i] || options.cwd;
    else {
      console.error(`Unknown option: ${arg}`);
      process.exit(2);
    }
  }

  return options;
}

const options = parseArgs(process.argv.slice(2));
const prompt = (await readStdin()).trim();
const eventsFile = workFile("forge", options.slug, "events.jsonl");
const finalFile = workFile("forge", options.slug, "final.txt");
const started = Date.now();

appendJsonl(eventsFile, {
  timestamp: nowIso(),
  event: "forge_started",
  slug: options.slug,
  model: options.model,
  reasoning_effort: options.reasoningEffort,
  sandbox: options.sandbox,
});

const codex = await resolveExecutable([
  process.env.CODEX_BIN,
  `${process.env.HOME}/.bun/bin/codex`,
  `${process.env.HOME}/.local/bin/codex`,
  "codex",
], "PAI_DISABLE_CODEX");

if (!codex) {
  const payload = {
    verdict: "unavailable",
    reason: "codex CLI not found in CODEX_BIN, ~/.bun/bin/codex, ~/.local/bin/codex, or PATH",
    events_file: eventsFile,
    final_file: finalFile,
    duration_ms: Date.now() - started,
  };
  appendJsonl(eventsFile, { timestamp: nowIso(), event: "forge_unavailable", reason: payload.reason });
  printJson(payload);
  process.exit(0);
}

if (!prompt) {
  const payload = {
    verdict: "fail",
    reason: "empty prompt on stdin",
    events_file: eventsFile,
    final_file: finalFile,
    duration_ms: Date.now() - started,
  };
  appendJsonl(eventsFile, { timestamp: nowIso(), event: "forge_failed", reason: payload.reason });
  printJson(payload);
  process.exit(0);
}

const result = await runCommand(codex, [
  "exec",
  "--json",
  "--model",
  options.model,
  "-c",
  `model_reasoning_effort="${options.reasoningEffort}"`,
  "--sandbox",
  options.sandbox,
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

if (result.stdout.trim()) appendText(eventsFile, `${result.stdout.trim()}\n`);
if (result.stderr.trim()) {
  appendJsonl(eventsFile, {
    timestamp: nowIso(),
    event: "forge_stderr",
    message: truncate(result.stderr.trim(), 1000),
  });
}

const finalMessage = readTextIfExists(finalFile).trim();
const payload = {
  verdict: result.timedOut ? "timeout" : result.code === 0 ? "ok" : "fail",
  exit_code: result.code,
  events_file: eventsFile,
  final_file: finalFile,
  duration_ms: result.durationMs,
  final_message: truncate(finalMessage || result.stdout.trim(), 2000),
  error: result.code === 0 ? undefined : truncate(result.stderr.trim(), 1000),
};

appendJsonl(eventsFile, {
  timestamp: nowIso(),
  event: "forge_completed",
  verdict: payload.verdict,
  exit_code: result.code,
  duration_ms: result.durationMs,
});

printJson(payload);
