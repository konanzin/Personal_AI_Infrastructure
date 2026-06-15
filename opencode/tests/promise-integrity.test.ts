import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";

const validatorPath = fileURLToPath(new URL("../bin/validate-promise-integrity.sh", import.meta.url));

function write(path: string, content: string) {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, content, "utf-8");
}

function makeRuntime(overrides: {
  claude?: string;
  algorithm?: string;
  config?: string;
  extraCommand?: string;
  skill?: string;
} = {}) {
  const root = mkdtempSync(join(tmpdir(), "pai-promise-"));

  write(join(root, "PAI/CLAUDE.md"), overrides.claude ?? "# PAI\nOpenCode runtime instructions.\n");
  write(join(root, "PAI/RUNTIME_CONSTITUTION.md"), "Runtime marker: RUNTIME_CONSTITUTION\n");
  write(join(root, "PAI/ALGORITHM/LATEST"), "v-test\n");
  write(join(root, "PAI/ALGORITHM/v-test.md"), overrides.algorithm ?? "# Algorithm\nNo stale promises.\n");
  write(join(root, "PAI/TOOLS/manifest.json"), JSON.stringify({ version: 1, runtime: "opencode", tools: {} }, null, 2));

  write(join(root, "plugins/pai-hooks.js"), [
    "const x = 'RUNTIME_CONSTITUTION.md';",
    "const y = 'tool.execute.before';",
    "const z = 'permission.asked';",
  ].join("\n"));

  write(join(root, "agents/Algorithm.md"), "---\nmode: subagent\n---\nAlgorithm agent.\n");
  write(join(root, "commands/status.md"), "# status\n");
  if (overrides.extraCommand) {
    write(join(root, `commands/${overrides.extraCommand}.md`), `# ${overrides.extraCommand}\n`);
  }
  if (overrides.skill) {
    write(join(root, "skills/TestSkill/SKILL.md"), overrides.skill);
  }

  write(join(root, "opencode.jsonc"), overrides.config ?? `{
  "plugin": ["./plugins/pai-hooks.js"],
  "instructions": ["~/.config/opencode/PAI/CLAUDE.md"],
  "agent": {
    "build": {"prompt": "call pai_notify before final"},
    "build-mobile": {"prompt": "call pai_notify before final"}
  },
  "command": {
    "status": {"agent": "build"},
    "pai": {"agent": "Algorithm"}
  }
}`);

  return root;
}

function runValidator(root: string, extraArgs: string[] = []) {
  return Bun.spawnSync({
    cmd: ["bash", validatorPath, "--root", root, ...extraArgs],
    stdout: "pipe",
    stderr: "pipe",
  });
}

function outputOf(result: ReturnType<typeof runValidator>) {
  return `${result.stdout.toString()}\n${result.stderr.toString()}`;
}

describe("Promise Integrity Validator", () => {
  test("passes a clean runtime", () => {
    const root = makeRuntime();
    const result = runValidator(root);
    expect(result.exitCode).toBe(0);
    expect(outputOf(result)).toContain("PASS");
  });

  test("allows a missing tool when the active instruction has explicit fallback", () => {
    const root = makeRuntime({
      algorithm: "Advisor is unavailable until `PAI/TOOLS/Missing.ts` exists; record unavailable and continue.\n",
    });
    const result = runValidator(root);
    expect(result.exitCode).toBe(0);
  });

  test("fails a missing tool promise without fallback", () => {
    const root = makeRuntime({
      algorithm: "Run `PAI/TOOLS/Missing.ts` for the advisor pass.\n",
    });
    const result = runValidator(root);
    expect(result.exitCode).toBe(1);
    expect(outputOf(result)).toContain("Missing.ts");
  });

  test("fails stale system-prompt authority promises", () => {
    const root = makeRuntime({
      claude: "Constitutional rules are loaded from PAI_SYSTEM_PROMPT.md.\n",
    });
    const result = runValidator(root);
    expect(result.exitCode).toBe(1);
    expect(outputOf(result)).toContain("system-prompt");
  });

  test("fails legacy .claude paths even without a trailing slash", () => {
    const root = makeRuntime({
      claude: "Read ~/.claude for the current runtime instructions.\n",
    });
    const result = runValidator(root);
    expect(result.exitCode).toBe(1);
    expect(outputOf(result)).toContain(".claude");
  });

  test("fails unregistered command files", () => {
    const root = makeRuntime({ extraCommand: "ghost" });
    const result = runValidator(root);
    expect(result.exitCode).toBe(1);
    expect(outputOf(result)).toContain("ghost.md");
  });

  test("fails primary-agent config without pai_notify", () => {
    const root = makeRuntime({
      config: `{
        "plugin": ["./plugins/pai-hooks.js"],
        "instructions": ["~/.config/opencode/PAI/CLAUDE.md"],
        "agent": {
          "build": {"prompt": "no final voice"},
          "build-mobile": {"prompt": "no final voice"}
        },
        "command": {
          "status": {"agent": "build"},
          "pai": {"agent": "Algorithm"}
        }
      }`,
    });
    const result = runValidator(root);
    expect(result.exitCode).toBe(1);
    expect(outputOf(result)).toContain("pai_notify");
  });

  test("skill issues warn by default instead of blocking the runtime", () => {
    const root = makeRuntime({
      skill: "Run `PAI/TOOLS/Ghost.ts` now.\n",
    });
    const result = runValidator(root);
    expect(result.exitCode).toBe(0);
    expect(outputOf(result)).toContain("warnings");
  });
});
