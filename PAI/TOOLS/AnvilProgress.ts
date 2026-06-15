#!/usr/bin/env bun
import {
  appendJsonl,
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
  model: string;
  temperature: number;
  maxTokens: number;
  timeoutMs: number;
}

function parseArgs(args: string[]): Options {
  const options: Options = {
    slug: "adhoc",
    model: "kimi-k2.6",
    temperature: 1,
    maxTokens: 16_000,
    timeoutMs: 300_000,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") {
      console.log("Usage: echo PROMPT | bun AnvilProgress.ts --slug SLUG [--model kimi-k2.6] [--temperature 1] [--max-tokens 16000]");
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

const options = parseArgs(process.argv.slice(2));
const prompt = (await readStdin()).trim();
const eventsFile = workFile("anvil", options.slug, "events.jsonl");
const finalFile = workFile("anvil", options.slug, "final.txt");
const started = Date.now();
const envFile = loadEnvFile();
const apiKey = process.env.MOONSHOT_API_KEY || envFile.MOONSHOT_API_KEY;

appendJsonl(eventsFile, {
  timestamp: nowIso(),
  event: "anvil_started",
  slug: options.slug,
  model: options.model,
});

if (!apiKey) {
  const payload = {
    verdict: "unavailable",
    reason: "MOONSHOT_API_KEY not set",
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
  const response = await fetch("https://api.moonshot.ai/v1/chat/completions", {
    method: "POST",
    signal: controller.signal,
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: options.model,
      temperature: options.temperature,
      max_tokens: options.maxTokens,
      messages: [{ role: "user", content: prompt }],
    }),
  });

  const text = await response.text();
  if (!response.ok) {
    const payload = {
      verdict: "fail",
      reason: `Moonshot API returned HTTP ${response.status}`,
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
