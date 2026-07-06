import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const validatorPath = join(repoRoot, "opencode", "bin", "validate-tools-manifest.js");
const toolsDir = join(repoRoot, "PAI", "TOOLS");

const toolPath = {
  Inference: join(toolsDir, "Inference.ts"),
  ForgeProgress: join(toolsDir, "ForgeProgress.ts"),
  AnvilProgress: join(toolsDir, "AnvilProgress.ts"),
  CrossVendorAudit: join(toolsDir, "CrossVendorAudit.ts"),
  Arthur: join(toolsDir, "Arthur.ts"),
};

function write(path: string, content: string) {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, content, "utf-8");
}

function tempPaiDir() {
  return mkdtempSync(join(tmpdir(), "pai-runtime-tools-"));
}

function jsonFrom(result: ReturnType<typeof Bun.spawnSync>) {
  const text = result.stdout.toString().trim() || result.stderr.toString().trim();
  return JSON.parse(text);
}

function withEnv(env: Record<string, string | undefined>) {
  return Object.fromEntries(
    Object.entries({ ...process.env, ...env }).filter((entry): entry is [string, string] => typeof entry[1] === "string"),
  );
}

function runBun(path: string, args: string[], env: Record<string, string | undefined> = {}) {
  return Bun.spawnSync({
    cmd: ["bun", path, ...args],
    env: withEnv(env),
    stdout: "pipe",
    stderr: "pipe",
  });
}

function runWithPrompt(path: string, args: string[], env: Record<string, string | undefined> = {}) {
  return Bun.spawnSync({
    cmd: ["bash", "-lc", `echo prompt | bun '${path.replace(/'/g, "'\\''")}' ${args.join(" ")}`],
    env: withEnv(env),
    stdout: "pipe",
    stderr: "pipe",
  });
}

describe("PAI runtime tools manifest", () => {
  test("repository manifest validates implemented, deferred, and optional tools", () => {
    const result = runBun(validatorPath, ["--repo"]);
    expect(result.exitCode).toBe(0);
    expect(result.stdout.toString()).toContain("PASS");
  });

  test("implemented manifest entries must have files", () => {
    const root = tempPaiDir();
    write(
      join(root, "PAI/TOOLS/manifest.json"),
      JSON.stringify(
        {
          version: 1,
          runtime: "opencode",
          tools: {
            "Ghost.ts": {
              status: "implemented",
              layer: "A",
              required_by: ["test"],
              contract: "missing tool fixture",
              smoke: ["bun PAI/TOOLS/Ghost.ts"],
            },
          },
        },
        null,
        2,
      ),
    );

    const result = runBun(validatorPath, ["--root", root]);
    expect(result.exitCode).toBe(1);
    expect(result.stderr.toString()).toContain("Ghost.ts");
  });
});

describe("PAI runtime tool fallbacks", () => {
  test("Inference returns structured unavailable without an adapter command", () => {
    const result = runBun(toolPath.Inference, ["--json", "--level", "fast", "system", "user"], {
      PAI_DIR: tempPaiDir(),
      PAI_INFERENCE_CMD: undefined,
      OPENCODE_INFERENCE_CMD: undefined,
    });

    expect(result.exitCode).toBe(0);
    const json = jsonFrom(result);
    expect(json.status).toBe("unavailable");
    expect(json.provider).toBe("command-adapter");
  });

  test("ForgeProgress returns unavailable when codex is disabled", () => {
    const result = runWithPrompt(toolPath.ForgeProgress, ["--slug", "smoke"], {
      PAI_DIR: tempPaiDir(),
      PAI_DISABLE_CODEX: "1",
    });

    expect(result.exitCode).toBe(0);
    const json = jsonFrom(result);
    expect(json.verdict).toBe("unavailable");
    expect(json.reason).toContain("codex CLI not found");
  });

  test("AnvilProgress returns unavailable when no engine is configured (model-agnostic)", () => {
    const env = { ...process.env, PAI_DIR: tempPaiDir() };
    // Anvil has no baked-in provider: with no anvil.json and no PAI_ANVIL_*
    // env, it must report unconfigured — never fall back to any vendor.
    delete env.PAI_ANVIL_BASE_URL;
    delete env.PAI_ANVIL_MODEL;
    delete env.PAI_ANVIL_API_KEY;
    delete env.PAI_ANVIL_API_KEY_ENV;
    const result = Bun.spawnSync({
      cmd: ["bash", "-lc", `echo prompt | bun '${toolPath.AnvilProgress}' --slug smoke`],
      env,
      stdout: "pipe",
      stderr: "pipe",
    });

    expect(result.exitCode).toBe(0);
    const json = jsonFrom(result);
    expect(json.verdict).toBe("unavailable");
    expect(json.reason).toContain("not configured");
  });

  test("CrossVendorAudit returns skipped when codex is disabled", () => {
    const result = runBun(toolPath.CrossVendorAudit, ["--slug", "smoke", "--advisor-verdict", "{}"], {
      PAI_DIR: tempPaiDir(),
      PAI_DISABLE_CODEX: "1",
    });

    expect(result.exitCode).toBe(0);
    const json = jsonFrom(result);
    expect(json.verdict).toBe("skipped");
    expect(json.reason).toContain("codex CLI not found");
  });

  test("Arthur exposes credential policy status without raw secrets", () => {
    const result = runBun(toolPath.Arthur, ["status"], {
      PAI_DIR: tempPaiDir(),
    });

    expect(result.exitCode).toBe(0);
    const json = jsonFrom(result);
    expect(json.verdict).toBe("available");
    expect(JSON.stringify(json)).not.toMatch(/API_KEY\s*[:=]\s*["\x27][A-Za-z0-9]/); // no raw secret values
  });
});
