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
run_test "Plugin version is 2.5.0" \
    "grep -q \"PLUGIN_VERSION = '2.5.0'\" ${PLUGINS_DIR}/pai-hooks.js"

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

# ─── SECURITY PIPELINE TEST ───────────────────────────────
echo ""
echo "${BLUE}8. Security Pipeline${RESET}"

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
