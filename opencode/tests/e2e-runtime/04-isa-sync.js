/**
 * E2E Scenario 4: ISA/State Sync Path
 * Verifies ISA frontmatter changes propagate to work.json.
 */

import {
  isISAArtifactPath,
  extractISAState,
  syncISAToWorkRegistry,
  readWorkRegistry,
} from '../../plugins/lib/pai-hooks.lib.js';
import { existsSync, writeFileSync, mkdirSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';

function run() {
  const testDir = join(tmpdir(), `pai-isa-e2e-${Date.now()}`);
  mkdirSync(testDir, { recursive: true });
  const isaFile = join(testDir, 'ISA.md');

  // Create ISA with frontmatter
  writeFileSync(isaFile, '---\nphase: plan\nprogress: 1/4\neffort: e3\nstatus: active\n---\n\n# Test ISA\n', 'utf-8');

  // Step 1: Detection
  if (!isISAArtifactPath(isaFile)) {
    console.log('E2E_FAIL: ISA file not detected');
    rmSync(testDir, { recursive: true });
    process.exit(1);
  }

  // Step 2: State extraction
  const state = extractISAState(isaFile);
  if (state.phase !== 'plan') {
    console.log(`E2E_FAIL: Extracted phase=${state.phase}, expected plan`);
    rmSync(testDir, { recursive: true });
    process.exit(1);
  }

  // Step 3: Sync to registry
  const result = syncISAToWorkRegistry(isaFile);
  if (!result.synced) {
    console.log(`E2E_FAIL: Sync failed: ${result.reason}`);
    rmSync(testDir, { recursive: true });
    process.exit(1);
  }

  // Step 4: Verify registry
  const registry = readWorkRegistry();
  const slug = testDir.split('/').pop();
  const session = registry.sessions[slug];
  if (!session) {
    console.log('E2E_FAIL: Session not found in registry after sync');
    rmSync(testDir, { recursive: true });
    process.exit(1);
  }
  if (session.phase !== 'plan') {
    console.log(`E2E_FAIL: Registry phase=${session.phase}, expected plan`);
    rmSync(testDir, { recursive: true });
    process.exit(1);
  }
  if (session.effort !== 'e3') {
    console.log(`E2E_FAIL: Registry effort=${session.effort}, expected e3`);
    rmSync(testDir, { recursive: true });
    process.exit(1);
  }

  // Cleanup
  rmSync(testDir, { recursive: true });

  console.log('E2E_PASS: ISA frontmatter synced to work.json');
}

run();
