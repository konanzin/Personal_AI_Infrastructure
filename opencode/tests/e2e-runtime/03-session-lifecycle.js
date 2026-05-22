/**
 * E2E Scenario 3: Session Lifecycle Path
 * Verifies create → work → idle → delete flow.
 */

import { readWorkRegistry, writeWorkRegistry, getISOTimestamp } from '../../plugins/lib/pai-hooks.lib.js';
import { existsSync, readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

const PAI_DIR = process.env.PAI_DIR || join(homedir(), '.config', 'opencode', 'PAI');
const STATE_DIR = join(PAI_DIR, 'MEMORY', 'STATE');
const WORK_DIR = join(PAI_DIR, 'MEMORY', 'WORK');

function run() {
  const testSlug = `e2e-test-${Date.now()}`;
  const sessionId = `test-session-${Date.now()}`;
  const testDir = join(WORK_DIR, testSlug);

  // Ensure dirs exist
  if (!existsSync(STATE_DIR)) mkdirSync(STATE_DIR, { recursive: true });
  if (!existsSync(WORK_DIR)) mkdirSync(WORK_DIR, { recursive: true });

  // Step 1: Create session
  const registry = readWorkRegistry();
  registry.sessions[testSlug] = {
    sessionUUID: sessionId,
    started: getISOTimestamp(),
    updatedAt: getISOTimestamp(),
    phase: 'observe',
    progress: '1/5',
    task: 'E2E lifecycle test',
    status: 'active',
  };
  writeWorkRegistry(registry);

  // Verify creation
  const afterCreate = readWorkRegistry();
  if (!afterCreate.sessions[testSlug]) {
    console.log('E2E_FAIL: Session not created in registry');
    process.exit(1);
  }

  // Step 2: Simulate work (update phase)
  afterCreate.sessions[testSlug].phase = 'execute';
  afterCreate.sessions[testSlug].progress = '3/5';
  afterCreate.sessions[testSlug].updatedAt = getISOTimestamp();
  writeWorkRegistry(afterCreate);

  // Verify work update
  const afterWork = readWorkRegistry();
  if (afterWork.sessions[testSlug].phase !== 'execute') {
    console.log('E2E_FAIL: Work phase not updated');
    process.exit(1);
  }

  // Step 3: Simulate idle (only update lastIdleAt)
  const idleTime = getISOTimestamp();
  afterWork.sessions[testSlug].lastIdleAt = idleTime;
  writeWorkRegistry(afterWork);

  const afterIdle = readWorkRegistry();
  if (afterIdle.sessions[testSlug].lastIdleAt !== idleTime) {
    console.log('E2E_FAIL: Idle timestamp not set');
    process.exit(1);
  }

  // Step 4: Delete/archive
  const sessionData = { ...afterIdle.sessions[testSlug] };
  delete afterIdle.sessions[testSlug];
  writeWorkRegistry(afterIdle);

  // Verify deletion
  const afterDelete = readWorkRegistry();
  if (afterDelete.sessions[testSlug]) {
    console.log('E2E_FAIL: Session not removed from registry');
    process.exit(1);
  }

  console.log('E2E_PASS: Full lifecycle create→work→idle→delete');
}

run();
