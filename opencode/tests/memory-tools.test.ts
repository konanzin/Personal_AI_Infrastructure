import { describe, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";

const memoryRetrieverPath = fileURLToPath(new URL("../../PAI/TOOLS/MemoryRetriever.ts", import.meta.url));
const knowledgeGraphPath = fileURLToPath(new URL("../../PAI/TOOLS/KnowledgeGraph.ts", import.meta.url));

function write(path: string, content: string) {
  mkdirSync(join(path, ".."), { recursive: true });
  writeFileSync(path, content, "utf-8");
}

function makePaiRuntime() {
  return mkdtempSync(join(tmpdir(), "pai-memory-tools-"));
}

function seedKnowledge(root: string) {
  write(join(root, "MEMORY/KNOWLEDGE/Ideas/memory-architecture.md"), `---
title: Memory Architecture
type: Ideas
tags: [memory, architecture]
related:
  - slug: retrieval-pattern
    type: extends
quality: 8
---

PAI memory has runtime state, work artifacts, and a knowledge archive.
The retrieval strategy is documented in [[retrieval-pattern]].
`);

  write(join(root, "MEMORY/KNOWLEDGE/Ideas/retrieval-pattern.md"), `---
title: Retrieval Pattern
type: Ideas
tags:
  - memory
  - retrieval
quality: 7
---

BM25 lexical retrieval is the minimum viable search layer for the OpenCode port.
It should return compact context before graph traversal is needed.
`);
}

function runTool(path: string, root: string, args: string[]) {
  return Bun.spawnSync({
    cmd: ["bun", path, ...args],
    env: {
      ...process.env,
      PAI_DIR: root,
    },
    stdout: "pipe",
    stderr: "pipe",
  });
}

function jsonOutput(result: ReturnType<typeof runTool>) {
  const output = `${result.stdout.toString()}${result.stderr.toString()}`;
  return JSON.parse(output);
}

describe("Memory runtime tools", () => {
  test("MemoryRetriever reports empty archive without failing", () => {
    const root = makePaiRuntime();
    const result = runTool(memoryRetrieverPath, root, ["anything", "--json"]);
    expect(result.exitCode).toBe(0);
    const json = jsonOutput(result);
    expect(json.status).toBe("empty_archive");
    expect(json.results).toEqual([]);
  });

  test("MemoryRetriever ranks matching notes with excerpts", () => {
    const root = makePaiRuntime();
    seedKnowledge(root);

    const result = runTool(memoryRetrieverPath, root, ["bm25 retrieval", "--top", "2", "--json"]);
    expect(result.exitCode).toBe(0);
    const json = jsonOutput(result);

    expect(json.status).toBe("ok");
    expect(json.total_notes).toBe(2);
    expect(json.results[0].slug).toBe("retrieval-pattern");
    expect(json.results[0].excerpt.toLowerCase()).toContain("bm25");
  });

  test("KnowledgeGraph builds stats and related traversal", () => {
    const root = makePaiRuntime();
    seedKnowledge(root);

    const statsResult = runTool(knowledgeGraphPath, root, ["stats", "--json"]);
    expect(statsResult.exitCode).toBe(0);
    const stats = jsonOutput(statsResult);
    expect(stats.status).toBe("ok");
    expect(stats.nodes).toBe(2);
    expect(stats.edges).toBeGreaterThanOrEqual(1);

    const relatedResult = runTool(knowledgeGraphPath, root, ["related", "memory-architecture", "--json"]);
    expect(relatedResult.exitCode).toBe(0);
    const related = jsonOutput(relatedResult);
    expect(related.status).toBe("ok");
    expect(related.related.map((note: { slug: string }) => note.slug)).toContain("retrieval-pattern");

    const traverseResult = runTool(knowledgeGraphPath, root, ["traverse", "memory-architecture", "--hops", "2", "--json"]);
    expect(traverseResult.exitCode).toBe(0);
    const traverse = jsonOutput(traverseResult);
    expect(traverse.nodes.map((note: { slug: string }) => note.slug)).toContain("retrieval-pattern");
  });
});
