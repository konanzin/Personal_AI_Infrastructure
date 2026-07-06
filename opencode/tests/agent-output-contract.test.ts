/**
 * Agent output-contract drift fence (drift register W2.3).
 *
 * The pai_notify + 🎯 COMPLETED contract is duplicated across the built-in
 * agent files. That duplication is where frozen numbers silently diverge —
 * the audit found a 12-word vs 8-16-word split. Until the contract is
 * rendered from one source (W3.3), this test IS the single source of truth:
 * every agent that carries a COMPLETED line must state the same word cap, and
 * no agent may reintroduce the rigid "STORY EXPLANATION 1-8" scaffold that
 * dictates HOW to narrate rather than WHAT to deliver.
 */
import { describe, test, expect } from "bun:test";
import { readdirSync, readFileSync } from "fs";
import { fileURLToPath } from "url";
import { join } from "path";

const agentsDir = fileURLToPath(new URL("../agents", import.meta.url));
const agentFiles = readdirSync(agentsDir).filter((f) => f.endsWith(".md"));

const withCompleted = agentFiles.filter((f) =>
  readFileSync(join(agentsDir, f), "utf-8").includes("🎯 COMPLETED"),
);

describe("agent output contract — no drift", () => {
  test("there are agents carrying the COMPLETED contract", () => {
    expect(withCompleted.length).toBeGreaterThan(0);
  });

  test.each(withCompleted)("%s states the canonical 12-word cap, never 8-16", (f) => {
    const body = readFileSync(join(agentsDir, f), "utf-8");
    expect(body).not.toContain("8-16 words");
    // Every COMPLETED contract mentions the 12-word cap somewhere in the file.
    expect(body).toContain("12 words");
  });

  test.each(agentFiles)("%s does not reintroduce the rigid STORY 1-8 scaffold", (f) => {
    const body = readFileSync(join(agentsDir, f), "utf-8");
    expect(body).not.toContain("MUST BE A NUMBERED LIST");
    expect(body).not.toMatch(/8\. \[Eighth key point/);
  });
});
