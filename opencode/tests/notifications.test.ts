import { describe, test, expect, beforeEach } from "bun:test";
import { existsSync, readFileSync, rmSync, writeFileSync, mkdirSync } from "fs";
import { join } from "path";
import { tmpdir } from "os";

// PAI_DIR is pointed at a temp dir by tests/setup.ts (bunfig preload),
// so NOTIFICATIONS_PATH lands in an isolated tree.
import {
  emitNotification,
  buildSpeak,
  NOTIFICATIONS_PATH,
  syncISAToWorkRegistry,
} from "../plugins/lib/pai-hooks.lib.js";

function readEvents(): any[] {
  if (!existsSync(NOTIFICATIONS_PATH)) return [];
  return readFileSync(NOTIFICATIONS_PATH, "utf-8")
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l));
}

function clearStream() {
  if (existsSync(NOTIFICATIONS_PATH)) rmSync(NOTIFICATIONS_PATH);
}

describe("Notifications — emitNotification envelope", () => {
  beforeEach(clearStream);

  test("writes a v1 entry with defaulted level and templated speak", () => {
    const entry = emitNotification({
      event: "phase_transition",
      sessionId: "ses_test",
      slug: "20260611_my-task",
      title: "My Task",
      data: { phase: "verify", previous_phase: "execute" },
    });

    expect(entry).not.toBeNull();
    const events = readEvents();
    expect(events.length).toBe(1);
    const e = events[0];
    expect(e.v).toBe(1);
    expect(e.level).toBe("milestone");
    expect(e.event).toBe("phase_transition");
    expect(e.session_id).toBe("ses_test");
    expect(e.slug).toBe("20260611_my-task");
    expect(e.speak).toContain("My Task");
    expect(e.speak).toContain("verify");
    expect(e.language).toBe("en-US");
    expect(e.timestamp).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  test("attention events get the attention level", () => {
    emitNotification({ event: "guard_denied", sessionId: "s", data: { guard: "skill", target: "ArXiv", reason: "misfire" } });
    emitNotification({ event: "security_blocked", sessionId: "s", data: { tool: "bash", reason: "rm -rf detected" } });
    emitNotification({ event: "tool_failing", sessionId: "s", data: { tool: "bash", count: 3 } });

    const levels = readEvents().map((e) => e.level);
    expect(levels).toEqual(["attention", "attention", "attention"]);
  });

  test("session_completed is a digest with duration in speak", () => {
    emitNotification({
      event: "session_completed",
      sessionId: "s",
      slug: "slug-x",
      title: "Port work",
      data: { duration_human: "42 minutes", final_phase: "complete" },
    });

    const e = readEvents()[0];
    expect(e.level).toBe("digest");
    expect(e.speak).toContain("Port work");
    expect(e.speak).toContain("42 minutes");
  });

  test("explicit speak overrides the template and is normalized", () => {
    emitNotification({
      event: "agent_completed",
      sessionId: "s",
      speak: "  Shipped the   parser\nwith tests  ",
      data: {},
    });

    expect(readEvents()[0].speak).toBe("Shipped the parser with tests");
  });

  test("explicit language overrides the default selector", () => {
    emitNotification({
      event: "agent_completed",
      sessionId: "s",
      speak: "Tarefa concluída",
      language: "pt_BR",
      data: {},
    });

    expect(readEvents()[0].language).toBe("pt-BR");
  });

  // Drift register W2.4: any well-formed BCP-47 locale is preserved, not
  // clamped to en/pt or dropped — the harness rides the model getting more
  // multilingual instead of capping it at two languages.
  test("non-en/pt locales are preserved, not nulled", () => {
    emitNotification({ event: "agent_completed", sessionId: "s", speak: "Tarea completada", language: "es-ES", data: {} });
    expect(readEvents()[0].language).toBe("es-ES");
  });

  test("bare language subtag normalizes without a fabricated region", () => {
    emitNotification({ event: "agent_completed", sessionId: "s", speak: "Terminé", language: "fr", data: {} });
    expect(readEvents()[0].language).toBe("fr");
  });

  test("unknown events fall back to milestone and a generic speak", () => {
    emitNotification({ event: "totally_new_event", sessionId: "s", data: {} });
    const e = readEvents()[0];
    expect(e.level).toBe("milestone");
    expect(e.speak).toContain("totally_new_event");
  });
});

describe("Notifications — buildSpeak templates", () => {
  test("every template yields a bounded single line", () => {
    const cases: Array<[string, any]> = [
      ["session_started", { title: "X" }],
      ["phase_transition", { slug: "y", phase: "build" }],
      ["agent_completed", { completed_line: "Done a thing with care" }],
      ["guard_denied", { guard: "agent", target: "Cato", reason: "trivial task" }],
      ["security_blocked", { tool: "bash", reason: "fork bomb" }],
      ["tool_failing", { tool: "edit", count: 3 }],
      ["permission_needed", { tool: "bash" }],
      ["session_completed", { slug: "z", duration_human: "5 minutes" }],
    ];
    for (const [event, data] of cases) {
      const speak = buildSpeak(event, data);
      expect(speak.length).toBeGreaterThan(0);
      expect(speak.length).toBeLessThanOrEqual(160);
      expect(speak).not.toContain("\n");
      expect(speak).not.toContain("undefined");
    }
  });

  test("agent_completed speaks the completed line verbatim", () => {
    expect(buildSpeak("agent_completed", { completed_line: "Fixed the sync race in work registry" }))
      .toBe("Fixed the sync race in work registry");
  });
});

describe("Notifications — phase_transition from ISA sync", () => {
  beforeEach(clearStream);

  function makeISA(dir: string, phase: string) {
    mkdirSync(dir, { recursive: true });
    const isaPath = join(dir, "ISA.md");
    writeFileSync(isaPath, `---\nphase: ${phase}\nprogress: 1/4\nstatus: active\n---\n\n# Test\n`, "utf-8");
    return isaPath;
  }

  test("emits exactly one event when the phase changes, none when it repeats", () => {
    const workDir = join(tmpdir(), `pai-notif-isa-${Math.floor(performance.now() * 1000)}`);
    const isaPath = makeISA(workDir, "plan");

    syncISAToWorkRegistry(isaPath, "ses_notif");
    const afterFirst = readEvents().filter((e) => e.event === "phase_transition");
    expect(afterFirst.length).toBe(1); // undefined -> plan is a transition

    syncISAToWorkRegistry(isaPath, "ses_notif");
    expect(readEvents().filter((e) => e.event === "phase_transition").length).toBe(1); // unchanged: no new event

    makeISA(workDir, "verify");
    syncISAToWorkRegistry(isaPath, "ses_notif");
    const all = readEvents().filter((e) => e.event === "phase_transition");
    expect(all.length).toBe(2);
    expect(all[1].data.phase).toBe("verify");
    expect(all[1].data.previous_phase).toBe("plan");
    expect(all[1].session_id).toBe("ses_notif");

    rmSync(workDir, { recursive: true, force: true });
  });
});
