import { describe, expect, test } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const validatorPath = join(repoRoot, "opencode", "bin", "validate-doc-integrity.js");

function write(path: string, content: string) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, content, "utf-8");
}

function makeRuntime(overrides: {
  claude?: string;
  doc?: string;
  agent?: string;
} = {}) {
  const root = mkdtempSync(join(tmpdir(), "pai-doc-integrity-"));
  write(join(root, "PAI/CLAUDE.md"), overrides.claude ?? "# PAI\nOpenCode runtime.\n");
  write(join(root, "PAI/RUNTIME_CONSTITUTION.md"), "# Runtime\n");
  write(join(root, "PAI/ALGORITHM/LATEST"), "v-test\n");
  write(join(root, "PAI/ALGORITHM/v-test.md"), "# Algorithm\nNo stale docs.\n");
  write(join(root, "PAI/DOCUMENTATION/Test.md"), overrides.doc ?? "# Doc\nNo stale docs.\n");
  write(join(root, "agents/Test.md"), overrides.agent ?? "---\nmode: subagent\n---\nNo stale docs.\n");
  write(join(root, "commands/test.md"), "# test\n");
  write(join(root, "opencode.jsonc"), "{ \"plugin\": [], \"agent\": {}, \"command\": {} }\n");
  chmodSync(validatorPath, 0o755);
  return root;
}

function runValidator(root: string, args: string[] = []) {
  return Bun.spawnSync({
    cmd: ["bun", validatorPath, "--root", root, ...args],
    stdout: "pipe",
    stderr: "pipe",
  });
}

function outputOf(result: ReturnType<typeof runValidator>) {
  return `${result.stdout.toString()}\n${result.stderr.toString()}`;
}

describe("DocIntegrity validator", () => {
  test("passes a clean minimal OpenCode runtime", () => {
    const root = makeRuntime();
    const result = runValidator(root);
    expect(result.exitCode).toBe(0);
    expect(outputOf(result)).toContain("PASS");
  });

  test("fails missing PAI tool promises without fallback", () => {
    const root = makeRuntime({ doc: "Run `PAI/TOOLS/Ghost.ts` as the active helper.\n" });
    const result = runValidator(root);
    expect(result.exitCode).toBe(1);
    expect(outputOf(result)).toContain("missing-tool");
    expect(outputOf(result)).toContain("Ghost.ts");
  });

  test("allows missing PAI tool references with explicit fallback", () => {
    const root = makeRuntime({
      doc: "`PAI/TOOLS/Ghost.ts` is optional; if missing, report unavailable and continue.\n",
    });
    const result = runValidator(root);
    expect(result.exitCode).toBe(0);
  });

  test("fails missing hook promises as active runtime", () => {
    const root = makeRuntime({ doc: "`Ghost.hook.ts` runs on every prompt.\n" });
    const result = runValidator(root);
    expect(result.exitCode).toBe(1);
    expect(outputOf(result)).toContain("missing-hook");
  });

  test("fails stale system prompt and .claude authority references", () => {
    const root = makeRuntime({
      claude: "Load PAI_SYSTEM_PROMPT.md from ~/.claude as current runtime authority.\n",
    });
    const result = runValidator(root);
    const output = outputOf(result);
    expect(result.exitCode).toBe(1);
    expect(output).toContain("missing-system-prompt");
    expect(output).toContain("legacy-claude-path");
  });

  test("skips clearly marked legacy reference documents", () => {
    const root = makeRuntime({
      doc: [
        "# Old Hooks",
        "",
        "> **legacy/reference material** - original Claude Code notes.",
        "",
        "`Ghost.hook.ts` and `PAI/TOOLS/Ghost.ts` existed upstream.",
      ].join("\n"),
    });
    const result = runValidator(root);
    expect(result.exitCode).toBe(0);
    expect(outputOf(result)).toContain("legacy/reference docs skipped");
  });

  test("passes on the repository's active docs", () => {
    const result = Bun.spawnSync({
      cmd: ["bun", validatorPath, "--repo"],
      stdout: "pipe",
      stderr: "pipe",
    });
    expect(result.exitCode).toBe(0);
  });
});
