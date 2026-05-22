#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  PAI Canonical Runtime E2E Validation
#  Small set of real runtime flows beyond structural/grep checks
# ═══════════════════════════════════════════════════════════

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Detect if running from runtime (~/.config/opencode/PAI/bin) or from repo
if [ -d "${REPO_ROOT}/opencode/tests/e2e-runtime" ]; then
    E2E_DIR="${REPO_ROOT}/opencode/tests/e2e-runtime"
elif [ -d "${HOME}/PAI-opencode/opencode/tests/e2e-runtime" ]; then
    E2E_DIR="${HOME}/PAI-opencode/opencode/tests/e2e-runtime"
else
    echo "Error: Cannot find e2e-runtime scenarios directory"
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

pass() { echo -e "  ${GREEN}PASS${RESET} $1"; }
fail() { echo -e "  ${RED}FAIL${RESET} $1"; }
info() { echo -e "  ${BLUE}INFO${RESET} $1"; }
section() { echo ""; echo -e "${BLUE}$1${RESET}"; }

TOTAL=0
PASSED=0
FAILED=0

run_scenario() {
    local name="$1"
    shift
    local file="$1"
    shift
    TOTAL=$((TOTAL + 1))
    
    local result
    result=$(bun run "${E2E_DIR}/${file}" "$@" 2>&1) || true
    
    if echo "$result" | grep -q "^E2E_PASS"; then
        pass "$name"
        PASSED=$((PASSED + 1))
    else
        fail "$name"
        FAILED=$((FAILED + 1))
        # Show error detail on failure
        local detail
        detail=$(echo "$result" | grep "^E2E_FAIL" | head -1)
        if [ -n "$detail" ]; then
            echo -e "    ${RED}→${RESET} ${detail#E2E_FAIL: }"
        fi
    fi
}

echo "═══════════════════════════════════════════════════"
echo "  PAI Canonical Runtime E2E Validation"
echo "═══════════════════════════════════════════════════"
echo ""

section "1. Prompt Security Path"
run_scenario "Dangerous prompt blocked pre-sanitization" "01-prompt-security.js"
run_scenario "Safe prompt allowed" "01-prompt-security.js" --safe

section "2. Mode Selection Path"
run_scenario "Trivial ask → MINIMAL" "02-mode-selection.js"
run_scenario "Complex ask → ALGORITHM" "02-mode-selection.js" --complex

section "3. Session Lifecycle Path"
run_scenario "Create → work → idle → delete" "03-session-lifecycle.js"

section "4. ISA/State Sync Path"
run_scenario "ISA update propagates to work.json" "04-isa-sync.js"

section "5. Passive Satisfaction Path"
run_scenario "Explicit rating captured" "05-satisfaction.js"
run_scenario "Praise detected" "05-satisfaction.js" --praise

section "6. Permission/Security Path"
run_scenario "rm -rf blocked" "06-security-path.js"
run_scenario "curl | bash blocked" "06-security-path.js" --curl

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Results: ${PASSED}/${TOTAL} passed"
echo "═══════════════════════════════════════════════════"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All E2E scenarios passed ✅${RESET}"
    exit 0
else
    echo -e "${YELLOW}${FAILED} scenario(s) failed. Review output above.${RESET}"
    exit 1
fi
