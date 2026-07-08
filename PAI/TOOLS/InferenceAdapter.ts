#!/usr/bin/env bun
// The PAI_INFERENCE_CMD adapter: reads an InferenceRequest JSON object on
// stdin (contract in Inference.ts / skills/Lib/OpenCodeInference.ts) and
// writes the engine's completion text to stdout.
//
// Engine is per-machine config, not identity: USER/Config/inference.json may
// name {bin, model}; PAI_INFERENCE_BIN overrides; default is `opencode run
// --pure` so the advisor answers with the session's own configured model
// without re-entering the PAI plugins.
import { getPaiDir, readTextIfExists, runCommand } from "./lib/tool-runtime.ts";
import { join } from "path";

interface EngineConfig {
  bin?: string;
  model?: string;
}

interface AdapterRequest {
  systemPrompt?: string;
  userPrompt?: string;
  level?: string;
  timeout?: number;
  json?: boolean;
}

function readEngineConfig(): EngineConfig {
  const raw = readTextIfExists(join(getPaiDir(), "USER", "Config", "inference.json"));
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return typeof parsed === "object" && parsed !== null ? (parsed as EngineConfig) : {};
  } catch {
    return {};
  }
}

function buildEngineArgs(bin: string, model: string | undefined, prompt: string): string[] {
  const name = bin.split("/").pop() || bin;
  if (name.includes("codex")) {
    return ["exec", ...(model ? ["--model", model] : []), prompt];
  }
  // opencode (default) and anything that follows its `run` shape.
  return ["run", "--pure", ...(model ? ["-m", model] : []), prompt];
}

async function main(): Promise<number> {
  const stdinText = await Bun.stdin.text();
  let request: AdapterRequest = {};
  try {
    request = JSON.parse(stdinText) as AdapterRequest;
  } catch {
    console.error("InferenceAdapter: stdin was not an InferenceRequest JSON object");
    return 2;
  }

  const engineConfig = readEngineConfig();
  const bin = process.env.PAI_INFERENCE_BIN || engineConfig.bin || "opencode";
  const model = process.env.PAI_INFERENCE_MODEL || engineConfig.model;

  const system = (request.systemPrompt || "").trim();
  const user = (request.userPrompt || "").trim();
  if (!user && !system) {
    console.error("InferenceAdapter: request carried no prompts");
    return 2;
  }
  const prompt = [
    system ? `[SYSTEM INSTRUCTIONS]\n${system}` : "",
    user,
    request.json ? "Respond with a single JSON object and nothing else." : "",
  ]
    .filter(Boolean)
    .join("\n\n");

  const timeoutMs = typeof request.timeout === "number" && request.timeout > 0 ? request.timeout : 120_000;
  const result = await runCommand(bin, buildEngineArgs(bin, model, prompt), { timeoutMs });

  if (result.timedOut) {
    console.error(`InferenceAdapter: engine timed out after ${timeoutMs}ms`);
    return 1;
  }
  if (result.code !== 0) {
    console.error(result.stderr.trim() || `InferenceAdapter: engine exited with code ${result.code}`);
    return result.code || 1;
  }

  const text = result.stdout.trim();
  if (!text) {
    console.error("InferenceAdapter: engine returned empty output");
    return 1;
  }
  console.log(text);
  return 0;
}

if (import.meta.main) {
  process.exit(await main());
}
