#!/usr/bin/env bun
/**
 * LearningPatternSynthesis - Aggregate ratings into actionable patterns
 *
 * Analyzes LEARNING/SIGNALS/ratings.jsonl to find recurring patterns
 * and generates synthesis reports for continuous improvement.
 *
 * Commands:
 *   --week         Analyze last 7 days (default)
 *   --month        Analyze last 30 days
 *   --all          Analyze all ratings
 *   --dry-run      Show analysis without writing
 *
 * Examples:
 *   bun run LearningPatternSynthesis.ts --week
 *   bun run LearningPatternSynthesis.ts --month --dry-run
 */

import { parseArgs } from "util";
import * as fs from "fs";
import * as path from "path";
import { getPaiDir } from "./lib/tool-runtime";

// ============================================================================
// Configuration (OpenCode: paths resolve via getPaiDir)
// ============================================================================

const MIN_RATINGS = 5;
const LEARNING_DIR = path.join(getPaiDir(), "MEMORY", "LEARNING");
const RATINGS_FILE = path.join(LEARNING_DIR, "SIGNALS", "ratings.jsonl");
const SYNTHESIS_DIR = path.join(LEARNING_DIR, "SYNTHESIS");

// ============================================================================
// Types
// ============================================================================

interface Rating {
  timestamp: string;
  rating: number;
  session_id: string;
  source: "explicit" | "implicit";
  sentiment_summary: string;
  confidence: number;
  comment?: string;
}

interface PatternGroup {
  pattern: string;
  count: number;
  avgRating: number;
  avgConfidence: number;
  examples: string[];
}

interface SynthesisResult {
  period: string;
  totalRatings: number;
  avgRating: number;
  frustrations: PatternGroup[];
  successes: PatternGroup[];
  topIssues: string[];
  recommendations: string[];
}

// ============================================================================
// Pattern Detection
// ============================================================================

const FRUSTRATION_PATTERNS: Record<string, RegExp> = {
  "Time/Performance Issues": /time|slow|delay|hang|wait|long|minutes|hours/i,
  "Incomplete Work": /incomplete|missing|partial|didn't finish|not done/i,
  "Wrong Approach": /wrong|incorrect|not what|misunderstand|mistake/i,
  "Over-engineering": /over-?engineer|too complex|unnecessary|bloat/i,
  "Tool/System Failures": /fail|error|broken|crash|bug|issue/i,
  "Communication Problems": /unclear|confus|didn't ask|should have asked/i,
  "Repetitive Issues": /again|repeat|still|same problem/i,
};

const SUCCESS_PATTERNS: Record<string, RegExp> = {
  "Quick Resolution": /quick|fast|efficient|smooth/i,
  "Good Understanding": /understood|clear|exactly|perfect/i,
  "Proactive Help": /proactive|anticipat|helpful|above and beyond/i,
  "Clean Implementation": /clean|simple|elegant|well done/i,
};

function detectPatterns(summaries: string[], patterns: Record<string, RegExp>): Map<string, string[]> {
  const results = new Map<string, string[]>();

  for (const summary of summaries) {
    for (const [name, pattern] of Object.entries(patterns)) {
      if (pattern.test(summary)) {
        if (!results.has(name)) {
          results.set(name, []);
        }
        results.get(name)!.push(summary);
      }
    }
  }

  return results;
}

function groupToPatternGroups(
  grouped: Map<string, string[]>,
  ratings: Rating[]
): PatternGroup[] {
  const groups: PatternGroup[] = [];

  for (const [pattern, examples] of grouped.entries()) {
    // Find ratings that match these examples
    const matchingRatings = ratings.filter(r =>
      examples.some(e => e === r.sentiment_summary)
    );

    // W2.12: no data means no number — the old fallbacks (5 and 0.5) invented
    // a neutral score for patterns nobody rated.
    const avgRating = matchingRatings.length > 0
      ? matchingRatings.reduce((sum, r) => sum + r.rating, 0) / matchingRatings.length
      : null;

    const avgConfidence = matchingRatings.length > 0
      ? matchingRatings.reduce((sum, r) => sum + r.confidence, 0) / matchingRatings.length
      : null;

    groups.push({
      pattern,
      count: examples.length,
      avgRating,
      avgConfidence,
      examples: examples.slice(0, 3), // Top 3 examples
    });
  }

  return groups.sort((a, b) => b.count - a.count);
}

// ============================================================================
// Analysis
// ============================================================================

function analyzeRatings(ratings: Rating[], period: string): SynthesisResult {
  if (ratings.length === 0) {
    return {
      period,
      totalRatings: 0,
      avgRating: 0,
      frustrations: [],
      successes: [],
      topIssues: [],
      recommendations: [],
    };
  }

  const avgRating = ratings.reduce((sum, r) => sum + r.rating, 0) / ratings.length;

  // Separate frustrations (rating <= 4) and successes (rating >= 7)
  const frustrationRatings = ratings.filter(r => r.rating <= 4);
  const successRatings = ratings.filter(r => r.rating >= 7);

  const frustrationSummaries = frustrationRatings.map(r => r.sentiment_summary);
  const successSummaries = successRatings.map(r => r.sentiment_summary);

  // Detect patterns
  const frustrationGroups = detectPatterns(frustrationSummaries, FRUSTRATION_PATTERNS);
  const successGroups = detectPatterns(successSummaries, SUCCESS_PATTERNS);

  const frustrations = groupToPatternGroups(frustrationGroups, frustrationRatings);
  const successes = groupToPatternGroups(successGroups, successRatings);

  // Generate top issues (most common frustrations)
  const topIssues = frustrations
    .slice(0, 3)
    .map(f => `${f.pattern} (${f.count} occurrences, avg rating ${f.avgRating.toFixed(1)})`);

  // Generate recommendations based on patterns
  // W2.12: no canned advice — the old version mapped pattern names to frozen
  // recommendation strings, which is a lookup table cosplaying as insight. The
  // report carries the DATA (patterns, counts, examples); interpreting it is
  // the reading model's job, with full context this tool does not have.
  const recommendations: string[] = [
    "Interpretation belongs to the reader: review the patterns above in context before changing behavior.",
  ];

  return {
    period,
    totalRatings: ratings.length,
    avgRating,
    frustrations,
    successes,
    topIssues,
    recommendations,
  };
}

// ============================================================================
// File Generation
// ============================================================================

function formatSynthesisReport(result: SynthesisResult): string {
  const date = new Date().toISOString().split('T')[0];

  let content = `# Learning Pattern Synthesis

**Period:** ${result.period}
**Generated:** ${date}
**Total Ratings:** ${result.totalRatings}
**Average Rating:** ${result.avgRating.toFixed(1)}/10

---

## Top Issues

${result.topIssues.length > 0
    ? result.topIssues.map((issue, i) => `${i + 1}. ${issue}`).join('\n')
    : 'No significant issues detected'}

## Frustration Patterns

`;

  if (result.frustrations.length === 0) {
    content += '*No frustration patterns detected*\n\n';
  } else {
    for (const f of result.frustrations) {
      content += `### ${f.pattern}

- **Occurrences:** ${f.count}
- **Avg Rating:** ${f.avgRating.toFixed(1)}
- **Confidence:** ${(f.avgConfidence * 100).toFixed(0)}%
- **Examples:**
${f.examples.map(e => `  - "${e}"`).join('\n')}

`;
    }
  }

  content += `## Success Patterns

`;

  if (result.successes.length === 0) {
    content += '*No success patterns detected*\n\n';
  } else {
    for (const s of result.successes) {
      content += `### ${s.pattern}

- **Occurrences:** ${s.count}
- **Avg Rating:** ${s.avgRating.toFixed(1)}
- **Examples:**
${s.examples.map(e => `  - "${e}"`).join('\n')}

`;
    }
  }

  content += `## Recommendations

${result.recommendations.map((r, i) => `${i + 1}. ${r}`).join('\n')}

---

*Generated by LearningPatternSynthesis tool*
`;

  return content;
}

function writeSynthesis(result: SynthesisResult, period: string): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');

  const monthDir = path.join(SYNTHESIS_DIR, `${year}-${month}`);
  if (!fs.existsSync(monthDir)) {
    fs.mkdirSync(monthDir, { recursive: true });
  }

  const dateStr = now.toISOString().split('T')[0];
  const filename = `${dateStr}_${period.toLowerCase().replace(/\s+/g, '-')}-patterns.md`;
  const filepath = path.join(monthDir, filename);

  const content = formatSynthesisReport(result);
  fs.writeFileSync(filepath, content);

  return filepath;
}

// ============================================================================
// CLI
// ============================================================================

const { values } = parseArgs({
  args: Bun.argv.slice(2),
  options: {
    week: { type: "boolean" },
    month: { type: "boolean" },
    all: { type: "boolean" },
    "dry-run": { type: "boolean" },
    json: { type: "boolean" },
    help: { type: "boolean", short: "h" },
  },
});

const asJson = !!values.json;
const log = (msg: string) => { if (!asJson) console.log(msg); };
const emit = (obj: Record<string, unknown>) => {
  if (asJson) console.log(JSON.stringify(obj, null, 2));
};

if (values.help) {
  console.log(`
LearningPatternSynthesis - Aggregate ratings into actionable patterns

Usage:
  bun run LearningPatternSynthesis.ts --week      Analyze last 7 days (default)
  bun run LearningPatternSynthesis.ts --month     Analyze last 30 days
  bun run LearningPatternSynthesis.ts --all       Analyze all ratings
  bun run LearningPatternSynthesis.ts --dry-run   Preview without writing
  bun run LearningPatternSynthesis.ts --json      Emit structured JSON

Output: Creates synthesis report in MEMORY/LEARNING/SYNTHESIS/YYYY-MM/
`);
  process.exit(0);
}

// Read all ratings (unavailable when the signal source is absent)
if (!fs.existsSync(RATINGS_FILE)) {
  log(`No ratings file found at: ${RATINGS_FILE}`);
  emit({ status: "unavailable", reason: "No ratings.jsonl signal source", ratings_file: RATINGS_FILE });
  process.exit(0);
}

const content = fs.readFileSync(RATINGS_FILE, "utf-8");
const allRatings: Rating[] = content
  .split("\n")
  .filter((line) => line.trim())
  .map((line) => { try { return JSON.parse(line); } catch { return null; } })
  .filter((r): r is Rating => r !== null);

log(`📊 Loaded ${allRatings.length} total ratings`);

// Insufficient data for a meaningful synthesis
if (allRatings.length < MIN_RATINGS) {
  log(`Insufficient ratings for synthesis (have ${allRatings.length}, need ${MIN_RATINGS})`);
  emit({ status: "no_data", reason: `Fewer than ${MIN_RATINGS} ratings`, total_ratings: allRatings.length });
  process.exit(0);
}

// Determine period and filter
let period = "Weekly";
let cutoffDate = new Date();
if (values.month) { period = "Monthly"; cutoffDate.setDate(cutoffDate.getDate() - 30); }
else if (values.all) { period = "All Time"; cutoffDate = new Date(0); }
else { cutoffDate.setDate(cutoffDate.getDate() - 7); }

const filteredRatings = allRatings.filter((r) => new Date(r.timestamp) >= cutoffDate);
log(`🔍 Analyzing ${filteredRatings.length} ratings for ${period.toLowerCase()} period`);

if (filteredRatings.length === 0) {
  log("✅ No ratings in this period");
  emit({ status: "no_data", reason: "No ratings in selected period", period, total_ratings: allRatings.length });
  process.exit(0);
}

const result = analyzeRatings(filteredRatings, period);

log(`\n📈 Analysis Results:`);
log(`   Average Rating: ${result.avgRating.toFixed(1)}/10`);
log(`   Frustration Patterns: ${result.frustrations.length}`);
log(`   Success Patterns: ${result.successes.length}`);
if (result.topIssues.length > 0) {
  log(`\n⚠️  Top Issues:`);
  for (const issue of result.topIssues) log(`   - ${issue}`);
}

let filepath: string | null = null;
if (values["dry-run"]) {
  log("\n🔍 DRY RUN - Would write synthesis report");
  log("\nRecommendations:");
  for (const rec of result.recommendations) log(`   - ${rec}`);
} else {
  filepath = writeSynthesis(result, period);
  log(`\n✅ Created synthesis report: ${path.basename(filepath)}`);
}

emit({
  status: "ok",
  period,
  dry_run: !!values["dry-run"],
  total_ratings: allRatings.length,
  analyzed: filteredRatings.length,
  avg_rating: result.avgRating,
  frustration_patterns: result.frustrations.length,
  success_patterns: result.successes.length,
  top_issues: result.topIssues,
  recommendations: result.recommendations,
  filepath,
});
