export type InferenceLevel = "fast" | "standard" | "smart";

export interface InferenceRequest {
  systemPrompt: string;
  userPrompt: string;
  level?: InferenceLevel;
  timeout?: number;
  json?: boolean;
}

export interface InferenceResult {
  success: boolean;
  output: string;
  error?: string;
  code?: number;
}

const unavailableMessage =
  "OpenCode inference adapter unavailable: set PAI_INFERENCE_CMD or OPENCODE_INFERENCE_CMD to a command that accepts an InferenceRequest JSON object on stdin.";

function envFileCommand(): string | undefined {
  // Machine config lives in PAI/.env (preserved by the installer).
  const paiDir = process.env.PAI_DIR || `${process.env.HOME}/.config/opencode/PAI`;
  try {
    const text = require("fs").readFileSync(`${paiDir}/.env`, "utf-8") as string;
    for (const line of text.split(/\r?\n/)) {
      const match = line.trim().match(/^(PAI_INFERENCE_CMD|OPENCODE_INFERENCE_CMD)=(.+)$/);
      if (match) return match[2].trim().replace(/^['"]|['"]$/g, "");
    }
  } catch {
    // No .env — adapter stays unavailable.
  }
  return undefined;
}

export async function inference(request: InferenceRequest): Promise<InferenceResult> {
  const command = process.env.PAI_INFERENCE_CMD || process.env.OPENCODE_INFERENCE_CMD || envFileCommand();

  if (!command) {
    return {
      success: false,
      output: "",
      error: unavailableMessage,
    };
  }

  const timeoutMs = request.timeout ?? 60_000;
  const proc = Bun.spawn(["bash", "-lc", command], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: {
      ...process.env,
      PAI_INFERENCE_LEVEL: request.level ?? "standard",
    },
  });

  proc.stdin.write(JSON.stringify(request));
  proc.stdin.end();

  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    proc.kill();
  }, timeoutMs);

  const [stdout, stderr, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]).finally(() => clearTimeout(timer));

  if (timedOut) {
    return {
      success: false,
      output: stdout.trim(),
      error: `OpenCode inference command timed out after ${timeoutMs}ms`,
      code,
    };
  }

  if (code !== 0) {
    return {
      success: false,
      output: stdout.trim(),
      error: stderr.trim() || `OpenCode inference command exited with code ${code}`,
      code,
    };
  }

  const text = stdout.trim();
  try {
    const parsed = JSON.parse(text) as Partial<InferenceResult>;
    if (typeof parsed.success === "boolean") {
      return {
        success: parsed.success,
        output: parsed.output ?? "",
        error: parsed.error,
        code: parsed.code ?? code,
      };
    }
  } catch {
    // Plain stdout is a valid adapter response.
  }

  return {
    success: true,
    output: text,
    code,
  };
}
