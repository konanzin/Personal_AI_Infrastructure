import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";

const telosTool = fileURLToPath(new URL("../../PAI/TOOLS/GenerateTelosSummary.ts", import.meta.url));

function write(path: string, content: string) {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, content, "utf-8");
}

function runTool(root: string, args: string[]) {
  return Bun.spawnSync({
    cmd: ["bun", telosTool, ...args],
    env: { ...process.env, PAI_DIR: root },
    stdout: "pipe",
    stderr: "pipe",
  });
}

function json(result: ReturnType<typeof runTool>) {
  const stderr = result.stderr.toString().trim();
  if (stderr) throw new Error(`tool wrote to stderr: ${stderr}`);
  return JSON.parse(result.stdout.toString().trim());
}

function seedTelos(root: string) {
  write(join(root, "USER/TELOS/MISSION.md"), "- **M0**: Build a Life OS that augments human flourishing.\n");
  write(join(root, "USER/TELOS/GOALS.md"), "- **G9**: Ship OpenCode parity in 2026. Then expand.\n- **G2**: Old deferred goal.\n");
  write(join(root, "USER/TELOS/PROBLEMS.md"), "## P0: Context loss across sessions\n");
}

describe("GenerateTelosSummary", () => {
  test("returns unavailable when core TELOS sources are missing", () => {
    const root = mkdtempSync(join(tmpdir(), "pai-telos-"));
    const result = runTool(root, ["--json"]);
    expect(result.exitCode).toBe(0);
    expect(json(result).status).toBe("unavailable");
  });

  test("dry-run reports ok without writing the summary", () => {
    const root = mkdtempSync(join(tmpdir(), "pai-telos-"));
    seedTelos(root);
    const result = runTool(root, ["--json", "--dry-run"]);
    expect(result.exitCode).toBe(0);
    const out = json(result);
    expect(out.status).toBe("ok");
    expect(out.dry_run).toBe(true);
    expect(existsSync(join(root, "USER/TELOS/PRINCIPAL_TELOS.md"))).toBe(false);
  });

  test("writes a compressed PRINCIPAL_TELOS.md from sources", () => {
    const root = mkdtempSync(join(tmpdir(), "pai-telos-"));
    seedTelos(root);
    const result = runTool(root, ["--json"]);
    expect(result.exitCode).toBe(0);
    expect(json(result).status).toBe("ok");
    const summaryPath = join(root, "USER/TELOS/PRINCIPAL_TELOS.md");
    expect(existsSync(summaryPath)).toBe(true);
    const summary = readFileSync(summaryPath, "utf-8");
    expect(summary).toContain("## Active Goals (2026)");
    expect(summary).toContain("G9");
    // G2 is deferred, compressed to the deferred line rather than a full bullet
    expect(summary).toContain("Deferred");
  });
});
