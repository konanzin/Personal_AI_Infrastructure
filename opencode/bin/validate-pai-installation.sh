#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  PAI Installation Validator
#  68 checkpoints across 12 categories
# ═══════════════════════════════════════════════════════════

set -uo pipefail

# ─── Colors ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# ─── Paths ────────────────────────────────────────────────
PAI_DIR="${HOME}/.config/opencode/PAI"
OPENCODE_DIR="${HOME}/.config/opencode"

# ─── Counters ─────────────────────────────────────────────
TOTAL=0
PASSED=0
FAILED=0

# ─── Logging ──────────────────────────────────────────────
pass() { 
    PASSED=$((PASSED + 1))
    TOTAL=$((TOTAL + 1))
    echo -e "  ${GREEN}✓${RESET} $1"
}
fail() { 
    FAILED=$((FAILED + 1))
    TOTAL=$((TOTAL + 1))
    echo -e "  ${RED}✗${RESET} $1"
}
warn() { echo -e "  ${YELLOW}⚠${RESET} $1"; }
section() { echo ""; echo -e "${BLUE}$1${RESET}"; }

# ═══════════════════════════════════════════════════════════
#  CHECKPOINTS
# ═══════════════════════════════════════════════════════════

check_base_structure() {
    section "1. Base Structure"
    local checks=0
    local passed=0
    
    if [ -d "$PAI_DIR" ]; then
        pass "PAI directory exists"
        passed=$((passed + 1))
    else
        fail "PAI directory missing"
    fi
    checks=$((checks + 1))
    
    if [ -L "${HOME}/.claude" ] || [ -d "${HOME}/.claude" ]; then
        pass "~/.claude accessible (backward compat)"
        passed=$((passed + 1))
    else
        pass "~/.claude removed (clean OpenCode install)"
        passed=$((passed + 1))
    fi
    checks=$((checks + 1))
    
    if [ -f "${OPENCODE_DIR}/opencode.jsonc" ]; then
        pass "opencode.jsonc exists"
        passed=$((passed + 1))
    else
        fail "opencode.jsonc missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/.env" ]; then
        pass ".env exists"
        passed=$((passed + 1))
    else
        fail ".env missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/.pai-protected.json" ]; then
        pass ".pai-protected.json exists"
        passed=$((passed + 1))
    else
        fail ".pai-protected.json missing"
    fi
    checks=$((checks + 1))
    
    if [ -d "${OPENCODE_DIR}/plugins" ]; then
        pass "plugins/ directory exists"
        passed=$((passed + 1))
    else
        fail "plugins/ directory missing"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_memory() {
    section "2. Memory System"
    local checks=0
    local passed=0
    
    if [ -d "$PAI_DIR/MEMORY/STATE" ]; then
        pass "MEMORY/STATE/ exists"
        passed=$((passed + 1))
    else
        fail "MEMORY/STATE/ missing"
    fi
    checks=$((checks + 1))
    
    if [ -d "$PAI_DIR/MEMORY/WORK" ]; then
        pass "MEMORY/WORK/ exists"
        passed=$((passed + 1))
    else
        fail "MEMORY/WORK/ missing"
    fi
    checks=$((checks + 1))
    
    if [ -d "$PAI_DIR/MEMORY/KNOWLEDGE" ]; then
        pass "MEMORY/KNOWLEDGE/ exists"
        passed=$((passed + 1))
    else
        fail "MEMORY/KNOWLEDGE/ missing"
    fi
    checks=$((checks + 1))
    
    if [ -d "$PAI_DIR/MEMORY/LEARNING" ]; then
        pass "MEMORY/LEARNING/ exists"
        passed=$((passed + 1))
    else
        fail "MEMORY/LEARNING/ missing"
    fi
    checks=$((checks + 1))
    
    if [ -d "$PAI_DIR/MEMORY/RESEARCH" ]; then
        pass "MEMORY/RESEARCH/ exists"
        passed=$((passed + 1))
    else
        fail "MEMORY/RESEARCH/ missing"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_config() {
    section "3. Configuration"
    local checks=0
    local passed=0
    
    local line_count=$(wc -l < "${OPENCODE_DIR}/opencode.jsonc")
    if [ "$line_count" -gt 50 ]; then
        pass "opencode.jsonc has $line_count lines (>50)"
        passed=$((passed + 1))
    else
        fail "opencode.jsonc too small ($line_count lines)"
    fi
    checks=$((checks + 1))
    
    if grep -q '"command"' "${OPENCODE_DIR}/opencode.jsonc"; then
        pass "Commands configured"
        passed=$((passed + 1))
    else
        fail "Commands missing"
    fi
    checks=$((checks + 1))
    
    if grep -q '"agent"' "${OPENCODE_DIR}/opencode.jsonc"; then
        pass "Agents configured"
        passed=$((passed + 1))
    else
        fail "Agents missing"
    fi
    checks=$((checks + 1))
    
    if grep -q '"plugin"' "${OPENCODE_DIR}/opencode.jsonc"; then
        pass "Plugins configured"
        passed=$((passed + 1))
    else
        fail "Plugins missing"
    fi
    checks=$((checks + 1))

    if grep -q 'Default PAI primary agent' "${OPENCODE_DIR}/opencode.jsonc"; then
        pass "Default build agent is PAI-aware"
        passed=$((passed + 1))
    else
        fail "Default build agent is not PAI-aware"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/.version.json" ]; then
        pass ".version.json exists"
        passed=$((passed + 1))
    else
        fail ".version.json missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/.preferences.json" ]; then
        pass ".preferences.json exists"
        passed=$((passed + 1))
    else
        fail ".preferences.json missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/.techstack.json" ]; then
        pass ".techstack.json exists"
        passed=$((passed + 1))
    else
        fail ".techstack.json missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/.observability.json" ]; then
        pass ".observability.json exists"
        passed=$((passed + 1))
    else
        fail ".observability.json missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/.notifications.json" ]; then
        pass ".notifications.json exists"
        passed=$((passed + 1))
    else
        fail ".notifications.json missing"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_skills() {
    section "4. Skills"
    local checks=0
    local passed=0
    
    local skill_count=$(ls "${HOME}/.config/opencode/skills/" 2>/dev/null | wc -l)
    if [ "$skill_count" -ge 10 ]; then
        pass "$skill_count skills installed (target: 48+)"
        passed=$((passed + 1))
    else
        fail "Only $skill_count skills found"
    fi
    checks=$((checks + 1))
    
    if [ -f "${HOME}/.config/opencode/skills/ISA/SKILL.md" ]; then
        pass "ISA skill exists"
        passed=$((passed + 1))
    else
        fail "ISA skill missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "${HOME}/.config/opencode/skills/Telos/SKILL.md" ]; then
        pass "Telos skill exists"
        passed=$((passed + 1))
    else
        fail "Telos skill missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "${HOME}/.config/opencode/skills/Knowledge/SKILL.md" ]; then
        pass "Knowledge skill exists"
        passed=$((passed + 1))
    else
        fail "Knowledge skill missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "${HOME}/.config/opencode/skills/Research/SKILL.md" ]; then
        pass "Research skill exists"
        passed=$((passed + 1))
    else
        fail "Research skill missing"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_plugins() {
    section "5. Hooks/Plugins"
    local checks=0
    local passed=0
    
    if [ -f "${OPENCODE_DIR}/plugins/pai-hooks.js" ]; then
        pass "pai-hooks.js exists"
        passed=$((passed + 1))
    else
        fail "pai-hooks.js missing"
    fi
    checks=$((checks + 1))
    
    # Check lib is in subdirectory (not auto-loaded as plugin)
    if [ -f "${OPENCODE_DIR}/plugins/lib/pai-hooks.lib.js" ]; then
        pass "pai-hooks.lib.js in lib/ subdirectory (correct)"
        passed=$((passed + 1))
    elif [ -f "${OPENCODE_DIR}/plugins/pai-hooks.lib.js" ]; then
        fail "pai-hooks.lib.js in plugins/ root — will be auto-loaded as plugin"
    else
        warn "pai-hooks.lib.js not found"
    fi
    checks=$((checks + 1))
    
    # Check for duplicate plugin registration
    local plugin_refs=$(grep -o '"\.\/plugins\/pai-hooks\.js"' "${OPENCODE_DIR}/opencode.jsonc" 2>/dev/null | wc -l)
    if [ "$plugin_refs" -eq 1 ]; then
        pass "Plugin registered once in config"
        passed=$((passed + 1))
    elif [ "$plugin_refs" -gt 1 ]; then
        fail "Plugin registered $plugin_refs times (duplicate)"
    else
        fail "Plugin not registered in config"
    fi
    checks=$((checks + 1))
    
    # Check for critical isUserMessage bug fix
    if grep -q "const isUserMessage =" "${OPENCODE_DIR}/plugins/pai-hooks.js"; then
        pass "isUserMessage defined at top of message.updated"
        passed=$((passed + 1))
    else
        fail "isUserMessage not found — critical bug not fixed"
    fi
    checks=$((checks + 1))
    
    # Check session.deleted handler exists
    if grep -q '"session.deleted"' "${OPENCODE_DIR}/plugins/pai-hooks.js"; then
        pass "session.deleted handler exists"
        passed=$((passed + 1))
    else
        fail "session.deleted handler missing"
    fi
    checks=$((checks + 1))

    if grep -q '"experimental.chat.system.transform"' "${OPENCODE_DIR}/plugins/pai-hooks.js" && grep -q '"chat.message"' "${OPENCODE_DIR}/plugins/pai-hooks.js"; then
        pass "Default PAI runtime injection hooks exist"
        passed=$((passed + 1))
    else
        fail "Default PAI runtime injection hooks missing"
    fi
    checks=$((checks + 1))

    # Check permission.asked hook exists (notified security denials)
    if grep -q '"permission.asked"' "${OPENCODE_DIR}/plugins/pai-hooks.js"; then
        pass "permission.asked hook exists"
        passed=$((passed + 1))
    else
        fail "permission.asked hook missing"
    fi
    checks=$((checks + 1))

    # Check rm -rf is in BLOCKED_PATTERNS (explicit model-visible block)
    if grep -q 'rm -rf detected' "${OPENCODE_DIR}/plugins/lib/pai-hooks.lib.js"; then
        pass "rm -rf in BLOCKED_PATTERNS (explicit fail)"
        passed=$((passed + 1))
    else
        fail "rm -rf not in BLOCKED_PATTERNS"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_agents() {
    section "6. Agents"
    local checks=0
    local passed=0
    
    local agent_count=$(ls "${OPENCODE_DIR}/agents/"*.md 2>/dev/null | wc -l)
    if [ "$agent_count" -ge 18 ]; then
        pass "$agent_count agents installed"
        passed=$((passed + 1))
    else
        fail "Only $agent_count agents found"
    fi
    checks=$((checks + 1))
    
    local agents=("Algorithm" "Anvil" "Architect" "Arthur" "Artist" "BrowserAgent" "Cato" "ClaudeResearcher" "CodexResearcher" "Designer" "Engineer" "Forge" "GeminiResearcher" "GrokResearcher" "PerplexityResearcher" "QATester" "Silas" "UIReviewer")
    
    for agent in "${agents[@]}"; do
        if [ -f "${OPENCODE_DIR}/agents/${agent}.md" ]; then
            pass "${agent}.md exists"
            passed=$((passed + 1))
        else
            fail "${agent}.md missing"
        fi
        checks=$((checks + 1))
    done
    
    if grep -q '"pai"' "${OPENCODE_DIR}/opencode.jsonc" && grep -q '"agent": "Algorithm"' "${OPENCODE_DIR}/opencode.jsonc"; then
        pass "Algorithm command references Algorithm agent"
        passed=$((passed + 1))
    else
        fail "Algorithm command does not reference Algorithm agent"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_commands() {
    section "7. Commands"
    local checks=0
    local passed=0
    
    if grep -q '"pai"' "${OPENCODE_DIR}/opencode.jsonc"; then
        pass "/pai command registered"
        passed=$((passed + 1))
    else
        fail "/pai missing"
    fi
    checks=$((checks + 1))
    
    if grep -q '"status"' "${OPENCODE_DIR}/opencode.jsonc"; then
        pass "/status command registered"
        passed=$((passed + 1))
    else
        fail "/status missing"
    fi
    checks=$((checks + 1))
    
    if grep -q '"interview"' "${OPENCODE_DIR}/opencode.jsonc"; then
        pass "/interview command registered"
        passed=$((passed + 1))
    else
        fail "/interview missing"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_tools() {
    section "8. Tools"
    local checks=0
    local passed=0
    
    if [ -d "$PAI_DIR/TOOLS" ]; then
        pass "TOOLS/ directory exists"
        passed=$((passed + 1))
    else
        fail "TOOLS/ missing"
    fi
    checks=$((checks + 1))
    
    if [ -d "$PAI_DIR/bin" ]; then
        pass "bin/ directory exists"
        passed=$((passed + 1))
    else
        fail "bin/ missing"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_documentation() {
    section "9. Documentation"
    local checks=0
    local passed=0
    
    if [ -d "$PAI_DIR/DOCUMENTATION" ]; then
        pass "DOCUMENTATION/ exists"
        passed=$((passed + 1))
    else
        fail "DOCUMENTATION/ missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/CLAUDE.md" ]; then
        pass "CLAUDE.md exists"
        passed=$((passed + 1))
    else
        fail "CLAUDE.md missing"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_pulse() {
    section "10. Pulse"
    local checks=0
    local passed=0
    
    if [ -d "$PAI_DIR/PULSE" ]; then
        pass "PULSE/ directory exists"
        passed=$((passed + 1))
    else
        fail "PULSE/ missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/PULSE/PULSE.toml" ]; then
        pass "PULSE.toml exists"
        passed=$((passed + 1))
    else
        fail "PULSE.toml missing"
    fi
    checks=$((checks + 1))
    
    local claude_refs=$(grep -r "\.claude/" "$PAI_DIR/PULSE/" --include="*.ts" --include="*.sh" --include="*.toml" -l --exclude-dir=node_modules --exclude-dir=.next --exclude-dir=out 2>/dev/null | grep -v patch-paths.sh | wc -l)
    if [ "$claude_refs" -eq 0 ]; then
        pass "No hardcoded ~/.claude/ paths (all migrated to ~/.config/opencode/)"
        passed=$((passed + 1))
    else
        fail "$claude_refs files still have ~/.claude/ refs (should be ~/.config/opencode/)"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_algorithm() {
    section "11. Algorithm"
    local checks=0
    local passed=0
    
    if [ -d "$PAI_DIR/ALGORITHM" ]; then
        pass "ALGORITHM/ exists"
        passed=$((passed + 1))
    else
        fail "ALGORITHM/ missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/ALGORITHM/LATEST" ]; then
        pass "LATEST file exists"
        passed=$((passed + 1))
    else
        fail "LATEST missing"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_user() {
    section "12. User/TELOS"
    local checks=0
    local passed=0
    
    if [ -d "$PAI_DIR/USER" ]; then
        pass "USER/ exists"
        passed=$((passed + 1))
    else
        fail "USER/ missing"
    fi
    checks=$((checks + 1))
    
    if [ -d "$PAI_DIR/USER/TELOS" ]; then
        pass "USER/TELOS/ exists"
        passed=$((passed + 1))
    else
        fail "USER/TELOS/ missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/USER/PRINCIPAL_IDENTITY.md" ]; then
        pass "PRINCIPAL_IDENTITY.md exists"
        passed=$((passed + 1))
    else
        fail "PRINCIPAL_IDENTITY.md missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/USER/DA_IDENTITY.md" ]; then
        pass "DA_IDENTITY.md exists"
        passed=$((passed + 1))
    else
        fail "DA_IDENTITY.md missing"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

# ═══════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════

main() {
    echo "═══════════════════════════════════════════════════"
    echo "  PAI Installation Validation"
    echo "═══════════════════════════════════════════════════"
    echo ""
    
    local total_failed=0
    
    check_base_structure; local ret=$?; ((total_failed += ret))
    check_memory; local ret=$?; ((total_failed += ret))
    check_config; local ret=$?; ((total_failed += ret))
    check_skills; local ret=$?; ((total_failed += ret))
    check_plugins; local ret=$?; ((total_failed += ret))
    check_agents; local ret=$?; ((total_failed += ret))
    check_commands; local ret=$?; ((total_failed += ret))
    check_tools; local ret=$?; ((total_failed += ret))
    check_documentation; local ret=$?; ((total_failed += ret))
    check_pulse; local ret=$?; ((total_failed += ret))
    check_algorithm; local ret=$?; ((total_failed += ret))
    check_user; local ret=$?; ((total_failed += ret))
    
    # Report
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Validation Report"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "Total Checks:    $TOTAL"
    echo "Passed:          $PASSED"
    echo "Failed:          $FAILED"
    if [ $TOTAL -gt 0 ]; then
        echo "Success Rate:    $(( PASSED * 100 / TOTAL ))%"
    fi
    echo ""
    
    # Optional: run behavioral tests if available
    if [ -f "${PAI_DIR}/bin/test-behavioral.sh" ]; then
        echo ""
        echo "═══════════════════════════════════════════════════"
        echo "  Behavioral Tests"
        echo "═══════════════════════════════════════════════════"
        echo ""
        bash "${PAI_DIR}/bin/test-behavioral.sh" && echo "" || echo ""
    fi
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}Status: ALL CHECKS PASSED ✅${RESET}"
        exit 0
    else
        echo -e "${RED}Status: $FAILED CHECKS FAILED ❌${RESET}"
        exit 1
    fi
}

main "$@"
