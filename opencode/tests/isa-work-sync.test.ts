import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { existsSync, mkdirSync, writeFileSync, unlinkSync, rmdirSync, rmSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

// Static imports for stateless functions
import {
  isISAArtifactPath,
  extractISAState,
} from "../plugins/lib/pai-hooks.lib.js";

// Helper to create a mock ISA file with frontmatter
function createMockISA(dir, filename, frontmatter) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  const path = join(dir, filename);
  const content = `---\n${frontmatter}\n---\n\n# ISA Content\n`;
  writeFileSync(path, content, "utf-8");
  return path;
}

// Re-import lib with a fresh PAI_DIR for stateful tests
async function loadLib(paiDir) {
  process.env.PAI_DIR = paiDir;
  const mod = await import(`../plugins/lib/pai-hooks.lib.js?t=${Date.now()}`);
  return mod;
}

describe("ISA Sync — isISAArtifactPath", () => {
  test("detects MEMORY/WORK/*/ISA.md", () => {
    expect(isISAArtifactPath("/home/user/.config/opencode/PAI/MEMORY/WORK/20240101-120000_task/ISA.md")).toBe(true);
  });

  test("detects MEMORY/WORK/*/PRD.md (legacy)", () => {
    expect(isISAArtifactPath("/home/user/.config/opencode/PAI/MEMORY/WORK/some-task/PRD.md")).toBe(true);
  });

  test("detects standalone ISA.md", () => {
    expect(isISAArtifactPath("/project/ISA.md")).toBe(true);
  });

  test("rejects non-ISA files", () => {
    expect(isISAArtifactPath("/home/user/.config/opencode/PAI/MEMORY/WORK/task/README.md")).toBe(false);
    expect(isISAArtifactPath("/project/src/index.ts")).toBe(false);
    expect(isISAArtifactPath("")).toBe(false);
  });

  test("rejects null/undefined", () => {
    expect(isISAArtifactPath(null)).toBe(false);
    expect(isISAArtifactPath(undefined)).toBe(false);
  });
});

describe("ISA Sync — extractISAState", () => {
  const testDir = join(tmpdir(), "pai-isa-extract-" + Date.now());

  beforeEach(() => {
    if (!existsSync(testDir)) mkdirSync(testDir, { recursive: true });
  });

  afterEach(() => {
    if (existsSync(testDir)) {
      for (const f of require("fs").readdirSync(testDir)) {
        try { unlinkSync(join(testDir, f)); } catch {}
      }
      rmdirSync(testDir);
    }
  });

  test("extracts all state fields from frontmatter", () => {
    const isaPath = createMockISA(testDir, "ISA.md", [
      "phase: observe",
      "progress: 3/5",
      "updated: 2024-01-15T10:30:00Z",
      "effort: e3",
      "mode: algorithm",
      "task: Build auth system",
      "slug: auth-system",
    ].join("\n"));

    const state = extractISAState(isaPath);
    expect(state).not.toBeNull();
    expect(state.phase).toBe("observe");
    expect(state.progress).toBe("3/5");
    expect(state.updated).toBe("2024-01-15T10:30:00Z");
    expect(state.effort).toBe("e3");
    expect(state.mode).toBe("algorithm");
    expect(state.task).toBe("Build auth system");
    expect(state.slug).toBe("auth-system");
  });

  test("returns null for file without frontmatter", () => {
    const path = join(testDir, "no-fm.md");
    writeFileSync(path, "# Just a heading\n", "utf-8");
    expect(extractISAState(path)).toBeNull();
  });

  test("returns null for missing file", () => {
    expect(extractISAState(join(testDir, "nonexistent.md"))).toBeNull();
  });

  test("handles partial frontmatter gracefully", () => {
    const isaPath = createMockISA(testDir, "partial.md", "phase: think\n");
    const state = extractISAState(isaPath);
    expect(state).not.toBeNull();
    expect(state.phase).toBe("think");
    expect(state.progress).toBeUndefined();
    expect(state.effort).toBeUndefined();
  });

  test("maps title to task field", () => {
    const isaPath = createMockISA(testDir, "title.md", "title: My Task\n");
    const state = extractISAState(isaPath);
    expect(state.title).toBe("My Task");
  });
});

describe("ISA Sync — syncISAToWorkRegistry", () => {
  let paiDir;
  let lib;

  beforeEach(async () => {
    paiDir = join(tmpdir(), `pai-sync-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`);
    mkdirSync(join(paiDir, "MEMORY", "STATE"), { recursive: true });
    mkdirSync(join(paiDir, "MEMORY", "WORK"), { recursive: true });
    lib = await loadLib(paiDir);
  });

  afterEach(() => {
    if (existsSync(paiDir)) {
      rmSync(paiDir, { recursive: true, force: true });
    }
  });

  test("creates new session when ISA is first seen", async () => {
    const slug = "test-task-" + Date.now();
    const isaPath = createMockISA(join(paiDir, "MEMORY", "WORK", slug), "ISA.md", [
      "phase: observe",
      "progress: 1/5",
      "effort: e2",
    ].join("\n"));

    const result = lib.syncISAToWorkRegistry(isaPath);
    expect(result.synced).toBe(true);
    expect(result.slug).toBe(slug);

    const registry = lib.readWorkRegistry();
    expect(registry.sessions[slug]).toBeDefined();
    expect(registry.sessions[slug].phase).toBe("observe");
    expect(registry.sessions[slug].progress).toBe("1/5");
    expect(registry.sessions[slug].effort).toBe("e2");
  });

  test("updates existing session in-place (no duplicates)", async () => {
    const slug = "upsert-task-" + Date.now();
    const workDir = join(paiDir, "MEMORY", "WORK", slug);

    // First write
    const isaPath = createMockISA(workDir, "ISA.md", "phase: observe\nprogress: 1/5\n");
    lib.syncISAToWorkRegistry(isaPath);

    const registry1 = lib.readWorkRegistry();
    const sessionCount1 = Object.keys(registry1.sessions).length;

    // Re-edit same ISA
    const isaPath2 = createMockISA(workDir, "ISA.md", "phase: think\nprogress: 2/5\n");
    lib.syncISAToWorkRegistry(isaPath2);

    const registry2 = lib.readWorkRegistry();
    const sessionCount2 = Object.keys(registry2.sessions).length;

    expect(sessionCount2).toBe(sessionCount1); // No new sessions
    expect(registry2.sessions[slug].phase).toBe("think");
    expect(registry2.sessions[slug].progress).toBe("2/5");
  });

  test("does nothing for non-ISA files", async () => {
    const testWorkDir = join(paiDir, "random");
    if (!existsSync(testWorkDir)) mkdirSync(testWorkDir, { recursive: true });
    const path = join(testWorkDir, "readme.md");
    writeFileSync(path, "# Readme\n", "utf-8");
    const result = lib.syncISAToWorkRegistry(path);
    expect(result.synced).toBe(false);
    expect(result.reason).toBe("no_state_extracted");
  });

  test("handles missing frontmatter gracefully", async () => {
    const testWorkDir = join(paiDir, "random");
    if (!existsSync(testWorkDir)) mkdirSync(testWorkDir, { recursive: true });
    const path = join(testWorkDir, "ISA.md");
    writeFileSync(path, "# No frontmatter\n", "utf-8");
    const result = lib.syncISAToWorkRegistry(path);
    expect(result.synced).toBe(false);
    expect(result.reason).toBe("no_state_extracted");
  });

  test("syncs with sessionId and updates current-work file", async () => {
    const slug = "session-task-" + Date.now();
    const sessionId = "test-session-123";
    const isaPath = createMockISA(join(paiDir, "MEMORY", "WORK", slug), "ISA.md", [
      "phase: verify",
      "progress: 5/5",
      "mode: algorithm",
    ].join("\n"));

    const result = lib.syncISAToWorkRegistry(isaPath, sessionId);
    expect(result.synced).toBe(true);

    const registry = lib.readWorkRegistry();
    expect(registry.sessions[slug]).toBeDefined();
    expect(registry.sessions[slug].phase).toBe("verify");
    expect(registry.sessions[slug].sessionUUID).toBe(sessionId);
  });

  test("preserves existing session fields not in ISA", async () => {
    const slug = "preserve-task-" + Date.now();
    const isaPath = createMockISA(join(paiDir, "MEMORY", "WORK", slug), "ISA.md", "phase: observe\n");

    // Pre-seed registry with extra fields
    const registry = lib.readWorkRegistry();
    registry.sessions[slug] = {
      sessionUUID: "existing-session",
      customField: "should-persist",
      ratings: [{ value: 8 }],
    };
    lib.writeWorkRegistry(registry);

    lib.syncISAToWorkRegistry(isaPath);

    const updated = lib.readWorkRegistry();
    expect(updated.sessions[slug].customField).toBe("should-persist");
    expect(updated.sessions[slug].ratings).toHaveLength(1);
    expect(updated.sessions[slug].phase).toBe("observe");
  });
});
