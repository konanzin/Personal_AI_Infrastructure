/**
 * E2E Scenario 5: Passive Satisfaction Path
 * Verifies rating and praise capture without slash commands.
 */

import { parseExplicitRating, detectPositivePraise } from '../../plugins/lib/pai-hooks.lib.js';

const isPraiseMode = process.argv.includes('--praise');

function run() {
  if (isPraiseMode) {
    // Praise detection
    const praiseMsgs = [
      "Great work, thanks!",
      "Perfect, exactly what I needed",
      "Excellent job on this",
    ];
    for (const msg of praiseMsgs) {
      if (!detectPositivePraise(msg)) {
        console.log(`E2E_FAIL: Praise not detected in: "${msg}"`);
        process.exit(1);
      }
    }
    console.log('E2E_PASS: Praise detection works');
    return;
  }

  // Explicit rating capture
  const cases = [
    { input: '/rate 5 great job', expected: { rating: 5, comment: 'great job' } },
    { input: '/rating 8 too verbose', expected: { rating: 8 } },
    { input: '7 decent but could be better', expected: { rating: 7, comment: 'decent but could be better' } },
  ];

  for (const { input, expected } of cases) {
    const result = parseExplicitRating(input);
    if (!result) {
      console.log(`E2E_FAIL: No rating parsed from: "${input}"`);
      process.exit(1);
    }
    if (result.rating !== expected.rating) {
      console.log(`E2E_FAIL: Expected rating ${expected.rating}, got ${result.rating}`);
      process.exit(1);
    }
    if (expected.comment !== undefined && result.comment !== expected.comment) {
      console.log(`E2E_FAIL: Expected comment "${expected.comment}", got "${result.comment}"`);
      process.exit(1);
    }
  }

  console.log('E2E_PASS: Explicit rating capture works');
}

run();
