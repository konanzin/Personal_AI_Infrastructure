/**
 * W2.6 — MEMORY/SKILLS/execution.jsonl is runtime-owned.
 *
 * Unit-tests the emitter and fences the repo against the old pattern: 44
 * skill files used to instruct the MODEL to hand-echo this row (placeholder
 * workflow/summary/duration values — observed live fabricating a 00:00:00
 * timestamp). The runtime hook writes the row now; no prompt surface may
 * teach the echo again.
 */
import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync, statSync, mkdtempSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";
import {
  buildSkillExecutionEvent,
  emitSkillExecution,
  SKILL_EXECUTION_PATH,
} from "../plugins/lib/execution-log.lib.js";

describe("execution-log lib", () => {
  test("builds an ok event with previewed args and rounded duration", () => {
    const e = buildSkillExecutionEvent({
      skillName: "Research",
      args: { prompt: "find papers" },
      success: true,
      durationMs: 4321,
      sessionId: "s1",
    });
    expect(e.skill).toBe("Research");
    expect(e.status).toBe("ok");
    expect(e.duration_s).toBe(4.3);
    expect(e.input).toContain("find papers");
    expect(e.session_id).toBe("s1");
    expect(e.source).toBe("runtime");
  });

  test("failure, missing fields and oversized args degrade safely", () => {
    const e = buildSkillExecutionEvent({
      skillName: "",
      args: "x".repeat(500),
      success: false,
      durationMs: undefined,
      sessionId: undefined,
    });
    expect(e.skill).toBe("unknown");
    expect(e.status).toBe("error");
    expect(e.duration_s).toBeNull();
    expect(e.session_id).toBeNull();
    expect(e.input.length).toBeLessThanOrEqual(161); // 160 + ellipsis
  });

  test("circular args do not throw", () => {
    const a: any = {};
    a.self = a;
    const e = buildSkillExecutionEvent({ skillName: "X", args: a, success: true, durationMs: 1 });
    expect(e.input).toBe("[unserializable args]");
  });

  test("emit stamps ts and appends a parseable row", () => {
    const dir = mkdtempSync(join(tmpdir(), "exec-log-"));
    const path = join(dir, "execution.jsonl");
    emitSkillExecution(
      { skillName: "Agents", args: { q: 1 }, success: true, durationMs: 250, sessionId: "s" },
      path,
    );
    const rows = readFileSync(path, "utf-8").trim().split("\n").map((l) => JSON.parse(l));
    expect(rows.length).toBe(1);
    expect(rows[0].ts).toMatch(/^\d{4}-\d{2}-\d{2}T/);
    expect(rows[0].skill).toBe("Agents");
    expect(rows[0].source).toBe("runtime");
  });

  test("production stream path is the SKILLS observability stream", () => {
    expect(SKILL_EXECUTION_PATH.endsWith(join("MEMORY", "SKILLS", "execution.jsonl"))).toBe(true);
  });
});

describe("W2.6 fence — no prompt surface teaches the execution.jsonl echo", () => {
  const roots = ["skills", "PAI/ALGORITHM", "PAI/SKILLS", "opencode/commands", "opencode/agents"]
    .map((r) => new URL(`../../${r}`, import.meta.url).pathname);

  const offenders: string[] = [];
  const walk = (dir: string) => {
    let entries: string[];
    try {
      entries = readdirSync(dir);
    } catch {
      return; // root may not exist in a partial checkout
    }
    for (const name of entries) {
      const p = join(dir, name);
      const st = statSync(p);
      if (st.isDirectory()) walk(p);
      else if (/\.(md|txt)$/.test(name) && readFileSync(p, "utf-8").includes("MEMORY/SKILLS/execution.jsonl")) {
        offenders.push(p);
      }
    }
  };

  test("zero skill/doc files instruct writing execution.jsonl", () => {
    roots.forEach(walk);
    expect(offenders).toEqual([]);
  });
});
