/**
 * E2E Scenario 2: Mode Selection Path
 * Verifies that the classifier routes prompts to correct mode/tier.
 */

import { classifyPrompt } from '../../plugins/lib/mode-classifier.lib.js';

const isComplexMode = process.argv.includes('--complex');

function run() {
  if (isComplexMode) {
    const complex = "I need to design a distributed system with consensus, sharding, and failure recovery. Please produce a full architecture document with trade-off analysis.";
    const result = classifyPrompt(complex);
    if (result.mode !== 'ALGORITHM') {
      console.log(`E2E_FAIL: Complex prompt got mode=${result.mode}, expected ALGORITHM`);
      process.exit(1);
    }
    console.log('E2E_PASS: Complex prompt routed to ALGORITHM');
    return;
  }

  // Trivial ask
  const trivial = "hi";
  const result = classifyPrompt(trivial);
  if (result.mode !== 'MINIMAL') {
    console.log(`E2E_FAIL: Trivial prompt got mode=${result.mode}, expected MINIMAL`);
    process.exit(1);
  }
  console.log('E2E_PASS: Trivial prompt routed to MINIMAL');
}

run();
