import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";
import { captureRelationshipNote } from "../plugins/lib/pai-hooks.lib.js";

const learningTool = fileURLToPath(new URL("../../PAI/TOOLS/LearningPatternSynthesis.ts", import.meta.url));
const relationshipTool = fileURLToPath(new URL("../../PAI/TOOLS/RelationshipReflect.ts", import.meta.url));

function run(path: string, paiDir: string, args: string[]) {
  return Bun.spawnSync({
    cmd: ["bun", path, ...args],
    env: { ...process.env, PAI_DIR: paiDir },
    stdout: "pipe",
    stderr: "pipe",
  });
}

function json(result: ReturnType<typeof run>) {
  const stderr = result.stderr.toString().trim();
  if (stderr) throw new Error(`tool wrote to stderr: ${stderr}`);
  return JSON.parse(result.stdout.toString().trim());
}

function seedRatings(root: string, count: number, rating: number, sentiment: string) {
  mkdirSync(join(root, "MEMORY/LEARNING/SIGNALS"), { recursive: true });
  const lines = [];
  for (let i = 0; i < count; i++) {
    lines.push(JSON.stringify({ timestamp: `2026-06-1${(i % 9) + 1}T10:00:00Z`, rating, sentiment_summary: sentiment }));
  }
  writeFileSync(join(root, "MEMORY/LEARNING/SIGNALS/ratings.jsonl"), lines.join("\n"), "utf-8");
}

describe("LearningPatternSynthesis", () => {
  test("unavailable without a ratings source", () => {
    const root = mkdtempSync(join(tmpdir(), "pai-lps-"));
    expect(json(run(learningTool, root, ["--json"])).status).toBe("unavailable");
  });

  test("no_data below the minimum rating threshold", () => {
    const root = mkdtempSync(join(tmpdir(), "pai-lps-"));
    seedRatings(root, 3, 3, "too slow and incomplete");
    expect(json(run(learningTool, root, ["--all", "--json"])).status).toBe("no_data");
  });

  test("synthesizes patterns from enough ratings (dry-run writes nothing)", () => {
    const root = mkdtempSync(join(tmpdir(), "pai-lps-"));
    seedRatings(root, 6, 3, "took too long and felt incomplete");
    const out = json(run(learningTool, root, ["--all", "--dry-run", "--json"]));
    expect(out.status).toBe("ok");
    expect(out.dry_run).toBe(true);
    expect(out.total_ratings).toBe(6);
    expect(out.filepath).toBeNull();
  });
});

describe("RelationshipReflect", () => {
  test("unavailable when no relationship sources exist", () => {
    const root = mkdtempSync(join(tmpdir(), "pai-rr-"));
    expect(json(run(relationshipTool, root, ["--json", "--dry-run"])).status).toBe("unavailable");
  });

  test("ok (dry-run) when OPINIONS and a relationship note are present", () => {
    const root = mkdtempSync(join(tmpdir(), "pai-rr-"));
    mkdirSync(join(root, "USER"), { recursive: true });
    mkdirSync(join(root, "MEMORY/RELATIONSHIP/2026-06"), { recursive: true });
    writeFileSync(join(root, "USER/OPINIONS.md"), "### Prefers concise answers\n**Confidence:** 0.70\n", "utf-8");
    writeFileSync(join(root, "MEMORY/RELATIONSHIP/2026-06/2026-06-14.md"), "## 14:00\n- O(c=0.75) @principal: prefers concise answers\n", "utf-8");
    const out = json(run(relationshipTool, root, ["--json", "--dry-run"]));
    expect(out.status).toBe("ok");
    expect(out.dry_run).toBe(true);
  });
});

describe("RelationshipMemory capture", () => {
  test("appends a B-note for completed work and skips trivial titles", () => {
    const root = mkdtempSync(join(tmpdir(), "pai-relcap-"));
    process.env.PAI_DIR = root;
    try {
      expect(captureRelationshipNote({ sessionId: "s1", title: "x" }).captured).toBe(false);
      const ok = captureRelationshipNote({ sessionId: "s1", title: "Restore security policy parity", category: "SYSTEM" });
      expect(ok.captured).toBe(true);
      expect(existsSync(ok.file)).toBe(true);
      expect(readFileSync(ok.file, "utf-8")).toContain("completed work — Restore security policy parity");
    } finally {
      delete process.env.PAI_DIR;
    }
  });
});
