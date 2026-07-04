/**
 * Cross-runtime parity — the first EXECUTED O4 measurement.
 *
 * HARNESS_QUALITY.md §1/O4: "the port behaves like upstream PAI where it claims
 * parity" was, until now, a hand-graded table and a ~95% estimate — no scenario
 * had ever been run through BOTH runtimes and diffed. This file does exactly
 * that for the security floor:
 *
 *   upstream — the real Claude Code hook from the main branch
 *              (Releases/v5.0.0/.claude/hooks/SecurityPipeline.hook.ts),
 *              extracted from git at test time and driven over its actual
 *              contract: stdin JSON {session_id, tool_name, tool_input},
 *              exit 2 = deny, stdout permissionDecision "ask" = require_approval,
 *              stderr ALERT = alert, silent exit 0 = allow.
 *   dori     — the OpenCode port's inspectors (inspectBashCommand /
 *              inspectReadPath / inspectWritePath), the same entry points
 *              production pai-hooks.js calls.
 *
 * Two assertion classes:
 *   • relation "same"          — the outcomes must MATCH. This is the parity claim.
 *   • relation "dori-stronger" — a DOCUMENTED divergence where the port
 *     deliberately hardened past upstream (the 2026-07-04 deny-floor fixes).
 *     Asserted in both directions: dori must deny, and upstream must still be
 *     weaker — if upstream catches up, this test goes red so the case gets
 *     promoted to "same" (the same self-healing idea as the corpus fences).
 *   • every scenario, regardless of relation, must satisfy the DIRECTION
 *     RATCHET: dori is never WEAKER than upstream on a security decision.
 *
 * The suite skips (with a visible reason) when the main ref is not available
 * (shallow clone) — absence of the upstream tree must never read as parity.
 *
 * Run: bun test tests/cross-runtime-parity.test.ts
 */
import { describe, test, expect } from "bun:test";
import { mkdtempSync } from "fs";
import { tmpdir, homedir } from "os";
import { join } from "path";
import {
  inspectBashCommand,
  inspectReadPath,
  inspectWritePath,
} from "../plugins/lib/pai-hooks.lib.js";

type Action = "deny" | "require_approval" | "alert" | "allow";
const RANK: Record<Action, number> = { allow: 0, alert: 1, require_approval: 2, deny: 3 };

const repoRoot = join(import.meta.dir, "../..");
const HOME = homedir();

// ─── Upstream extraction ─────────────────────────────────────────────────────

function resolveMainRef(): string | null {
  for (const ref of ["origin/main", "main"]) {
    const r = Bun.spawnSync({
      cmd: ["git", "cat-file", "-e", `${ref}:Releases/v5.0.0/.claude/hooks/SecurityPipeline.hook.ts`],
      cwd: repoRoot,
    });
    if (r.exitCode === 0) return ref;
  }
  return null;
}

const MAIN_REF = resolveMainRef();

function extractUpstream(ref: string): string {
  const dir = mkdtempSync(join(tmpdir(), "pai-upstream-"));
  const r = Bun.spawnSync({
    cmd: ["bash", "-c", `git archive '${ref}:Releases/v5.0.0/.claude' | tar -x -C '${dir}'`],
    cwd: repoRoot,
  });
  if (r.exitCode !== 0) {
    throw new Error(`Failed to extract upstream tree: ${r.stderr.toString()}`);
  }
  return dir;
}

const upstreamDir = MAIN_REF ? extractUpstream(MAIN_REF) : null;

/** Drive the real upstream hook over its Claude Code contract. */
function upstreamDecision(toolName: string, toolInput: Record<string, unknown>): Action {
  const r = Bun.spawnSync({
    cmd: ["bun", join(upstreamDir!, "hooks/SecurityPipeline.hook.ts")],
    stdin: Buffer.from(JSON.stringify({ session_id: "parity", tool_name: toolName, tool_input: toolInput })),
    env: { ...process.env, PAI_DIR: join(upstreamDir!, "PAI") },
    stdout: "pipe",
    stderr: "pipe",
  });
  const stdout = r.stdout.toString();
  const stderr = r.stderr.toString();
  if (r.exitCode === 2) return "deny";
  if (stdout.includes('"permissionDecision":"ask"') || stdout.includes('"permissionDecision": "ask"')) {
    return "require_approval";
  }
  if (stderr.includes("ALERT")) return "alert";
  return "allow";
}

/** Drive the dori port through the same entry points production uses. */
function doriDecision(toolName: string, toolInput: Record<string, unknown>): Action {
  if (toolName === "Bash") return inspectBashCommand(String(toolInput.command)).action as Action;
  if (toolName === "Read") return inspectReadPath(String(toolInput.file_path)).action as Action;
  return inspectWritePath(String(toolInput.file_path)).action as Action;
}

// ─── Scenario table ──────────────────────────────────────────────────────────

type Scenario = {
  name: string;
  tool: string;
  input: Record<string, unknown>;
  relation: "same" | "dori-stronger";
  note: string;
};

const SCENARIOS: Scenario[] = [
  {
    name: "bash: rm -rf / (canonical root wipe)",
    tool: "Bash",
    input: { command: "rm -rf /" },
    relation: "same",
    note: "both runtimes must hard-deny",
  },
  {
    name: "bash: ls -la (benign)",
    tool: "Bash",
    input: { command: "ls -la" },
    relation: "same",
    note: "both runtimes must allow — O2 on both sides",
  },
  {
    name: "read: ~/.ssh/id_rsa (private key)",
    tool: "Read",
    input: { file_path: `${HOME}/.ssh/id_rsa` },
    relation: "same",
    note: "zeroAccess on both policies",
  },
  {
    name: "bash: cat ~/.aws/credentials",
    tool: "Bash",
    input: { command: "cat ~/.aws/credentials" },
    relation: "same",
    note: "measured 2026-07-04: BOTH allow (upstream EgressInspector watches exfil, not local reads; dori bash guard likewise). Pinned as agreement — if either side hardens, revisit deliberately.",
  },
  {
    name: "write: ~/.ssh/authorized_keys (SSH backdoor)",
    tool: "Write",
    input: { file_path: `${HOME}/.ssh/authorized_keys`, content: "ssh-ed25519 AAAA..." },
    relation: "dori-stronger",
    note: "dori denies since the 2026-07-04 deny-floor fixes; upstream v5.0.0 allows. Promote to 'same' when upstream adopts the fix.",
  },
  {
    name: "read: ~/project/.env (real dotenv)",
    tool: "Read",
    input: { file_path: `${HOME}/project/.env` },
    relation: "dori-stronger",
    note: "dori zero-accesses real .env files (templates exempt); upstream v5.0.0 allows the read. Promote to 'same' when upstream adopts the fix.",
  },
];

// ─── The measurement ─────────────────────────────────────────────────────────

describe.skipIf(!MAIN_REF)("Cross-runtime parity (O4, executed)", () => {
  // Guarded: bun executes the describe callback even when skipIf is true, so
  // decisions must not be computed against a missing upstream tree.
  const results = MAIN_REF
    ? SCENARIOS.map((s) => ({
        s,
        upstream: upstreamDecision(s.tool, s.input),
        dori: doriDecision(s.tool, s.input),
      }))
    : [];

  test("scoreboard", () => {
    console.log("\n  CROSS-RUNTIME PARITY (upstream = main/v5.0.0 hooks, executed):");
    for (const { s, upstream, dori } of results) {
      const mark = s.relation === "same" ? (upstream === dori ? "=" : "✗") : "≻";
      console.log(`    [${mark}] ${s.name}: upstream=${upstream} dori=${dori}`);
    }
    expect(results).toHaveLength(SCENARIOS.length);
  });

  for (const { s, upstream, dori } of results) {
    if (s.relation === "same") {
      test(`parity: ${s.name} — outcomes match`, () => {
        expect(dori).toBe(upstream);
      });
    } else {
      test(`documented divergence: ${s.name} — dori denies, upstream still weaker`, () => {
        expect(dori).toBe("deny");
        // If upstream catches up this goes red → promote the case to "same".
        expect(RANK[upstream]).toBeLessThan(RANK.deny);
      });
    }

    test(`direction ratchet: ${s.name} — dori never weaker than upstream`, () => {
      expect(RANK[dori]).toBeGreaterThanOrEqual(RANK[upstream]);
    });
  }
});

test.skipIf(!!MAIN_REF)("SKIPPED: main ref unavailable — parity NOT verified (do not read absence as green)", () => {
  console.warn("  cross-runtime parity skipped: no origin/main with Releases/v5.0.0 in this clone");
  expect(MAIN_REF).toBeNull();
});
