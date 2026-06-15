#!/usr/bin/env bun
import { appendJsonl, getPaiDir, nowIso, printJson, readTextIfExists } from "./lib/tool-runtime.ts";
import { existsSync, readdirSync } from "fs";
import { join } from "path";

function securityDir() {
  return join(getPaiDir(), "MEMORY", "SECURITY");
}

function policyPath() {
  return join(getPaiDir(), "USER", "SECURITY", "policies.yaml");
}

function narrationPath() {
  const now = new Date();
  const yyyy = String(now.getFullYear());
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  return join(securityDir(), yyyy, mm, `arthur-narration-${yyyy}${mm}${dd}.jsonl`);
}

function log(eventType: string, summary: string, extra: Record<string, unknown> = {}) {
  appendJsonl(narrationPath(), {
    timestamp: nowIso(),
    agent: "arthur",
    event_type: eventType,
    summary,
    ...extra,
  });
}

function recentSecurityEvents(limit = 20) {
  const root = securityDir();
  if (!existsSync(root)) return [];
  const files: string[] = [];
  const walk = (dir: string) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const full = join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.isFile() && entry.name.endsWith(".jsonl")) files.push(full);
    }
  };
  walk(root);
  return files
    .sort()
    .flatMap((file) => readTextIfExists(file).split(/\r?\n/).filter(Boolean).map((line) => ({ file, line })))
    .slice(-limit);
}

function parseArgs(args: string[]) {
  const command = args[0] || "status";
  const flags: Record<string, string | boolean> = {};
  for (let i = 1; i < args.length; i++) {
    const arg = args[i];
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      const next = args[i + 1];
      if (next && !next.startsWith("--")) {
        flags[key] = next;
        i++;
      } else {
        flags[key] = true;
      }
    }
  }
  return { command, flags };
}

const { command, flags } = parseArgs(process.argv.slice(2));

if (command === "--help" || command === "-h" || command === "help") {
  console.log(`Arthur - deterministic credential policy narrator

Usage:
  bun Arthur.ts status [--json]
  bun Arthur.ts audit [--limit 20] [--json]
  bun Arthur.ts decide --credential NAME --purpose TEXT [--json]

Arthur never emits raw credentials. Missing policy means denied/unavailable.`);
  process.exit(0);
}

if (command === "status") {
  const payload = {
    verdict: "available",
    policy_file: policyPath(),
    policy_file_exists: existsSync(policyPath()),
    recent_security_events: recentSecurityEvents(10).length,
    credential_release: "disabled_without_explicit_policy",
  };
  log("status", "Reported credential policy status.", { policy_file_exists: payload.policy_file_exists });
  printJson(payload);
  process.exit(0);
}

if (command === "audit") {
  const limit = Number(flags.limit) || 20;
  const events = recentSecurityEvents(limit).map((entry) => {
    try {
      return JSON.parse(entry.line);
    } catch {
      return { raw: entry.line };
    }
  });
  const payload = { verdict: "ok", count: events.length, events };
  log("audit", `Returned ${events.length} recent security events.`);
  printJson(payload);
  process.exit(0);
}

if (command === "decide") {
  const credential = String(flags.credential || "unknown");
  const purpose = String(flags.purpose || "");
  const hasPolicy = existsSync(policyPath());
  const payload = hasPolicy
    ? {
        verdict: "requires_confirmation",
        credential,
        reason: "Policy file exists, but automated credential release is disabled in this OpenCode port. Principal confirmation required.",
        purpose,
      }
    : {
        verdict: "denied",
        credential,
        reason: "No credential policy file installed; Arthur will not invent release decisions.",
        purpose,
      };
  log("decision", `${payload.verdict}: ${credential}`, { credential, purpose, reason: payload.reason });
  printJson(payload);
  process.exit(0);
}

printJson({ verdict: "error", reason: `unknown command: ${command}` });
process.exit(2);
