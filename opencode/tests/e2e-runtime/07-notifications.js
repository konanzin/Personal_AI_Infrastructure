/**
 * E2E Scenario 7: Notifications Stream Path
 * Verifies that an ISA phase edit produces a phase_transition event in
 * notifications.jsonl (contract v1), with deterministic speak text.
 *
 * Self-isolated: points PAI_DIR at a temp tree BEFORE importing the lib,
 * so it never appends test events to the real stream.
 */

import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

const paiDir = mkdtempSync(join(tmpdir(), 'pai-e2e-notif-'));
process.env.PAI_DIR = paiDir;

const lib = await import('../../plugins/lib/pai-hooks.lib.js');

function fail(msg) {
  console.log(`E2E_FAIL: ${msg}`);
  rmSync(paiDir, { recursive: true, force: true });
  process.exit(1);
}

const workDir = join(paiDir, 'MEMORY', 'WORK', 'e2e-notif-task');
mkdirSync(workDir, { recursive: true });
const isaFile = join(workDir, 'ISA.md');

// Phase 1: plan
writeFileSync(isaFile, '---\nphase: plan\nprogress: 0/3\nstatus: active\n---\n\n# E2E Notif\n', 'utf-8');
let result = lib.syncISAToWorkRegistry(isaFile, 'ses-e2e-notif');
if (!result.synced) fail(`initial sync failed: ${result.reason}`);

// Phase 2: edit phase -> verify (THE phase-change signal)
writeFileSync(isaFile, '---\nphase: verify\nprogress: 2/3\nstatus: active\n---\n\n# E2E Notif\n', 'utf-8');
result = lib.syncISAToWorkRegistry(isaFile, 'ses-e2e-notif');
if (!result.synced) fail(`second sync failed: ${result.reason}`);

if (!existsSync(lib.NOTIFICATIONS_PATH)) fail('notifications.jsonl was not created');

const events = readFileSync(lib.NOTIFICATIONS_PATH, 'utf-8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l))
  .filter((e) => e.event === 'phase_transition');

if (events.length !== 2) fail(`expected 2 phase_transition events (null->plan, plan->verify), got ${events.length}`);

const last = events[1];
if (last.v !== 1) fail(`bad contract version: ${last.v}`);
if (last.level !== 'milestone') fail(`bad level: ${last.level}`);
if (last.data.phase !== 'verify' || last.data.previous_phase !== 'plan') {
  fail(`bad transition data: ${JSON.stringify(last.data)}`);
}
if (!last.speak || !last.speak.includes('verify')) fail(`speak not speakable: "${last.speak}"`);
if (last.session_id !== 'ses-e2e-notif') fail(`bad session_id: ${last.session_id}`);

rmSync(paiDir, { recursive: true, force: true });
console.log('E2E_PASS: ISA phase edit emitted contract-v1 phase_transition notification');
