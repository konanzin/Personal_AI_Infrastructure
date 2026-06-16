import { describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";

const migrateScan = fileURLToPath(new URL("../../PAI/TOOLS/MigrateScan.ts", import.meta.url));
const migrateApprove = fileURLToPath(new URL("../../PAI/TOOLS/MigrateApprove.ts", import.meta.url));
const removeBg = fileURLToPath(new URL("../../PAI/TOOLS/RemoveBg.ts", import.meta.url));

function run(path: string, paiDir: string, args: string[]) {
  return Bun.spawnSync({
    cmd: ["bun", path, ...args],
    env: { ...process.env, PAI_DIR: paiDir },
    stdout: "pipe",
    stderr: "pipe",
  });
}

describe("MigrateScan + MigrateApprove", () => {
  test("scans markdown into proposals and lists them for review", () => {
    const paiDir = mkdtempSync(join(tmpdir(), "pai-migrate-"));
    const notes = join(paiDir, "notes.md");
    writeFileSync(
      notes,
      "## Section A\nSome belief about how I work and what I value when building software.\n\n## Section B\nA concrete goal: ship the OpenCode parity port and document the gaps.\n",
      "utf-8",
    );

    const scan = run(migrateScan, paiDir, ["--source", notes, "--json"]);
    expect(scan.exitCode).toBe(0);
    expect(scan.stderr.toString().trim()).toBe("");
    const out = JSON.parse(scan.stdout.toString().trim());
    expect(Array.isArray(out.proposals)).toBe(true);
    expect(out.proposals.length).toBeGreaterThan(0);

    // The proposals are queued; MigrateApprove --review reads the same queue.
    const review = run(migrateApprove, paiDir, ["--review"]);
    expect(review.exitCode).toBe(0);
    expect(review.stdout.toString()).toContain("pending proposals");
  });

  test("MigrateApprove --review on an empty queue does not fail", () => {
    const paiDir = mkdtempSync(join(tmpdir(), "pai-migrate-"));
    const review = run(migrateApprove, paiDir, ["--review"]);
    expect(review.exitCode).toBe(0);
  });
});

describe("RemoveBg", () => {
  test("--help works without the rembg binary installed", () => {
    const paiDir = mkdtempSync(join(tmpdir(), "pai-removebg-"));
    const help = run(removeBg, paiDir, ["--help"]);
    expect(help.exitCode).toBe(0);
    expect(help.stdout.toString().toLowerCase()).toContain("background");
  });
});
