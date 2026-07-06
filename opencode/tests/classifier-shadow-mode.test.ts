/**
 * W2.2 plumbing — classifier gate vs shadow mode, exercised through the REAL
 * chat.message hook in a subprocess (same pattern as the observability
 * round-trip).
 *
 * gate (default): classification persisted to current-work → injected next
 * transform as the executor's suggestion. shadow: telemetry-only
 * (applied:false), nothing persisted, the executor self-selects. Explicit
 * /eN overrides bind in BOTH modes — they are the Principal's order, not
 * classifier opinion. The default stays 'gate'; flipping to shadow is gated
 * on the escalation-golden 'none' bucket (REGISTER W2.2).
 */
import { describe, test, expect } from "bun:test";
import { readFileSync, mkdtempSync, existsSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { fileURLToPath } from "url";
import { resolveClassifierConfig } from "../plugins/lib/mode-classifier.lib.js";

const driver = fileURLToPath(new URL("./helpers/drive-classifier-mode.mjs", import.meta.url));

function drive(sid: string, prompt: string, extraEnv: Record<string, string> = {}) {
  const home = mkdtempSync(join(tmpdir(), "pai-shadow-"));
  const proc = Bun.spawnSync({
    cmd: ["bun", driver, sid, prompt],
    env: { ...process.env, PAI_DIR: home, PAI_CLASSIFIER_USE_LLM: "false", ...extraEnv },
    stdout: "pipe",
    stderr: "pipe",
  });
  const out = new TextDecoder().decode(proc.stdout) + new TextDecoder().decode(proc.stderr);
  expect(out).toContain("DRIVE_OK");
  const workPath = join(home, "MEMORY", "STATE", `current-work-${sid}.json`);
  const work = existsSync(workPath) ? JSON.parse(readFileSync(workPath, "utf-8")) : null;
  const telemetryPath = join(home, "MEMORY", "OBSERVABILITY", "mode-classifier.jsonl");
  const rows = existsSync(telemetryPath)
    ? readFileSync(telemetryPath, "utf-8").trim().split("\n").map((l) => JSON.parse(l))
    : [];
  return { work, rows };
}

describe("resolveClassifierConfig mode", () => {
  test("defaults to gate; file and env can select shadow; env wins; junk falls back to gate", () => {
    expect(resolveClassifierConfig({}, {}).mode).toBe("gate");
    expect(resolveClassifierConfig({ mode: "shadow" }, {}).mode).toBe("shadow");
    expect(resolveClassifierConfig({ mode: "gate" }, { PAI_CLASSIFIER_MODE: "shadow" }).mode).toBe("shadow");
    expect(resolveClassifierConfig({ mode: "shadow" }, { PAI_CLASSIFIER_MODE: "gate" }).mode).toBe("gate");
    expect(resolveClassifierConfig({ mode: "banana" }, {}).mode).toBe("gate");
  });
});

describe("classifier shadow mode (real hook, subprocess)", () => {
  const WORK_PROMPT = "implement the authentication module with jwt and refresh tokens";

  test("gate (default): classification persists and telemetry says applied", () => {
    const { work, rows } = drive("ses_gate", WORK_PROMPT);
    expect(work?.classification?.mode).toBeDefined();
    const row = rows.find((r) => r.event === "mode_classification");
    expect(row).toBeDefined();
    expect(row.applied).toBe(true);
  });

  test("shadow: telemetry-only — nothing persisted, applied:false", () => {
    const { work, rows } = drive("ses_shadow", WORK_PROMPT, { PAI_CLASSIFIER_MODE: "shadow" });
    expect(work?.classification).toBeUndefined();
    const row = rows.find((r) => r.event === "mode_classification");
    expect(row).toBeDefined();
    expect(row.applied).toBe(false);
    expect(row.mode).toBeDefined(); // still measured — shadow exists to keep measuring
  });

  test("shadow: explicit /eN override still binds (persisted, applied)", () => {
    const { work, rows } = drive(
      "ses_shadow_override",
      "Run PAI effort E4 for: refactor the auth module",
      { PAI_CLASSIFIER_MODE: "shadow" },
    );
    expect(work?.classification?.source).toBe("override");
    expect(work?.classification?.tier).toBe("E4");
    const row = rows.find((r) => r.event === "mode_classification");
    expect(row.applied).toBe(true);
    expect(row.source).toBe("override");
  });
});
