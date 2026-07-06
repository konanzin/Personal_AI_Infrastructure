#!/usr/bin/env bun
// AnvilProgress — model-AGNOSTIC delegate engine for the Anvil agent.
//
// Anvil's value is the ROLE (a second engine, ideally from a different model
// family than the session, holding long context), not any vendor. The engine
// is per-machine configuration, never code (Principal's directive,
// 2026-07-06; previously hardwired to one provider):
//
//   USER/Config/anvil.json:
//     {
//       "baseUrl": "https://api.example.com/v1",   // OpenAI-compatible /chat/completions root
//       "model": "provider-model-id",
//       "apiKeyEnv": "EXAMPLE_API_KEY",            // name of the env var holding the key
//       "temperature": 1,                          // optional; omit to use provider default
//       "maxTokens": 16000                         // optional
//     }
//
//   Env overrides (highest precedence): PAI_ANVIL_BASE_URL, PAI_ANVIL_MODEL,
//   PAI_ANVIL_API_KEY (direct value) or PAI_ANVIL_API_KEY_ENV (var name).
//
// No configuration → structured `unavailable`. Nothing here defaults to any
// provider or model.
import { existsSync, readFileSync } from "fs";
import { join } from "path";
import {
  appendJsonl,
  getPaiDir,
  loadEnvFile,
  nowIso,
  printJson,
  readStdin,
  truncate,
  workFile,
  writeText,
} from "./lib/tool-runtime.ts";

interface Options {
  slug: string;
  model: string | null;
  temperature: number | null;
  maxTokens: number;
  timeoutMs: number;
}

function parseArgs(args: string[]): Options {
  const options: Options = {
    slug: "adhoc",
    model: null,
    temperature: null,
    maxTokens: 16_000,
    timeoutMs: 300_000,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") {
      console.log("Usage: echo PROMPT | bun AnvilProgress.ts --slug SLUG [--model id] [--temperature N] [--max-tokens 16000]");
      console.log("Engine comes from USER/Config/anvil.json (baseUrl/model/apiKeyEnv) or PAI_ANVIL_* env vars.");
      process.exit(0);
    }
    if (arg === "--slug") options.slug = args[++i] || options.slug;
    else if (arg === "--model") options.model = args[++i] || options.model;
    else if (arg === "--temperature") options.temperature = Number(args[++i]);
    else if (arg === "--max-tokens") options.maxTokens = Number(args[++i]);
    else if (arg === "--timeout-ms") options.timeoutMs = Number(args[++i]);
    else {
      console.error(`Unknown option: ${arg}`);
      process.exit(2);
    }
  }

  return options;
}

interface EngineConfig {
  baseUrl: string;
  model: string;
  apiKey: string;
  temperature: number | null;
  maxTokens: number | null;
}

function resolveEngine(options: Options, envFile: Record<string, string>): { engine: EngineConfig | null; reason: string } {
  let file: Record<string, unknown> = {};
  const configPath = join(getPaiDir(), "USER", "Config", "anvil.json");
  if (existsSync(configPath)) {
    try {
      file = JSON.parse(readFileSync(configPath, "utf-8"));
    } catch {
      return { engine: null, reason: `anvil.json is not valid JSON (${configPath})` };
    }
  }

  const baseUrl = process.env.PAI_ANVIL_BASE_URL || (typeof file.baseUrl === "string" ? file.baseUrl : null);
  const model = options.model || process.env.PAI_ANVIL_MODEL || (typeof file.model === "string" ? file.model : null);
  const apiKeyEnv = process.env.PAI_ANVIL_API_KEY_ENV || (typeof file.apiKeyEnv === "string" ? file.apiKeyEnv : null);
  const apiKey =
    process.env.PAI_ANVIL_API_KEY ||
    (apiKeyEnv ? process.env[apiKeyEnv] || envFile[apiKeyEnv] || null : null);

  if (!baseUrl || !model) {
    return { engine: null, reason: "Anvil engine not configured — set baseUrl+model in USER/Config/anvil.json (or PAI_ANVIL_* env)" };
  }
  if (!apiKey) {
    return { engine: null, reason: `Anvil API key not available (${apiKeyEnv ? `env ${apiKeyEnv} unset` : "no apiKeyEnv configured"})` };
  }

  const temperature =
    options.temperature !== null && !Number.isNaN(options.temperature)
      ? options.temperature
      : typeof file.temperature === "number"
        ? file.temperature
        : null;
  const maxTokens = typeof file.maxTokens === "number" ? file.maxTokens : options.maxTokens;

  return { engine: { baseUrl: baseUrl.replace(/\/$/, ""), model, apiKey, temperature, maxTokens }, reason: "" };
}

const options = parseArgs(process.argv.slice(2));
const prompt = (await readStdin()).trim();
const eventsFile = workFile("anvil", options.slug, "events.jsonl");
const finalFile = workFile("anvil", options.slug, "final.txt");
const started = Date.now();
const envFile = loadEnvFile();
const { engine, reason: engineReason } = resolveEngine(options, envFile);

appendJsonl(eventsFile, {
  timestamp: nowIso(),
  event: "anvil_started",
  slug: options.slug,
  model: engine?.model ?? null,
});

if (!engine) {
  const payload = {
    verdict: "unavailable",
    reason: engineReason,
    events_file: eventsFile,
    final_file: finalFile,
    duration_ms: Date.now() - started,
  };
  appendJsonl(eventsFile, { timestamp: nowIso(), event: "anvil_unavailable", reason: payload.reason });
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
  appendJsonl(eventsFile, { timestamp: nowIso(), event: "anvil_failed", reason: payload.reason });
  printJson(payload);
  process.exit(0);
}

const controller = new AbortController();
const timer = setTimeout(() => controller.abort(), options.timeoutMs);

try {
  const body: Record<string, unknown> = {
    model: engine.model,
    max_tokens: engine.maxTokens ?? options.maxTokens,
    messages: [{ role: "user", content: prompt }],
  };
  // Only sent when explicitly configured — reasoning-model providers often
  // enforce their own default and reject or ignore overrides.
  if (engine.temperature !== null) body.temperature = engine.temperature;

  const response = await fetch(`${engine.baseUrl}/chat/completions`, {
    method: "POST",
    signal: controller.signal,
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${engine.apiKey}`,
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  if (!response.ok) {
    const payload = {
      verdict: "fail",
      reason: `Anvil engine API returned HTTP ${response.status}`,
      events_file: eventsFile,
      final_file: finalFile,
      duration_ms: Date.now() - started,
      error: truncate(text, 1000),
    };
    appendJsonl(eventsFile, { timestamp: nowIso(), event: "anvil_failed", reason: payload.reason });
    printJson(payload);
    process.exit(0);
  }

  const parsed = JSON.parse(text);
  const final = parsed?.choices?.[0]?.message?.content || "";
  writeText(finalFile, final);
  const payload = {
    verdict: "ok",
    exit_code: 0,
    events_file: eventsFile,
    final_file: finalFile,
    duration_ms: Date.now() - started,
    final_message: truncate(final, 2000),
  };
  appendJsonl(eventsFile, { timestamp: nowIso(), event: "anvil_completed", duration_ms: payload.duration_ms });
  printJson(payload);
} catch (error) {
  const payload = {
    verdict: error instanceof DOMException && error.name === "AbortError" ? "timeout" : "fail",
    reason: error instanceof Error ? error.message : String(error),
    events_file: eventsFile,
    final_file: finalFile,
    duration_ms: Date.now() - started,
  };
  appendJsonl(eventsFile, { timestamp: nowIso(), event: "anvil_failed", reason: payload.reason });
  printJson(payload);
} finally {
  clearTimeout(timer);
}
