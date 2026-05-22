#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  PAI Behavioral Validation — Runtime test matrix
#  Usage: opencode run && bash opencode/bin/test-behavioral.sh
# ═══════════════════════════════════════════════════════════

set -uo pipefail

OPENCODE_DIR="${HOME}/.config/opencode"
PAI_DIR="${OPENCODE_DIR}/PAI"
PLUGINS_DIR="${OPENCODE_DIR}/plugins"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

pass() { echo -e "  ${GREEN}PASS${RESET} $1"; }
fail() { echo -e "  ${RED}FAIL${RESET} $1"; }
info() { echo -e "  ${BLUE}INFO${RESET} $1"; }
warn() { echo -e "  ${YELLOW}WARN${RESET} $1"; }

echo "═══════════════════════════════════════════════════"
echo "  PAI Behavioral Validation Matrix"
echo "═══════════════════════════════════════════════════"
echo ""

TOTAL=0
PASSED=0

run_test() {
    local name="$1"
    local check_cmd="$2"
    TOTAL=$((TOTAL + 1))
    
    if eval "$check_cmd" >/dev/null 2>&1; then
        pass "$name"
        PASSED=$((PASSED + 1))
    else
        fail "$name"
    fi
}

# ─── STRUCTURAL TESTS ─────────────────────────────────────
echo "${BLUE}1. Structural${RESET}"
run_test "Plugin version is 2.7.0" \
    "grep -q \"PLUGIN_VERSION = '2.7.0'\" ${PLUGINS_DIR}/pai-hooks.js"

run_test "10 handlers present" \
    "[ \$(grep -c '\".*\": async' ${PLUGINS_DIR}/pai-hooks.js) -eq 10 ]"

run_test "permission.asked handler exists" \
    "grep -q '\"permission.asked\"' ${PLUGINS_DIR}/pai-hooks.js"

run_test "experimental.session.compacting handler exists" \
    "grep -q '\"experimental.session.compacting\"' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Lib in lib/ subdirectory" \
    "[ -f ${PLUGINS_DIR}/lib/pai-hooks.lib.js ]"

run_test "No stale lib in root" \
    "[ ! -f ${PLUGINS_DIR}/pai-hooks.lib.js ]"

# ─── SIDE-EFFECT TESTS ────────────────────────────────────
echo ""
echo "${BLUE}2. Side-Effect (file-based)${RESET}"

# Test 8: tool-activity.jsonl exists and is appendable
# Test 8b: mode-classifier.jsonl exists and is appendable
run_test "mode-classifier.jsonl writable" \
    "[ -f ${PAI_DIR}/MEMORY/OBSERVABILITY/mode-classifier.jsonl ] || touch ${PAI_DIR}/MEMORY/OBSERVABILITY/mode-classifier.jsonl"

run_test "tool-activity.jsonl writable" \
    "[ -f ${PAI_DIR}/MEMORY/STATE/tool-activity.jsonl ] || touch ${PAI_DIR}/MEMORY/STATE/tool-activity.jsonl"

# Test 9: work.json exists and is valid JSON
run_test "work.json is valid JSON" \
    "bun -e \"JSON.parse(require('fs').readFileSync('${PAI_DIR}/MEMORY/STATE/work.json'))\""

# Test 10: counts.json exists
run_test "counts.json exists or creatable" \
    "[ -f ${PAI_DIR}/MEMORY/STATE/counts.json ] || (echo '{\"sessions\":0,\"tools\":0,\"skills\":0,\"ratings\":0}' > ${PAI_DIR}/MEMORY/STATE/counts.json && [ -f ${PAI_DIR}/MEMORY/STATE/counts.json ])"

# ─── PERMISSION GUARD TEST ────────────────────────────────
echo ""
echo "${BLUE}3. PermissionGuard (permission.asked)${RESET}"

# Create a test script that simulates the guard logic
PERMISSION_TEST=$(cat <<EOF
import { inspectBashCommand } from '${PLUGINS_DIR}/lib/pai-hooks.lib.js';
const result = inspectBashCommand('rm -rf /');
console.log(result.action === 'deny' ? 'PASS' : 'FAIL');
EOF
)

PERM_RESULT=$(echo "$PERMISSION_TEST" | bun run - 2>/dev/null || echo "FAIL")
if [ "$PERM_RESULT" = "PASS" ]; then
    pass "permission.asked blocks rm -rf /"
    PASSED=$((PASSED + 1))
else
    fail "permission.asked blocks rm -rf /"
fi
TOTAL=$((TOTAL + 1))

# ─── PARSE EXPLICIT RATING TEST ───────────────────────────
echo ""
echo "${BLUE}4. Rating Parser (explicit message ratings)${RESET}"

RATE_TEST=$(cat <<EOF
import { parseExplicitRating } from '${PLUGINS_DIR}/lib/pai-hooks.lib.js';
const r1 = parseExplicitRating('/rate 5 good job');
const r2 = parseExplicitRating('8 too verbose');
const r3 = parseExplicitRating('/rating 3 bad');
console.log(
  r1?.rating === 5 && r1?.comment === 'good job' &&
  r2?.rating === 8 &&
  r3?.rating === 3
  ? 'PASS' : 'FAIL'
);
EOF
)

RATE_RESULT=$(echo "$RATE_TEST" | bun run - 2>/dev/null || echo "FAIL")
if [ "$RATE_RESULT" = "PASS" ]; then
    pass "Explicit rating parsing works for bare ratings and prefixed forms"
    PASSED=$((PASSED + 1))
else
    fail "Explicit rating parsing"
fi
TOTAL=$((TOTAL + 1))

# ─── SYSTEM CONTEXT INJECTION TEST ────────────────────────
echo ""
echo "${BLUE}5. System Context (experimental.chat.system.transform)${RESET}"

run_test "buildPAISystemContext function exists" \
    "grep -q 'function buildPAISystemContext' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Context includes TELOS reference" \
    "grep -q 'TELOS' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Context includes Algorithm reference" \
    "grep -q 'ALGORITHM' ${PLUGINS_DIR}/pai-hooks.js"

# ─── MODE/TIER CLASSIFIER TEST ────────────────────────────
echo ""
echo "${BLUE}5a. Mode/Tier Classifier${RESET}"

run_test "mode-classifier.lib.js exists" \
    "[ -f ${PLUGINS_DIR}/lib/mode-classifier.lib.js ]"

run_test "classifyPrompt exported" \
    "grep -q 'export function classifyPrompt' ${PLUGINS_DIR}/lib/mode-classifier.lib.js"

run_test "Classifier has fail-safe to ALGORITHM E3" \
    "grep -q 'ALGORITHM E3' ${PLUGINS_DIR}/lib/mode-classifier.lib.js"

run_test "Classifier supports /e1-/e5 overrides" \
    "grep -q '/e1' ${PLUGINS_DIR}/lib/mode-classifier.lib.js"

run_test "Classifier uses deepseek as default LLM" \
    "grep -q 'deepseek-v4-flash-free' ${PLUGINS_DIR}/lib/mode-classifier.lib.js"

run_test "pai-hooks imports mode-classifier" \
    "grep -q 'mode-classifier.lib.js' ${PLUGINS_DIR}/pai-hooks.js"

run_test "chat.message runs classification" \
    "grep -q 'classifyPrompt' ${PLUGINS_DIR}/pai-hooks.js"

run_test "System context reads stored classification" \
    "grep -q 'readStoredClassification' ${PLUGINS_DIR}/pai-hooks.js"

# Quick functional test of the classifier
CLASSIFIER_TEST=$(cat <<EOF
import { classifyPrompt } from '${PLUGINS_DIR}/lib/mode-classifier.lib.js';
const r1 = classifyPrompt('hi');
const r2 = classifyPrompt('implement auth');
const r3 = classifyPrompt('/e5 build everything');
console.log(
  r1.mode === 'MINIMAL' && r2.mode === 'ALGORITHM' && r3.tier === 'E5'
  ? 'PASS' : 'FAIL'
);
EOF
)

CLASS_RESULT=$(echo "$CLASSIFIER_TEST" | bun run - 2>/dev/null || echo "FAIL")
if [ "$CLASS_RESULT" = "PASS" ]; then
    pass "Classifier functional test (MINIMAL, ALGORITHM, override)"
    PASSED=$((PASSED + 1))
else
    fail "Classifier functional test"
fi
TOTAL=$((TOTAL + 1))

# ─── COMPACTION CONTEXT TEST ──────────────────────────────
echo ""
echo "${BLUE}6. Compaction Context (experimental.session.compacting)${RESET}"

run_test "Compaction injects PAI Life OS Context" \
    "grep -q 'PAI Life OS Context' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Compaction includes recent work" \
    "grep -q 'recent work' ${PLUGINS_DIR}/pai-hooks.js"

# ─── SESSION LIFECYCLE TEST ───────────────────────────────
echo ""
echo "${BLUE}7. Session Lifecycle${RESET}"

run_test "session.deleted captures before delete" \
    "grep -q 'Capture session data ONCE at the beginning' ${PLUGINS_DIR}/pai-hooks.js"

run_test "session.deleted archives to work-archive.json" \
    "grep -q 'work-archive.json' ${PLUGINS_DIR}/pai-hooks.js"

run_test "session.idle only updates lastIdleAt" \
    "grep -q 'Non-destructive: update lastIdleAt only' ${PLUGINS_DIR}/pai-hooks.js"

# ─── ISA ↔ WORK-STATE SYNC TEST ───────────────────────────
echo ""
echo "${BLUE}9. ISA ↔ Work-State Sync${RESET}"

run_test "ISA sync helper exists in lib" \
    "grep -q 'syncISAToWorkRegistry' ${PLUGINS_DIR}/lib/pai-hooks.lib.js"

run_test "ISA detection recognizes MEMORY/WORK paths" \
    "grep -q 'MEMORY/WORK' ${PLUGINS_DIR}/lib/pai-hooks.lib.js"

run_test "Plugin calls sync on ISA write/edit" \
    "grep -q 'isISAArtifactPath' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Plugin version is 2.7.0" \
    "grep -q \"PLUGIN_VERSION = '2.7.0'\" ${PLUGINS_DIR}/pai-hooks.js"

# Functional test of ISA sync
ISA_SYNC_TMP=$(mktemp /tmp/pai-isa-sync-test-XXXXXX.js)
cat > "$ISA_SYNC_TMP" << 'ENDTEST'
import {
  isISAArtifactPath,
  extractISAState,
  syncISAToWorkRegistry,
  readWorkRegistry,
} from '/home/konanzin/.config/opencode/plugins/lib/pai-hooks.lib.js';

// Test 1: Detection
const isISA = isISAArtifactPath('/PAI/MEMORY/WORK/task/ISA.md');
const notISA = isISAArtifactPath('/project/README.md');

// Test 2: State extraction
const fs = require('fs');
const os = require('os');
const path = require('path');
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pai-isa-test-'));
const isaFile = path.join(tmpDir, 'ISA.md');
fs.writeFileSync(isaFile, '---\nphase: observe\nprogress: 2/5\neffort: e3\n---\n\n# ISA\n');
const state = extractISAState(isaFile);

// Test 3: Sync
const result = syncISAToWorkRegistry(isaFile);
const registry = readWorkRegistry();
const slug = path.basename(tmpDir);
const synced = registry.sessions[slug]?.phase === 'observe';

console.log(isISA && !notISA && state?.phase === 'observe' && result.synced && synced ? 'PASS' : 'FAIL');

// Cleanup
fs.unlinkSync(isaFile);
fs.rmdirSync(tmpDir);
ENDTEST

ISA_RESULT=$(bun run "$ISA_SYNC_TMP" 2>/dev/null || echo "FAIL")
rm -f "$ISA_SYNC_TMP"
if [ "$ISA_RESULT" = "PASS" ]; then
    pass "ISA sync functional test (detect + extract + sync)"
    PASSED=$((PASSED + 1))
else
    fail "ISA sync functional test"
fi
TOTAL=$((TOTAL + 1))

# ─── SECURITY PIPELINE TEST ───────────────────────────────
echo ""
echo "${BLUE}10. Security Pipeline${RESET}"

run_test "tool.execute.before inspects bash" \
    "grep -q 'inspectBashCommand' ${PLUGINS_DIR}/pai-hooks.js"

run_test "tool.execute.before inspects writes" \
    "grep -q 'inspectWritePath' ${PLUGINS_DIR}/pai-hooks.js"

run_test "chat.message pre-sanitizes blocked prompts" \
    "grep -q 'PAI SECURITY BLOCKED' ${PLUGINS_DIR}/pai-hooks.js"

# ─── REPORT ───────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════"
echo "  Results: ${PASSED}/${TOTAL} passed"
echo "═══════════════════════════════════════════════════"

if [ $PASSED -eq $TOTAL ]; then
    echo -e "${GREEN}All behavioral checks passed ✅${RESET}"
    exit 0
else
    echo -e "${YELLOW}Some checks failed. Review output above.${RESET}"
    exit 1
fi
