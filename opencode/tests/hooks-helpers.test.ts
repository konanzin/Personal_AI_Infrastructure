/**
 * Unit tests for pai-hooks.lib.js helper functions (SmartApprover, repeat
 * detection, Telos sync, integrity telemetry).
 *
 * Renamed from hooks-parity.test.ts (2026-07-04): the old name implied these
 * verify behavioral parity with upstream Claude Code PAI — they don't. Nothing
 * here executes a scenario on both runtimes; parity remains an ESTIMATE until a
 * real cross-runtime comparison exists (see HARNESS_QUALITY.md §2, O4).
 */
import { describe, expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import {
  isTrustedPath,
  detectRepeatPrompt,
  maybeSyncTelosSummary,
  detectChangedPaiSystemFiles,
  runIntegrityTelemetry,
} from "../plugins/lib/pai-hooks.lib.js";

describe("SmartApprover — isTrustedPath", () => {
  test("trusts /tmp paths", () => {
    expect(isTrustedPath("/tmp/whatever.txt")).toBe(true);
  });
  test("does not trust system paths", () => {
    expect(isTrustedPath("/etc/passwd")).toBe(false);
    expect(isTrustedPath("/usr/lib/x")).toBe(false);
  });
});

describe("RepeatDetection — detectRepeatPrompt (Jaccard)", () => {
  test("first prompt is never a repeat; a near-identical follow-up is", () => {
    const sid = `test-repeat-${Math.floor(performance.now())}`;
    const prompt = "please refactor the authentication module to use jwt tokens and add tests";
    expect(detectRepeatPrompt(sid, prompt).isRepeat).toBe(false);
    const again = detectRepeatPrompt(sid, prompt + " now");
    expect(again.isRepeat).toBe(true);
    expect(again.similarity).toBeGreaterThan(0.6);
  });

  test("an unrelated follow-up is not flagged", () => {
    const sid = `test-repeat-${Math.floor(performance.now())}-b`;
    detectRepeatPrompt(sid, "explain how the security policy cascade works in detail");
    const other = detectRepeatPrompt(sid, "generate a haiku about the ocean at dawn please");
    expect(other.isRepeat).toBe(false);
  });
});

describe("TelosSummarySync — maybeSyncTelosSummary", () => {
  test("ignores non-TELOS writes", () => {
    expect(maybeSyncTelosSummary("/tmp/src/index.ts").reason).toBe("not_telos");
  });
});

describe("Integrity telemetry", () => {
  test("detects PAI doc writes from tool-activity ground truth", () => {
    const dir = mkdtempSync(join(tmpdir(), "pai-integrity-"));
    const activity = join(dir, "tool-activity.jsonl");
    writeFileSync(
      activity,
      [
        JSON.stringify({ session_id: "s1", tool_name: "edit", ground_truth: { file_path: "/home/u/.config/opencode/PAI/DOCUMENTATION/Tools/Tools.md" } }),
        JSON.stringify({ session_id: "s1", tool_name: "write", ground_truth: { file_path: "/home/u/project/src/app.ts" } }),
        JSON.stringify({ session_id: "other", tool_name: "edit", ground_truth: { file_path: "/x/DOCUMENTATION/y.md" } }),
      ].join("\n"),
      "utf-8",
    );
    const changed = detectChangedPaiSystemFiles("s1", activity);
    expect(changed.length).toBe(1);
    expect(changed[0]).toContain("DOCUMENTATION");
  });

  test("skips when no PAI files changed (no spawn)", () => {
    const result = runIntegrityTelemetry({ sessionId: "s1", changedFiles: [] });
    expect(result.ran).toBe(false);
    expect(result.skipped).toBe("no_pai_changes");
  });
});
