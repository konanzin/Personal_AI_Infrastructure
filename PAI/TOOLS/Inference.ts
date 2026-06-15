#!/usr/bin/env bun
import { printJson, runCommand, truncate } from "./lib/tool-runtime.ts";

export type InferenceLevel = "fast" | "standard" | "smart" | "advisor";

export interface InferenceRequest {
  systemPrompt: string;
  userPrompt: string;
  level?: InferenceLevel;
  timeout?: number;
  json?: boolean;
  mode?: string;
}

export interface InferenceResult {
  status: "ok" | "unavailable" | "error" | "timeout";
  success: boolean;
  output: string;
  error?: string;
  code?: number;
  level: InferenceLevel;
  provider: "command-adapter";
}

const unavailableMessage =
  "PAI inference adapter unavailable: set PAI_INFERENCE_CMD or OPENCODE_INFERENCE_CMD to a command that accepts an InferenceRequest JSON object on stdin.";

export async function inference(request: InferenceRequest): Promise<InferenceResult> {
  const command = process.env.PAI_INFERENCE_CMD || process.env.OPENCODE_INFERENCE_CMD;
  const level = request.level || (request.mode === "advisor" ? "advisor" : "standard");

  if (!command) {
    return {
      status: "unavailable",
      success: false,
      output: "",
      error: unavailableMessage,
      level,
      provider: "command-adapter",
    };
  }

  const timeoutMs = request.timeout ?? 60_000;
  const result = await runCommand("bash", ["-lc", command], {
    stdin: JSON.stringify({ ...request, level }),
    timeoutMs,
    env: {
      PAI_INFERENCE_LEVEL: level,
    },
  });

  if (result.timedOut) {
    return {
      status: "timeout",
      success: false,
      output: result.stdout.trim(),
      error: `PAI inference command timed out after ${timeoutMs}ms`,
      code: result.code,
      level,
      provider: "command-adapter",
    };
  }

  if (result.code !== 0) {
    return {
      status: "error",
      success: false,
      output: result.stdout.trim(),
      error: result.stderr.trim() || `PAI inference command exited with code ${result.code}`,
      code: result.code,
      level,
      provider: "command-adapter",
    };
  }

  const text = result.stdout.trim();
  try {
    const parsed = JSON.parse(text) as Partial<InferenceResult>;
    if (typeof parsed.success === "boolean") {
      return {
        status: parsed.success ? "ok" : parsed.status || "error",
        success: parsed.success,
        output: parsed.output ?? "",
        error: parsed.error,
        code: parsed.code ?? result.code,
        level,
        provider: "command-adapter",
      };
    }
  } catch {
    // Plain stdout is a valid adapter response.
  }

  return {
    status: "ok",
    success: true,
    output: text,
    code: result.code,
    level,
    provider: "command-adapter",
  };
}

export async function advisor(systemPrompt: string, userPrompt: string, timeout = 180_000): Promise<InferenceResult> {
  return inference({ systemPrompt, userPrompt, level: "advisor", timeout });
}

function usage(): never {
  console.log(`Inference - OpenCode-native PAI inference adapter

Usage:
  bun Inference.ts [--level fast|standard|smart|advisor] [--timeout MS] [--json] "system" "user"
  bun Inference.ts --mode advisor --json "system" "user"

The adapter is provider-neutral. Set PAI_INFERENCE_CMD or OPENCODE_INFERENCE_CMD
to a command that accepts the request JSON on stdin and returns plain text or an
InferenceResult JSON object.`);
  process.exit(0);
}

function parseCli(args: string[]) {
  let level: InferenceLevel = "standard";
  let timeout = 60_000;
  let json = false;
  const positional: string[] = [];

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") usage();
    if (arg === "--level") {
      level = args[++i] as InferenceLevel;
    } else if (arg === "--mode") {
      const mode = args[++i];
      if (mode === "advisor") level = "advisor";
    } else if (arg === "--timeout") {
      timeout = Number(args[++i]);
    } else if (arg === "--json") {
      json = true;
    } else if (arg.startsWith("--")) {
      console.error(`Unknown option: ${arg}`);
      process.exit(2);
    } else {
      positional.push(arg);
    }
  }

  if (!["fast", "standard", "smart", "advisor"].includes(level)) {
    console.error(`Invalid level: ${level}`);
    process.exit(2);
  }

  if (positional.length < 2) {
    console.error("Expected system and user prompts.");
    process.exit(2);
  }

  return {
    level,
    timeout: Number.isFinite(timeout) && timeout > 0 ? timeout : 60_000,
    json,
    systemPrompt: positional[0],
    userPrompt: positional.slice(1).join(" "),
  };
}

if (import.meta.main) {
  const request = parseCli(process.argv.slice(2));
  const result = await inference(request);
  if (request.json) {
    printJson(result);
  } else if (result.success) {
    console.log(result.output);
  } else {
    console.error(truncate(result.error || "Inference failed"));
  }
  process.exit(result.success || result.status === "unavailable" ? 0 : 1);
}
