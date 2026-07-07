#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════
#  PAI Installation Validator
#  Checkpoints across 12 categories
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_MANIFEST="$PAI_DIR/install-manifest.json"
CONFIG_TEMPLATE="$PAI_DIR/config/opencode.jsonc.template"

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

manifest_values() {
    local key="$1"

    if [ ! -f "$INSTALL_MANIFEST" ] || ! command -v bun &>/dev/null; then
        return 0
    fi

    MANIFEST_PATH="$INSTALL_MANIFEST" MANIFEST_KEY="$key" bun -e '
const fs = require("fs");
const data = JSON.parse(fs.readFileSync(process.env.MANIFEST_PATH, "utf8"));
for (const value of data[process.env.MANIFEST_KEY] ?? []) console.log(value);
' 2>/dev/null
}

manifest_has() {
    local key="$1"
    local value="$2"

    while IFS= read -r item; do
        [ "$item" = "$value" ] && return 0
    done < <(manifest_values "$key")

    return 1
}

manifest_count() {
    local key="$1"
    manifest_values "$key" | sed '/^$/d' | wc -l | tr -d ' '
}

# Must mirror install.sh's render_expected_config so --check / this validator and
# generate_config produce byte-identical output (no false drift). Currently:
# pai-hooks path rewrite + per-machine primary-model injection.
render_expected_config() {
    local output="$1"
    sed "s|\"./plugins/pai-hooks.js\"|\"${OPENCODE_DIR}/plugins/pai-hooks.js\"|" \
        "$CONFIG_TEMPLATE" > "$output"

    local model_file="$PAI_DIR/USER/Config/primary-model"
    if [ -f "$model_file" ]; then
        local m
        m="$(tr -d '[:space:]' < "$model_file" 2>/dev/null)"
        if [ -n "$m" ]; then
            sed -i "/PAI_MODEL_INJECTION_POINT/a\\  \"model\": \"${m}\"," "$output"
        fi
    fi
}

edge_tts_available() {
    local venv_python="${OPENCODE_DIR}/tts-venv/bin/python"
    if [ -x "$venv_python" ] && "$venv_python" -c 'import edge_tts' >/dev/null 2>&1; then
        return 0
    fi
    if command -v edge-tts &>/dev/null; then
        return 0
    fi

    local python
    for python in python3 python; do
        if command -v "$python" &>/dev/null && "$python" -c 'import edge_tts' >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

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

    if [ -f "$INSTALL_MANIFEST" ]; then
        pass "install-manifest.json exists"
        passed=$((passed + 1))
    else
        fail "install-manifest.json missing"
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
    
    # W2.9: the old ">50 lines" size check was a magic count — the template
    # drift comparison below validates the real contract (the file matches
    # what the generator produces), which subsumes any size floor.
    if [ -f "$CONFIG_TEMPLATE" ]; then
        local expected_config
        expected_config="$(mktemp)"
        render_expected_config "$expected_config"
        if cmp -s "$expected_config" "${OPENCODE_DIR}/opencode.jsonc"; then
            pass "opencode.jsonc matches generated template"
            passed=$((passed + 1))
        else
            fail "opencode.jsonc drift from generated template"
        fi
        rm -f "$expected_config"
    else
        fail "Installed opencode.jsonc template missing"
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

    if grep -q '"build-mobile"' "${OPENCODE_DIR}/opencode.jsonc"; then
        pass "build-mobile lean-profile agent configured"
        passed=$((passed + 1))
    else
        fail "build-mobile agent missing from opencode.jsonc"
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
    
    local skill_count=$(find "${HOME}/.config/opencode/skills/" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    local expected_skill_count
    expected_skill_count="$(manifest_count "skills")"
    if [ -n "$expected_skill_count" ] && [ "$expected_skill_count" -gt 0 ] && [ "$skill_count" -eq "$expected_skill_count" ]; then
        pass "$skill_count skills installed (matches manifest)"
        passed=$((passed + 1))
    else
        fail "$skill_count skills installed; manifest expects ${expected_skill_count:-unknown}"
    fi
    checks=$((checks + 1))

    local stale_skills=()
    local skill_dir
    while IFS= read -r skill_dir; do
        local skill_name
        skill_name="$(basename "$skill_dir")"
        if ! manifest_has "skills" "$skill_name"; then
            stale_skills+=("$skill_name")
        fi
    done < <(find "${HOME}/.config/opencode/skills/" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

    if [ ${#stale_skills[@]} -eq 0 ]; then
        pass "No stale skill directories installed"
        passed=$((passed + 1))
    else
        fail "Stale skill directories installed: ${stale_skills[*]}"
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
    
    # Check for duplicate plugin registration. The installer renders an
    # absolute path because OpenCode resolves relative plugin paths from the
    # server CWD; older configs may still use ./plugins.
    local relative_plugin_refs=$(grep -F -o '"./plugins/pai-hooks.js"' "${OPENCODE_DIR}/opencode.jsonc" 2>/dev/null | wc -l)
    local absolute_plugin_refs=$(grep -F -o "\"${OPENCODE_DIR}/plugins/pai-hooks.js\"" "${OPENCODE_DIR}/opencode.jsonc" 2>/dev/null | wc -l)
    local plugin_refs=$((relative_plugin_refs + absolute_plugin_refs))
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

    # Check mode classifier exists and is imported
    if [ -f "${OPENCODE_DIR}/plugins/lib/mode-classifier.lib.js" ]; then
        pass "mode-classifier.lib.js exists"
        passed=$((passed + 1))
    else
        fail "mode-classifier.lib.js missing"
    fi
    checks=$((checks + 1))

    if grep -q 'mode-classifier.lib.js' "${OPENCODE_DIR}/plugins/pai-hooks.js"; then
        pass "Plugin imports mode-classifier"
        passed=$((passed + 1))
    else
        fail "Plugin does not import mode-classifier"
    fi
    checks=$((checks + 1))

    # Default classifier model lives in the resolver (mode-classifier.lib.js),
    # not pai-hooks.js, since classifier config resolution was centralized there.
    # Assert the PROPERTY (a centralized default resolves), never a pinned
    # model id — the id is configurable and validators must not freeze it (W1.5).
    # Shape-check the resolved id (provider/model), so an empty or mangled
    # default fails here instead of at first runtime classification. A typo'd
    # but well-formed id still passes — existence is only checkable online.
    resolver_out=$(bun -e "const m = await import('${OPENCODE_DIR}/plugins/lib/mode-classifier.lib.js'); const c = m.resolveClassifierConfig({}, {}); if (typeof c.model !== 'string' || !/^[\\w.-]+\\/[\\w.-]+$/.test(c.model)) { console.error('bad model: ' + JSON.stringify(c.model)); process.exit(1); } console.log(c.model);" 2>&1)
    resolver_rc=$?
    if [ $resolver_rc -eq 0 ]; then
        pass "Classifier resolves a default LLM model (${resolver_out})"
        passed=$((passed + 1))
    elif echo "$resolver_out" | grep -q '^bad model:'; then
        fail "Classifier resolver default is not a provider/model id: ${resolver_out}"
    else
        fail "Could not evaluate classifier resolver (toolchain?): ${resolver_out}"
    fi
    checks=$((checks + 1))

    if grep -q 'classifyPrompt' "${OPENCODE_DIR}/plugins/pai-hooks.js"; then
        pass "chat.message uses classifyPrompt"
        passed=$((passed + 1))
    else
        fail "chat.message does not call classifyPrompt"
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

    # Check rm -rf is in BLOCKED_PATTERNS (policy-driven deny, model-visible reason)
    if grep -q 'Recursive deletion of system root' "${OPENCODE_DIR}/plugins/lib/pai-hooks.lib.js"; then
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
    
    # W2.9: contract check, not a count — the install manifest is the single
    # source of truth for which agents ship (same pattern the skills section
    # already uses). The old "-ge 15" plus a frozen roster array here drifted
    # the moment an agent was added or renamed.
    local agent_count=$(ls "${OPENCODE_DIR}/agents/"*.md 2>/dev/null | wc -l)
    local expected_agent_count
    expected_agent_count="$(manifest_count "agents")"
    if [ -n "$expected_agent_count" ] && [ "$expected_agent_count" -gt 0 ] && [ "$agent_count" -eq "$expected_agent_count" ]; then
        pass "$agent_count agents installed (matches manifest)"
        passed=$((passed + 1))
    else
        fail "Agent count $agent_count does not match manifest (${expected_agent_count:-unreadable})"
    fi
    checks=$((checks + 1))

    # Every manifest-declared agent must exist — names read from the manifest,
    # not a roster frozen in this script.
    while IFS= read -r agent_file; do
        [ -z "$agent_file" ] && continue
        if [ -f "${OPENCODE_DIR}/agents/${agent_file}" ]; then
            pass "${agent_file} exists"
            passed=$((passed + 1))
        else
            fail "${agent_file} missing"
        fi
        checks=$((checks + 1))
    done < <(manifest_values "agents")

    # Deprecated agents must NOT be installed (replaced by the Interceptor skill)
    local deprecated=("BrowserAgent" "QATester" "UIReviewer")
    for agent in "${deprecated[@]}"; do
        if [ ! -f "${OPENCODE_DIR}/agents/${agent}.md" ]; then
            pass "${agent}.md absent (deprecated, replaced by Interceptor skill)"
            passed=$((passed + 1))
        else
            fail "${agent}.md still installed (deprecated, should be removed)"
        fi
        checks=$((checks + 1))
    done

    # Specialists are subagents: they must not appear in client agent pickers
    # (Shift+Tab cycle, mobile picker). Only build/build-mobile are primary.
    local no_mode=$(grep -L "^mode: subagent" "${OPENCODE_DIR}/agents/"*.md 2>/dev/null | wc -l)
    if [ "$no_mode" -eq 0 ]; then
        pass "All installed agents declare mode: subagent"
        passed=$((passed + 1))
    else
        fail "$no_mode agent files missing 'mode: subagent' (would pollute agent pickers)"
    fi
    checks=$((checks + 1))
    
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
    
    if ! grep -q '"rate"' "${OPENCODE_DIR}/opencode.jsonc"; then
        pass "No stale /rate command in config"
        passed=$((passed + 1))
    else
        fail "/rate command still present in runtime config"
    fi
    checks=$((checks + 1))

    for cmd in "context-search" "cs" "pu" "voice"; do
        if grep -q "\"${cmd}\"" "${OPENCODE_DIR}/opencode.jsonc"; then
            pass "/${cmd} command registered"
            passed=$((passed + 1))
        else
            fail "/${cmd} missing"
        fi
        checks=$((checks + 1))
    done

    if [ -x "$PAI_DIR/bin/voice-config.sh" ]; then
        pass "Voice config helper installed"
        passed=$((passed + 1))
    else
        fail "Voice config helper missing or not executable"
    fi
    checks=$((checks + 1))

    local stale_commands=()
    local command_file
    while IFS= read -r command_file; do
        local command_name
        command_name="$(basename "$command_file")"
        if ! manifest_has "commands" "$command_name"; then
            stale_commands+=("$command_name")
        fi
    done < <(find "${OPENCODE_DIR}/commands" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)

    if [ ${#stale_commands[@]} -eq 0 ]; then
        pass "No stale command files installed"
        passed=$((passed + 1))
    else
        fail "Stale command files installed: ${stale_commands[*]}"
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

    if [ -f "$PAI_DIR/TOOLS/manifest.json" ]; then
        pass "TOOLS/manifest.json exists"
        passed=$((passed + 1))
    else
        fail "TOOLS/manifest.json missing"
    fi
    checks=$((checks + 1))

    for tool in Inference.ts AnvilProgress.ts CrossVendorAudit.ts Arthur.ts MemoryRetriever.ts KnowledgeGraph.ts Checkpoint.ts SessionHarvester.ts KnowledgeHarvester.ts; do
        if [ -f "$PAI_DIR/TOOLS/$tool" ]; then
            pass "$tool exists"
            passed=$((passed + 1))
        else
            fail "$tool missing"
        fi
        checks=$((checks + 1))
    done
    
    if [ -d "$PAI_DIR/bin" ]; then
        pass "bin/ directory exists"
        passed=$((passed + 1))
    else
        fail "bin/ missing"
    fi
    checks=$((checks + 1))

    if [ -x "$PAI_DIR/bin/validate-tools-manifest.js" ]; then
        pass "Tools manifest validator installed"
        passed=$((passed + 1))
    else
        fail "Tools manifest validator missing or not executable"
    fi
    checks=$((checks + 1))

    if [ -x "$PAI_DIR/bin/validate-tools-manifest.js" ] && bun "$PAI_DIR/bin/validate-tools-manifest.js" --root "$OPENCODE_DIR" >/dev/null 2>&1; then
        pass "Tools manifest validator passes"
        passed=$((passed + 1))
    else
        fail "Tools manifest validator detected runtime drift"
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

    if [ -f "$PAI_DIR/RUNTIME_CONSTITUTION.md" ]; then
        pass "RUNTIME_CONSTITUTION.md exists"
        passed=$((passed + 1))
    else
        fail "RUNTIME_CONSTITUTION.md missing"
    fi
    checks=$((checks + 1))

    if [ -f "${OPENCODE_DIR}/plugins/pai-hooks.js" ] && grep -q "RUNTIME_CONSTITUTION.md" "${OPENCODE_DIR}/plugins/pai-hooks.js"; then
        pass "OpenCode plugin loads RUNTIME_CONSTITUTION.md"
        passed=$((passed + 1))
    else
        fail "OpenCode plugin does not load RUNTIME_CONSTITUTION.md"
    fi
    checks=$((checks + 1))

    # W2.9: contract check, not a count — every contracted observability
    # stream (docs/OBSERVABILITY_CONTRACTS.md) must have its schema installed
    # by name. The old "-ge 6" would stay green with the wrong six files.
    local required_schemas=(
        "mode-classifier-event.schema.json"
        "security-event.schema.json"
        "session-event.schema.json"
        "tool-failure-event.schema.json"
        "subagent-trace-event.schema.json"
        "notification-event.schema.json"
        "skill-execution-event.schema.json"
    )
    local missing_schemas=""
    for schema in "${required_schemas[@]}"; do
        [ -f "$PAI_DIR/schemas/$schema" ] || missing_schemas="$missing_schemas $schema"
    done
    if [ -z "$missing_schemas" ]; then
        pass "All ${#required_schemas[@]} contracted observability schemas installed"
        passed=$((passed + 1))
    else
        fail "Missing observability schemas:$missing_schemas"
    fi
    checks=$((checks + 1))

    if [ -f "${OPENCODE_DIR}/docs/OBSERVABILITY_CONTRACTS.md" ]; then
        pass "OpenCode observability contract docs installed"
        passed=$((passed + 1))
    else
        fail "OpenCode observability contract docs missing"
    fi
    checks=$((checks + 1))

    if [ -x "$PAI_DIR/bin/validate-doc-integrity.js" ]; then
        pass "DocIntegrity validator installed"
        passed=$((passed + 1))
    else
        fail "DocIntegrity validator missing or not executable"
    fi
    checks=$((checks + 1))
    
    echo "  Score: $passed/$checks"
    return $((checks - passed))
}

check_pulse() {
    section "10. Pulse Scaffolding"
    local checks=0
    local passed=0
    
    if [ -d "$PAI_DIR/PULSE" ]; then
        pass "PULSE/ directory exists (scaffold)"
        passed=$((passed + 1))
    else
        fail "PULSE/ missing"
    fi
    checks=$((checks + 1))
    
    if [ -f "$PAI_DIR/PULSE/PULSE.toml" ]; then
        pass "PULSE.toml exists (config scaffold)"
        passed=$((passed + 1))
    else
        fail "PULSE.toml missing"
    fi
    checks=$((checks + 1))

    if [ -f "$PAI_DIR/PULSE/README.md" ]; then
        pass "PULSE/README.md documents optional broker scope"
        passed=$((passed + 1))
    else
        fail "PULSE/README.md missing"
    fi
    checks=$((checks + 1))

    if grep -q 'status = "optional-broker"' "$PAI_DIR/PULSE/PULSE.toml" 2>/dev/null; then
        pass "PULSE.toml declares optional broker scope"
        passed=$((passed + 1))
    else
        fail "PULSE.toml does not declare optional broker scope"
    fi
    checks=$((checks + 1))

    if ! grep -q 'PAI/TOOLS' "$PAI_DIR/PULSE/PULSE.toml" 2>/dev/null && ! grep -q '\[\[job\]\]' "$PAI_DIR/PULSE/PULSE.toml" 2>/dev/null; then
        pass "PULSE.toml has no legacy jobs or missing tool calls"
        passed=$((passed + 1))
    else
        fail "PULSE.toml still declares legacy jobs or PAI/TOOLS calls"
    fi
    checks=$((checks + 1))

    if [ -f "$PAI_DIR/broker/pulse-broker.ts" ] \
        && [ -f "$PAI_DIR/broker/broker-lib.ts" ] \
        && [ -f "$PAI_DIR/broker/renderer-desktop.ts" ] \
        && [ -f "$PAI_DIR/broker/edge-tts-lib.ts" ] \
        && [ -f "$PAI_DIR/broker/edge-tts-speaker.ts" ]; then
        pass "Pulse Broker and Edge TTS renderer files installed"
        passed=$((passed + 1))
    else
        fail "Pulse Broker or Edge TTS renderer files missing from PAI/broker/"
    fi
    checks=$((checks + 1))

    # Edge TTS is an OPTIONAL desktop-voice dependency: the renderer is opt-in
    # (--tts) and auto-installs edge-tts lazily on first use, and headless
    # servers are provisioned with --no-tts-bootstrap on purpose. Its absence is
    # therefore a soft warning, never a validation failure.
    if edge_tts_available; then
        pass "Edge TTS provider dependency available (desktop voice ready)"
        passed=$((passed + 1))
        checks=$((checks + 1))
    else
        warn "Edge TTS provider not installed — optional desktop voice; auto-installs on first --tts use, or rerun installer without --no-tts-bootstrap"
    fi
    
    # Installed content must have no legacy Claude Code paths anywhere —
    # PAI core, skills, agents, and commands (install.sh patch_installed_paths
    # rewrites them at install time).
    # USER/SECURITY/PATTERNS.yaml is excluded: the security policy legitimately
    # names ~/.claude/.credentials.json as a zero-access DENY target (it protects
    # the real Claude credential store at that path). It is a deny-list entry,
    # not a legacy path to migrate — rewriting it would break the protection.
    # Same for the Patterns.example.yaml template it is seeded from, and for the
    # PAI/plugins lib mirror (repo-canonical code, byte-identical to plugins/lib).
    # These mirror install.sh patch_installed_paths's exemptions exactly.
    local claude_refs=$(grep -rlI "\.claude/" "$PAI_DIR" "${OPENCODE_DIR}/skills" "${OPENCODE_DIR}/agents" "${OPENCODE_DIR}/commands" --exclude-dir=node_modules --exclude-dir=.next --exclude-dir=out 2>/dev/null | grep -v patch-paths.sh | grep -v "$PAI_DIR/bin/" | grep -v "USER/SECURITY/" | grep -v "$PAI_DIR/plugins/" | grep -v "DOCUMENTATION/Security/Patterns.example.yaml" | wc -l)
    if [ "$claude_refs" -eq 0 ]; then
        pass "No hardcoded ~/.claude/ paths in installed content (all migrated to ~/.config/opencode/)"
        passed=$((passed + 1))
    else
        fail "$claude_refs installed files still have ~/.claude/ refs (should be ~/.config/opencode/)"
    fi
    checks=$((checks + 1))
    
    echo "  Note: this validates Pulse files only, not a live daemon."
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

    if [ -x "${SCRIPT_DIR}/check-port-coherence.sh" ] && bash "${SCRIPT_DIR}/check-port-coherence.sh" >/dev/null 2>&1; then
        pass "Active Algorithm/CLAUDE instructions match OpenCode runtime"
        passed=$((passed + 1))
    else
        fail "Active Algorithm/CLAUDE instructions have stale runtime promises"
    fi
    checks=$((checks + 1))

    if [ -x "${SCRIPT_DIR}/validate-promise-integrity.sh" ] && bash "${SCRIPT_DIR}/validate-promise-integrity.sh" >/dev/null 2>&1; then
        pass "Promise integrity validator passes"
        passed=$((passed + 1))
    else
        fail "Promise integrity validator detected runtime drift"
    fi
    checks=$((checks + 1))

    if [ -x "${SCRIPT_DIR}/validate-doc-integrity.js" ] && bun "${SCRIPT_DIR}/validate-doc-integrity.js" --root "$OPENCODE_DIR" >/dev/null 2>&1; then
        pass "Doc integrity validator passes"
        passed=$((passed + 1))
    else
        fail "Doc integrity validator detected stale docs or missing runtime surfaces"
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
    local embedded_failed=0
    
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
        if bash "${PAI_DIR}/bin/test-behavioral.sh"; then
            echo ""
        else
            embedded_failed=1
            echo ""
        fi
    fi
    
    # Optional: run E2E runtime tests if available
    if [ -f "${PAI_DIR}/bin/test-e2e-runtime.sh" ]; then
        echo ""
        echo "═══════════════════════════════════════════════════"
        echo "  E2E Runtime Validation"
        echo "═══════════════════════════════════════════════════"
        echo ""
        if bash "${PAI_DIR}/bin/test-e2e-runtime.sh"; then
            echo ""
        else
            embedded_failed=1
            echo ""
        fi
    fi
    
    if [ $FAILED -eq 0 ] && [ $embedded_failed -eq 0 ]; then
        echo -e "${GREEN}Status: ALL CHECKS PASSED ✅${RESET}"
        exit 0
    else
        local total_failures=$FAILED
        if [ $embedded_failed -ne 0 ]; then
            total_failures=$((total_failures + embedded_failed))
        fi
        echo -e "${RED}Status: ${total_failures} VALIDATION GROUP(S) FAILED ❌${RESET}"
        exit 1
    fi
}

main "$@"
