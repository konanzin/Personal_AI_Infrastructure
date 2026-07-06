import { describe, expect, test } from "bun:test";
import { evaluateSecurityEvents, parseSecurityEvents } from "../bin/monitor-security-events";

const now = new Date("2026-07-05T16:00:00Z");

describe("Security event health monitor", () => {
  test("parses valid JSONL and ignores corrupt lines", () => {
    const events = parseSecurityEvents('{"eventType":"alert"}\nnot-json\n{"eventType":"block"}\n');
    expect(events).toHaveLength(2);
  });

  test("returns ok when no threshold is crossed", () => {
    const verdict = evaluateSecurityEvents(
      [{ timestamp: now.toISOString(), eventType: "alert" }],
      { now, thresholds: { alertWarn: 2 } },
    );
    expect(verdict.status).toBe("ok");
    expect(verdict.exit).toBe(0);
  });

  test("warns on security alert bursts", () => {
    const verdict = evaluateSecurityEvents(
      [
        { timestamp: now.toISOString(), eventType: "alert" },
        { timestamp: now.toISOString(), eventType: "alert" },
      ],
      { now, thresholds: { alertWarn: 2, alertAlert: 5 } },
    );
    expect(verdict.status).toBe("warn");
    expect(verdict.exit).toBe(1);
  });

  test("alerts on repeated security blocks", () => {
    const verdict = evaluateSecurityEvents(
      [
        { timestamp: now.toISOString(), eventType: "block" },
        { timestamp: now.toISOString(), eventType: "block" },
      ],
      { now, thresholds: { blockWarn: 1, blockAlert: 2 } },
    );
    expect(verdict.status).toBe("alert");
    expect(verdict.exit).toBe(2);
  });

  test("ignores events outside the window", () => {
    const verdict = evaluateSecurityEvents(
      [{ timestamp: "2026-07-04T15:00:00Z", eventType: "block" }],
      { now, windowMinutes: 30, thresholds: { blockWarn: 1 } },
    );
    expect(verdict.status).toBe("ok");
  });
});
