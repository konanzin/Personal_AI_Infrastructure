import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";

const repoRoot = fileURLToPath(new URL("../..", import.meta.url));
const sessionHarvester = join(repoRoot, "PAI", "TOOLS", "SessionHarvester.ts");
const knowledgeHarvester = join(repoRoot, "PAI", "TOOLS", "KnowledgeHarvester.ts");

function tempPaiDir() {
  return mkdtempSync(join(tmpdir(), "pai-harvesters-"));
}

function write(path: string, content: string) {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, content, "utf-8");
}

function runTool(path: string, paiDir: string, args: string[]) {
  return Bun.spawnSync({
    cmd: ["bun", path, ...args],
    env: { ...process.env, PAI_DIR: paiDir },
    stdout: "pipe",
    stderr: "pipe",
  });
}

function json(result: ReturnType<typeof runTool>) {
  const text = `${result.stdout.toString()}${result.stderr.toString()}`.trim();
  return JSON.parse(text);
}

describe("SessionHarvester", () => {
  test("reports no sessions without failing", () => {
    const paiDir = tempPaiDir();
    const sessionsDir = join(paiDir, "empty-sessions");
    mkdirSync(sessionsDir, { recursive: true });

    const result = runTool(sessionHarvester, paiDir, ["--sessions-dir", sessionsDir, "--json"]);

    expect(result.exitCode).toBe(0);
    expect(json(result).status).toBe("no_sessions");
  });

  test("mines session decisions in dry-run mode", () => {
    const paiDir = tempPaiDir();
    const sessionsDir = join(paiDir, "sessions");
    write(join(sessionsDir, "session-1.jsonl"), [
      JSON.stringify({
        type: "user",
        timestamp: "2026-01-01T00:00:00.000Z",
        message: { role: "user", content: "We decided to use the OpenCode-native checkpoint path for this port." },
      }),
    ].join("\n"));

    const result = runTool(sessionHarvester, paiDir, ["--sessions-dir", sessionsDir, "--mine", "--dry-run", "--json"]);

    expect(result.exitCode).toBe(0);
    const output = json(result);
    expect(output.status).toBe("ok");
    expect(output.candidates[0].memoryType).toBe("decision");
    expect(output.written).toEqual([]);
  });

  test("queues mined candidates for review when not dry-run", () => {
    const paiDir = tempPaiDir();
    const sessionsDir = join(paiDir, "sessions");
    write(join(sessionsDir, "session-2.jsonl"), [
      JSON.stringify({
        type: "user",
        timestamp: "2026-01-01T00:00:00.000Z",
        message: { role: "user", content: "The rule is never write harvested knowledge directly without review." },
      }),
    ].join("\n"));

    const result = runTool(sessionHarvester, paiDir, ["--sessions-dir", sessionsDir, "--mine", "--json"]);

    expect(result.exitCode).toBe(0);
    const output = json(result);
    expect(output.written.length).toBe(1);
    expect(existsSync(output.written[0])).toBe(true);
  });
});

describe("KnowledgeHarvester", () => {
  test("status handles an empty archive", () => {
    const paiDir = tempPaiDir();
    const result = runTool(knowledgeHarvester, paiDir, ["status", "--json"]);

    expect(result.exitCode).toBe(0);
    expect(json(result).status).toBe("empty_archive");
  });

  test("index regenerates domain and root MOCs", () => {
    const paiDir = tempPaiDir();
    write(join(paiDir, "MEMORY", "KNOWLEDGE", "Ideas", "checkpoint-port.md"), `---
title: Checkpoint Port
slug: checkpoint-port
type: idea
tags: [checkpoint, opencode]
updated: 2026-01-01
---

The OpenCode checkpoint port uses an allowlist and preview-only rollback.
`);

    const result = runTool(knowledgeHarvester, paiDir, ["index", "--json"]);

    expect(result.exitCode).toBe(0);
    expect(json(result).status).toBe("ok");
    expect(readFileSync(join(paiDir, "MEMORY", "KNOWLEDGE", "_index.md"), "utf-8")).toContain("Knowledge Archive");
    expect(readFileSync(join(paiDir, "MEMORY", "KNOWLEDGE", "Ideas", "_index.md"), "utf-8")).toContain("[[checkpoint-port]]");
  });

  test("validate catches malformed notes and passes valid notes", () => {
    const validPai = tempPaiDir();
    write(join(validPai, "MEMORY", "KNOWLEDGE", "Ideas", "valid.md"), `---
title: Valid Note
slug: valid
type: idea
tags: [valid]
---

This note has enough body content to pass validation.
`);

    const pass = runTool(knowledgeHarvester, validPai, ["validate", "--json"]);
    expect(pass.exitCode).toBe(0);
    expect(json(pass).status).toBe("pass");

    const invalidPai = tempPaiDir();
    write(join(invalidPai, "MEMORY", "KNOWLEDGE", "Ideas", "invalid.md"), "# Missing frontmatter\n");

    const fail = runTool(knowledgeHarvester, invalidPai, ["validate", "--json"]);
    expect(fail.exitCode).toBe(1);
    expect(json(fail).status).toBe("fail");
  });

  test("harvest consumes review queue into Ideas note", () => {
    const paiDir = tempPaiDir();
    const queue = join(paiDir, "MEMORY", "KNOWLEDGE", "_harvest-queue");
    write(join(queue, "candidate.json"), JSON.stringify({
      title: "Review Queue Candidate",
      content: "A queued memory candidate should become a knowledge note after review.",
      domain: "Ideas",
      type: "idea",
      tags: ["queue"],
    }));

    const result = runTool(knowledgeHarvester, paiDir, ["harvest", "--source", "queue", "--json"]);

    expect(result.exitCode).toBe(0);
    const output = json(result);
    expect(output.written.length).toBe(1);
    expect(existsSync(join(paiDir, "MEMORY", "KNOWLEDGE", "Ideas", "review-queue-candidate.md"))).toBe(true);
    expect(readdirSync(queue).length).toBe(0);
  });

  test("contradictions lists high tag-overlap pairs", () => {
    const paiDir = tempPaiDir();
    write(join(paiDir, "MEMORY", "KNOWLEDGE", "Ideas", "a.md"), `---
title: A
slug: a
type: idea
tags: [security, checkpoint, opencode]
---

First note with enough body content for validation and review.
`);
    write(join(paiDir, "MEMORY", "KNOWLEDGE", "Ideas", "b.md"), `---
title: B
slug: b
type: idea
tags: [security, checkpoint, memory]
---

Second note with overlapping tags that should become a review pair.
`);

    const result = runTool(knowledgeHarvester, paiDir, ["contradictions", "--json"]);

    expect(result.exitCode).toBe(0);
    const output = json(result);
    expect(output.status).toBe("ok");
    expect(output.total_pairs).toBe(1);
    expect(output.pairs[0].shared_tags).toContain("security");
  });
});
