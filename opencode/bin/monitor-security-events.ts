#!/usr/bin/env bun
import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

export type SecurityEvent = {
  timestamp?: string;
  eventType?: string;
  event_type?: string;
  actionTaken?: string;
};

export type SecurityHealthVerdict = {
  status: "ok" | "warn" | "alert";
  exit: 0 | 1 | 2;
  windowMinutes: number;
  counts: {
    alert: number;
    block: number;
    confirm: number;
    total: number;
  };
  reasons: string[];
};

type Thresholds = {
  alertWarn: number;
  alertAlert: number;
  blockWarn: number;
  blockAlert: number;
  confirmWarn: number;
  confirmAlert: number;
};

const DEFAULT_THRESHOLDS: Thresholds = {
  alertWarn: 10,
  alertAlert: 30,
  blockWarn: 1,
  blockAlert: 5,
  confirmWarn: 5,
  confirmAlert: 15,
};

function intEnv(name: string, fallback: number): number {
  const parsed = Number.parseInt(process.env[name] || "", 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

export function parseSecurityEvents(text: string): SecurityEvent[] {
  const events: SecurityEvent[] = [];
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      const value = JSON.parse(trimmed) as SecurityEvent;
      if (value && typeof value === "object") events.push(value);
    } catch {
      // Corrupt telemetry lines should not hide valid surrounding events.
    }
  }
  return events;
}

export function evaluateSecurityEvents(
  events: SecurityEvent[],
  options: { now?: Date; windowMinutes?: number; thresholds?: Partial<Thresholds> } = {},
): SecurityHealthVerdict {
  const now = options.now ?? new Date();
  const windowMinutes = options.windowMinutes ?? 24 * 60;
  const thresholds = { ...DEFAULT_THRESHOLDS, ...(options.thresholds ?? {}) };
  const sinceMs = now.getTime() - windowMinutes * 60_000;
  const counts = { alert: 0, block: 0, confirm: 0, total: 0 };

  for (const event of events) {
    const ts = event.timestamp ? Date.parse(event.timestamp) : NaN;
    if (Number.isFinite(ts) && ts < sinceMs) continue;
    const kind = String(event.eventType || event.event_type || "").toLowerCase();
    if (kind === "alert") counts.alert += 1;
    if (kind === "block") counts.block += 1;
    if (kind === "confirm") counts.confirm += 1;
    counts.total += 1;
  }

  let exit: 0 | 1 | 2 = 0;
  const reasons: string[] = [];
  const bump = (level: 1 | 2, reason: string) => {
    if (level > exit) exit = level;
    reasons.push(reason);
  };

  if (counts.alert >= thresholds.alertAlert) bump(2, `security alert count ${counts.alert} ≥ alert ${thresholds.alertAlert}`);
  else if (counts.alert >= thresholds.alertWarn) bump(1, `security alert count ${counts.alert} ≥ warn ${thresholds.alertWarn}`);

  if (counts.block >= thresholds.blockAlert) bump(2, `security block count ${counts.block} ≥ alert ${thresholds.blockAlert}`);
  else if (counts.block >= thresholds.blockWarn) bump(1, `security block count ${counts.block} ≥ warn ${thresholds.blockWarn}`);

  if (counts.confirm >= thresholds.confirmAlert) bump(2, `security confirm count ${counts.confirm} ≥ alert ${thresholds.confirmAlert}`);
  else if (counts.confirm >= thresholds.confirmWarn) bump(1, `security confirm count ${counts.confirm} ≥ warn ${thresholds.confirmWarn}`);

  return {
    status: exit === 2 ? "alert" : exit === 1 ? "warn" : "ok",
    exit,
    windowMinutes,
    counts,
    reasons,
  };
}

function defaultSecurityLogPath(): string {
  const paiDir = process.env.PAI_DIR || join(homedir(), ".config/opencode/PAI");
  return process.env.PAI_SECURITY_EVENTS_PATH || join(paiDir, "MEMORY/STATE/security-events.jsonl");
}

if (import.meta.main) {
  const logPath = defaultSecurityLogPath();
  const windowMinutes = intEnv("PAI_SECURITY_EVENT_WINDOW_MINUTES", 24 * 60);
  const thresholds: Partial<Thresholds> = {
    alertWarn: intEnv("PAI_SECURITY_ALERT_WARN", DEFAULT_THRESHOLDS.alertWarn),
    alertAlert: intEnv("PAI_SECURITY_ALERT_ALERT", DEFAULT_THRESHOLDS.alertAlert),
    blockWarn: intEnv("PAI_SECURITY_BLOCK_WARN", DEFAULT_THRESHOLDS.blockWarn),
    blockAlert: intEnv("PAI_SECURITY_BLOCK_ALERT", DEFAULT_THRESHOLDS.blockAlert),
    confirmWarn: intEnv("PAI_SECURITY_CONFIRM_WARN", DEFAULT_THRESHOLDS.confirmWarn),
    confirmAlert: intEnv("PAI_SECURITY_CONFIRM_ALERT", DEFAULT_THRESHOLDS.confirmAlert),
  };
  const text = existsSync(logPath) ? readFileSync(logPath, "utf-8") : "";
  const verdict = evaluateSecurityEvents(parseSecurityEvents(text), { windowMinutes, thresholds });
  const reason = verdict.reasons.length ? ` — ${verdict.reasons.join("; ")}` : "";
  console.log(`security-events ${verdict.status}: ${JSON.stringify(verdict.counts)}${reason}`);
  process.exit(verdict.exit);
}
