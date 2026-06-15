import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const checkpointTool = join(repoRoot, "PAI", "TOOLS", "Checkpoint.ts");

function tempDir(prefix: string) {
  return mkdtempSync(join(tmpdir(), prefix));
}

function write(path: string, content: string) {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, content, "utf-8");
}

function run(cmd: string[], cwd?: string, env: Record<string, string> = {}) {
  const result = Bun.spawnSync({
    cmd,
    cwd,
    env: { ...process.env, ...env },
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0) {
    throw new Error(`${cmd.join(" ")} failed\n${result.stdout}\n${result.stderr}`);
  }
  return result.stdout.toString();
}

async function loadLib(paiDir: string) {
  process.env.PAI_DIR = paiDir;
  return await import(`../plugins/lib/pai-hooks.lib.js?checkpoint=${Date.now()}-${Math.random()}`);
}

function createGitRepo() {
  const repo = tempDir("pai-checkpoint-repo-");
  run(["git", "init"], repo);
  run(["git", "config", "user.email", "pai@example.test"], repo);
  run(["git", "config", "user.name", "PAI Test"], repo);
  write(join(repo, "note.txt"), "initial\n");
  run(["git", "add", "note.txt"], repo);
  run(["git", "commit", "-m", "initial"], repo);
  write(join(repo, "note.txt"), "changed\n");
  return repo;
}

describe("CheckpointPerISC runtime", () => {
  test("parses completed ISC criteria", async () => {
    const paiDir = tempDir("pai-checkpoint-parse-");
    const lib = await loadLib(paiDir);
    const criteria = lib.parseCriteriaList([
      "- [ ] ISC-1: open criterion",
      "- [x] ISC-2: completed criterion",
      "- [X] [A] ISC-3-A-1: completed anti criterion",
    ].join("\n"));

    expect(criteria.map((item: { id: string }) => item.id)).toEqual(["ISC-1", "ISC-2", "ISC-3-A-1"]);
    expect(criteria.filter((item: { status: string }) => item.status === "completed").length).toBe(2);
  });

  test("skips checkpoint commits when allowlist is absent", async () => {
    const paiDir = tempDir("pai-checkpoint-no-allowlist-");
    const lib = await loadLib(paiDir);
    const slug = "no-allowlist";
    const isaPath = join(paiDir, "MEMORY", "WORK", slug, "ISA.md");
    write(isaPath, "---\nphase: execute\n---\n\n## Criteria\n- [x] ISC-1: finish one thing\n");

    const result = lib.recordISCCheckpointsFromISA(isaPath, { sessionId: "s1" });

    expect(result.status).toBe("skipped");
    expect(result.reason).toBe("no_checkpoint_repos_configured");
    expect(existsSync(join(paiDir, "MEMORY", "WORK", slug, ".checkpoint-state.json"))).toBe(false);
  });

  test("commits dirty allowlisted repos once and records sidecar state", async () => {
    const paiDir = tempDir("pai-checkpoint-record-");
    const repo = createGitRepo();
    write(join(paiDir, "checkpoint-repos.txt"), `${repo}\n`);

    const lib = await loadLib(paiDir);
    const slug = "recorded-task";
    const isaPath = join(paiDir, "MEMORY", "WORK", slug, "ISA.md");
    write(isaPath, "---\nphase: execute\n---\n\n## Criteria\n- [x] ISC-1: save dirty work\n");

    const result = lib.recordISCCheckpointsFromISA(isaPath, { sessionId: "s1" });
    expect(result.status).toBe("ok");
    expect(result.checkpoints[0].repos[0].status).toBe("committed");

    const log = run(["git", "log", "--oneline", "-1"], repo);
    expect(log).toContain("ISC-1 (recorded-task): save dirty work");

    write(join(repo, "note.txt"), "changed again\n");
    const second = lib.recordISCCheckpointsFromISA(isaPath, { sessionId: "s1" });
    expect(second.status).toBe("noop");

    const statePath = join(paiDir, "MEMORY", "WORK", slug, ".checkpoint-state.json");
    const state = JSON.parse(readFileSync(statePath, "utf-8"));
    expect(state.committed_iscs).toEqual(["ISC-1"]);
  });

  test("Checkpoint CLI lists and previews rollback without executing it", async () => {
    const paiDir = tempDir("pai-checkpoint-cli-");
    const slug = "cli-task";
    write(join(paiDir, "MEMORY", "WORK", slug, ".checkpoint-state.json"), JSON.stringify({
      committed_iscs: ["ISC-1"],
      last_commit_sha: { "/tmp/repo": "abc123" },
      entries: [{
        id: "ISC-1",
        slug,
        description: "checkpoint via test",
        timestamp: "2026-01-01T00:00:00.000Z",
        repos: [{ repo: "/tmp/repo", sha: "abc123", status: "committed" }],
      }],
    }, null, 2));

    const list = JSON.parse(run(["bun", checkpointTool, "list", slug, "--json"], undefined, { PAI_DIR: paiDir }));
    expect(list.status).toBe("ok");
    expect(list.committed_iscs).toEqual(["ISC-1"]);

    const rollback = JSON.parse(run(["bun", checkpointTool, "rollback", slug, "ISC-1", "--json"], undefined, { PAI_DIR: paiDir }));
    expect(rollback.status).toBe("preview");
    expect(rollback.destructive_executed).toBe(false);
    expect(rollback.commands[0].command).toContain("reset --hard abc123");
  });
});
