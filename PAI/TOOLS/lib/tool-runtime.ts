import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { dirname, join } from "path";
import { homedir } from "os";

export interface CommandResult {
  code: number;
  stdout: string;
  stderr: string;
  timedOut: boolean;
  durationMs: number;
}

export function getPaiDir(): string {
  return process.env.PAI_DIR || join(homedir(), ".config", "opencode", "PAI");
}

export function ensureDir(path: string) {
  mkdirSync(path, { recursive: true });
}

export function appendJsonl(path: string, data: Record<string, unknown>) {
  ensureDir(dirname(path));
  appendFileSync(path, `${JSON.stringify(data)}\n`, "utf-8");
}

export function appendText(path: string, content: string) {
  ensureDir(dirname(path));
  appendFileSync(path, content, "utf-8");
}

export function writeText(path: string, content: string) {
  ensureDir(dirname(path));
  writeFileSync(path, content, "utf-8");
}

export function readTextIfExists(path: string): string {
  return existsSync(path) ? readFileSync(path, "utf-8") : "";
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function truncate(value: string, max = 500): string {
  return value.length > max ? `${value.slice(0, max)}...[truncated]` : value;
}

export async function readStdin(): Promise<string> {
  return await new Response(Bun.stdin.stream()).text();
}

export function workFile(agent: string, slug: string, name: string): string {
  const safeSlug = slug || "adhoc";
  return join(getPaiDir(), "MEMORY", "WORK", safeSlug, `${agent}-${name}`);
}

export function observabilityFile(name: string): string {
  return join(getPaiDir(), "MEMORY", "OBSERVABILITY", name);
}

export function loadEnvFile(path = join(getPaiDir(), ".env")): Record<string, string> {
  const env: Record<string, string> = {};
  if (!existsSync(path)) return env;
  for (const line of readFileSync(path, "utf-8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const index = trimmed.indexOf("=");
    if (index === -1) continue;
    const key = trimmed.slice(0, index).trim();
    const value = trimmed.slice(index + 1).trim().replace(/^['"]|['"]$/g, "");
    if (key) env[key] = value;
  }
  return env;
}

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`;
}

export async function resolveExecutable(candidates: Array<string | undefined>, disableEnv?: string): Promise<string | null> {
  if (disableEnv && process.env[disableEnv] === "1") return null;

  for (const candidate of candidates) {
    if (!candidate) continue;
    if (candidate.includes("/")) {
      if (existsSync(candidate)) return candidate;
      continue;
    }

    const result = await runCommand("bash", ["-lc", `command -v ${shellQuote(candidate)}`], { timeoutMs: 3000 });
    const resolved = result.stdout.trim().split(/\r?\n/)[0];
    if (result.code === 0 && resolved) return resolved;
  }

  return null;
}

export async function runCommand(
  command: string,
  args: string[],
  options: {
    stdin?: string;
    timeoutMs?: number;
    cwd?: string;
    env?: Record<string, string | undefined>;
  } = {},
): Promise<CommandResult> {
  const started = Date.now();
  const proc = Bun.spawn([command, ...args], {
    stdin: options.stdin === undefined ? "ignore" : "pipe",
    stdout: "pipe",
    stderr: "pipe",
    cwd: options.cwd,
    env: {
      ...process.env,
      ...options.env,
    },
  });

  if (options.stdin !== undefined) {
    proc.stdin.write(options.stdin);
    proc.stdin.end();
  }

  let timedOut = false;
  const timeoutMs = options.timeoutMs ?? 60_000;
  const timer = setTimeout(() => {
    timedOut = true;
    proc.kill();
  }, timeoutMs);

  const [stdout, stderr, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]).finally(() => clearTimeout(timer));

  return {
    code,
    stdout,
    stderr,
    timedOut,
    durationMs: Date.now() - started,
  };
}

export function printJson(data: unknown) {
  console.log(JSON.stringify(data, null, 2));
}
