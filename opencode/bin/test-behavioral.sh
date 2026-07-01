#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  PAI Behavioral Validation — Runtime test matrix
#  Usage: opencode run && bash opencode/bin/test-behavioral.sh
# ═══════════════════════════════════════════════════════════

set -uo pipefail

OPENCODE_DIR="${HOME}/.config/opencode"
PAI_DIR="${OPENCODE_DIR}/PAI"
PLUGINS_DIR="${OPENCODE_DIR}/plugins"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
run_test "Plugin version is 2.13.0" \
    "grep -q \"PLUGIN_VERSION = '2.13.0'\" ${PLUGINS_DIR}/pai-hooks.js"

run_test "10 handlers present" \
    "[ \$(grep -c '\".*\": async' ${PLUGINS_DIR}/pai-hooks.js) -eq 10 ]"

run_test "permission.asked handler exists" \
    "grep -q '\"permission.asked\"' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Runtime event bridge present (OpenCode >=1.16 bus events)" \
    "grep -q 'hooks.event = async' ${PLUGINS_DIR}/pai-hooks.js && grep -q \"hooks\['permission.ask'\]\" ${PLUGINS_DIR}/pai-hooks.js"

run_test "Event bridge routes session lifecycle and message parts" \
    "grep -q \"case 'session.created':\" ${PLUGINS_DIR}/pai-hooks.js && grep -q \"case 'message.part.updated':\" ${PLUGINS_DIR}/pai-hooks.js"

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

run_test "Runtime constitution file is installed" \
    "[ -f ${PAI_DIR}/RUNTIME_CONSTITUTION.md ]"

run_test "System transform loads runtime constitution" \
    "grep -q 'RUNTIME_CONSTITUTION.md' ${PLUGINS_DIR}/pai-hooks.js"

run_test "System transform supports lean profile (client agent)" \
    "grep -q 'readStoredClientAgent' ${PLUGINS_DIR}/pai-hooks.js && grep -q 'LEAN_AGENTS' ${PLUGINS_DIR}/pai-hooks.js"

run_test "build-mobile agent defined in runtime config" \
    "grep -q '\"build-mobile\"' ${OPENCODE_DIR}/opencode.jsonc"

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

# Functional test of ISA sync
ISA_SYNC_TMP=$(mktemp /tmp/pai-isa-sync-test-XXXXXX.js)
cat > "$ISA_SYNC_TMP" <<ENDTEST
import {
  isISAArtifactPath,
  extractISAState,
  syncISAToWorkRegistry,
  readWorkRegistry,
} from '${PLUGINS_DIR}/lib/pai-hooks.lib.js';

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

run_test "tool.execute.before inspects reads" \
    "grep -q 'inspectReadPath' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Containment inspector exists in lib" \
    "grep -q 'inspectWriteContent' ${PLUGINS_DIR}/lib/pai-hooks.lib.js"

run_test "chat.message pre-sanitizes blocked prompts" \
    "grep -q 'PAI SECURITY BLOCKED' ${PLUGINS_DIR}/pai-hooks.js"

READ_GUARD_TEST=$(cat <<EOF
import { inspectBashCommand, inspectReadPath, inspectWriteContent } from '${PLUGINS_DIR}/lib/pai-hooks.lib.js';
const shadow = inspectReadPath('/etc/shadow');
const env = inspectReadPath('.env');
const catEnv = inspectBashCommand('cat .env');
const leak = inspectWriteContent('public/leak.txt', '-----BEGIN PRIVATE KEY-----\\nabc\\n-----END PRIVATE KEY-----');
console.log(
  shadow.action === 'deny' &&
  env.action === 'deny' &&
  catEnv.action === 'deny' &&
  leak.action === 'deny'
  ? 'PASS' : 'FAIL'
);
EOF
)

READ_GUARD_RESULT=$(echo "$READ_GUARD_TEST" | bun run - 2>/dev/null || echo "FAIL")
if [ "$READ_GUARD_RESULT" = "PASS" ]; then
    pass "ReadGuard and containment functional test"
    PASSED=$((PASSED + 1))
else
    fail "ReadGuard and containment functional test"
fi
TOTAL=$((TOTAL + 1))

# ─── AGENT GUARD / SKILL GUARD TEST ───────────────────────
echo ""
echo "${BLUE}11. AgentGuard / SkillGuard${RESET}"

run_test "AgentGuard inspector exists in lib" \
    "grep -q 'inspectAgentSpawn' ${PLUGINS_DIR}/lib/pai-hooks.lib.js"

run_test "SkillGuard inspector exists in lib" \
    "grep -q 'inspectSkillInvocation' ${PLUGINS_DIR}/lib/pai-hooks.lib.js"

run_test "AgentGuard integrated in tool.execute.before" \
    "grep -q 'AgentGuard' ${PLUGINS_DIR}/pai-hooks.js"

run_test "SkillGuard integrated in tool.execute.before" \
    "grep -q 'SkillGuard' ${PLUGINS_DIR}/pai-hooks.js"

run_test "AgentGuard logs to agent-guard.jsonl" \
    "grep -q 'agent-guard.jsonl' ${PLUGINS_DIR}/pai-hooks.js"

run_test "SkillGuard logs to skill-guard.jsonl" \
    "grep -q 'skill-guard.jsonl' ${PLUGINS_DIR}/pai-hooks.js"

# Functional test of guards
GUARD_TEST_TMP=$(mktemp /tmp/pai-guard-test-XXXXXX.js)
cat > "$GUARD_TEST_TMP" <<ENDTEST
import {
  inspectAgentSpawn,
  inspectSkillInvocation,
} from '${PLUGINS_DIR}/lib/pai-hooks.lib.js';

// AgentGuard: trivial lookup should warn
const ag1 = inspectAgentSpawn({
  subagent_type: 'explore',
  description: 'find file named config.ts',
  prompt: '',
  sessionAgentCount: 0,
});

// AgentGuard: complex task should allow
const ag2 = inspectAgentSpawn({
  subagent_type: 'engineer',
  description: 'refactor auth module',
  prompt: 'detailed requirements here',
  sessionAgentCount: 0,
});

// SkillGuard: obvious misfire should deny
const sg1 = inspectSkillInvocation({
  skillName: 'ArXiv',
  userRequest: 'find italian restaurant',
  context: '',
});

// SkillGuard: matching request should allow
const sg2 = inspectSkillInvocation({
  skillName: 'ArXiv',
  userRequest: 'find papers on transformers',
  context: '',
});

console.log(
  ag1.action === 'warn' && ag2.action === 'allow' &&
  sg1.action === 'deny' && sg2.action === 'allow'
  ? 'PASS' : 'FAIL'
);
ENDTEST

GUARD_RESULT=$(bun run "$GUARD_TEST_TMP" 2>/dev/null || echo "FAIL")
rm -f "$GUARD_TEST_TMP"
if [ "$GUARD_RESULT" = "PASS" ]; then
    pass "Guard functional test (AgentGuard + SkillGuard)"
    PASSED=$((PASSED + 1))
else
    fail "Guard functional test"
fi
TOTAL=$((TOTAL + 1))

# ─── OBSERVABILITY STREAMS TEST ───────────────────────────
echo ""
echo "${BLUE}12. Observability Streams${RESET}"

run_test "session-events.jsonl path referenced" \
    "grep -q 'session-events.jsonl' ${PLUGINS_DIR}/pai-hooks.js"

run_test "tool-failures.jsonl path referenced" \
    "grep -q 'tool-failures.jsonl' ${PLUGINS_DIR}/pai-hooks.js"

run_test "subagent-trace.jsonl path referenced" \
    "grep -q 'subagent-trace.jsonl' ${PLUGINS_DIR}/pai-hooks.js"

run_test "mode-classifier includes prompt_hash" \
    "grep -q 'prompt_hash' ${PLUGINS_DIR}/pai-hooks.js"

run_test "hashString exported from lib" \
    "grep -q 'export function hashString' ${PLUGINS_DIR}/lib/pai-hooks.lib.js"

run_test "Session created event emitted" \
    "grep -q 'session_created' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Session idle event emitted" \
    "grep -q 'session_idle' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Session archived event emitted" \
    "grep -q 'session_archived' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Session deleted event emitted" \
    "grep -q 'session_deleted' ${PLUGINS_DIR}/pai-hooks.js"

run_test "State sync event emitted" \
    "grep -q 'state_sync' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Tool failure event emitted" \
    "grep -q 'tool_failure' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Agent spawned trace emitted" \
    "grep -q 'agent_spawned' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Skill invoked trace emitted" \
    "grep -q 'skill_invoked' ${PLUGINS_DIR}/pai-hooks.js"

run_test "Observability schemas installed" \
    "[ \$(find ${PAI_DIR}/schemas -maxdepth 1 -type f -name '*.schema.json' 2>/dev/null | wc -l | tr -d ' ') -ge 6 ]"

run_test "Observability contract docs installed" \
    "[ -f ${OPENCODE_DIR}/docs/OBSERVABILITY_CONTRACTS.md ]"

# Functional test of hashString
HASH_TEST=$(cat <<EOF
import { hashString } from '${PLUGINS_DIR}/lib/pai-hooks.lib.js';
const h1 = hashString('test prompt', 8);
const h2 = hashString('test prompt', 8);
const h3 = hashString('different', 8);
console.log(h1 === h2 && h1.length === 8 && h1 !== h3 ? 'PASS' : 'FAIL');
EOF
)

HASH_RESULT=$(echo "$HASH_TEST" | bun run - 2>/dev/null || echo "FAIL")
if [ "$HASH_RESULT" = "PASS" ]; then
    pass "hashString functional test (deterministic, length, different input)"
    PASSED=$((PASSED + 1))
else
    fail "hashString functional test"
fi
TOTAL=$((TOTAL + 1))

# ─── NOTIFICATIONS STREAM (contract v1) ───────────────────
echo ""
echo "${BLUE}Notifications Stream${RESET}"

run_test "emitNotification exported by lib" \
    "grep -q 'export function emitNotification' ${PLUGINS_DIR}/lib/pai-hooks.lib.js"

run_test "Plugin wires notification emit points" \
    "[ \$(grep -c 'emitNotification(' ${PLUGINS_DIR}/pai-hooks.js) -ge 6 ]"

run_test "ISA sync emits phase_transition" \
    "grep -q \"event: 'phase_transition'\" ${PLUGINS_DIR}/lib/pai-hooks.lib.js"

# Functional: emit into an isolated PAI_DIR and verify the contract envelope
NOTIF_TEST=$(cat <<EOF
import { mkdtempSync, readFileSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
process.env.PAI_DIR = mkdtempSync(join(tmpdir(), 'pai-behav-notif-'));
const lib = await import('${PLUGINS_DIR}/lib/pai-hooks.lib.js');
lib.emitNotification({ event: 'tool_failing', sessionId: 's1', data: { tool: 'bash', count: 3 } });
const e = JSON.parse(readFileSync(lib.NOTIFICATIONS_PATH, 'utf-8').trim());
console.log(e.v === 1 && e.level === 'attention' && e.speak.includes('bash') ? 'PASS' : 'FAIL');
EOF
)

NOTIF_RESULT=$(echo "$NOTIF_TEST" | bun run - 2>/dev/null || echo "FAIL")
if [ "$NOTIF_RESULT" = "PASS" ]; then
    pass "emitNotification functional test (envelope v1, level, speak)"
    PASSED=$((PASSED + 1))
else
    fail "emitNotification functional test"
fi
TOTAL=$((TOTAL + 1))

# ─── PULSE BROKER (optional runtime) ──────────────────────
echo ""
echo "${BLUE}Pulse Broker${RESET}"

run_test "Broker daemon, renderer, and Edge TTS files installed" \
    "[ -f ${PAI_DIR}/broker/pulse-broker.ts ] && [ -f ${PAI_DIR}/broker/broker-lib.ts ] && [ -f ${PAI_DIR}/broker/renderer-desktop.ts ] && [ -f ${PAI_DIR}/broker/edge-tts-lib.ts ] && [ -f ${PAI_DIR}/broker/edge-tts-speaker.ts ]"

run_test "Pulse config declares optional broker scope" \
    "grep -q 'status = \"optional-broker\"' ${PAI_DIR}/PULSE/PULSE.toml"

run_test "Pulse config has no legacy jobs or missing tool calls" \
    "! grep -q 'PAI/TOOLS' ${PAI_DIR}/PULSE/PULSE.toml && ! grep -q '\\[\\[job\\]\\]' ${PAI_DIR}/PULSE/PULSE.toml"

run_test "Broker serves /health and legacy /api/pulse/health" \
    "grep -q \"'/health'\" ${PAI_DIR}/broker/pulse-broker.ts && grep -q '/api/pulse/health' ${PAI_DIR}/broker/pulse-broker.ts"

run_test "Desktop renderer defaults to Edge TTS with command override" \
    "grep -q 'edge-tts-speaker.ts' ${PAI_DIR}/broker/renderer-desktop.ts && grep -q 'PULSE_TTS_CMD' ${PAI_DIR}/broker/renderer-desktop.ts"

run_test "Voice config helper installed" \
    "[ -x ${PAI_DIR}/bin/voice-config.sh ]"

run_test "Edge TTS provider dependency available" \
    "([ -x \"${OPENCODE_DIR}/tts-venv/bin/python\" ] && \"${OPENCODE_DIR}/tts-venv/bin/python\" -c 'import edge_tts') || command -v edge-tts || (command -v python3 && python3 -c 'import edge_tts') || (command -v python && python -c 'import edge_tts')"

# Functional: routing policy v1 (attention always; focused suppresses others)
BROKER_TEST=$(cat <<EOF
import { decideRender } from '${PAI_DIR}/broker/broker-lib.ts';
const ev = (level) => ({ v:1, timestamp:'t', level, event:'x', session_id:'s1', slug:null, title:null, speak:'s', data:{} });
const sub = (over) => ({ id:'a', device:'phone', name:'p', focusedSession:null, listening:true, ...over });
const watcher = sub({ id:'w', focusedSession:'s1' });
const phone = sub({});
const r1 = decideRender(ev('milestone'), [watcher, phone], phone);
const r2 = decideRender(ev('attention'), [watcher, phone], phone);
console.log(!r1.speak && r1.reason === 'session-on-screen' && r2.speak ? 'PASS' : 'FAIL');
EOF
)

BROKER_RESULT=$(echo "$BROKER_TEST" | bun run - 2>/dev/null || echo "FAIL")
if [ "$BROKER_RESULT" = "PASS" ]; then
    pass "Routing policy functional test (attention-always, focused suppresses others)"
    PASSED=$((PASSED + 1))
else
    fail "Routing policy functional test"
fi
TOTAL=$((TOTAL + 1))

# ─── PROMISE INTEGRITY ────────────────────────────────────
# Agents and instructions must not promise surfaces the install does not
# provide: legacy paths, unregistered commands, missing context files.
echo ""
echo "${BLUE}Promise Integrity${RESET}"

run_test "No installed agent references ~/.claude/" \
    "! grep -rl '\.claude/' ${OPENCODE_DIR}/agents/"

run_test "No duplicated PAI/PAI/ paths in installed CLAUDE.md" \
    "! grep -q 'opencode/PAI/PAI/' ${PAI_DIR}/CLAUDE.md"

run_test "Active PAI instructions match OpenCode runtime" \
    "bash ${SCRIPT_DIR}/check-port-coherence.sh"

run_test "Promise integrity validator passes" \
    "bash ${SCRIPT_DIR}/validate-promise-integrity.sh"

run_test "Doc integrity validator passes" \
    "bun ${SCRIPT_DIR}/validate-doc-integrity.js --root ${OPENCODE_DIR}"

run_test "Tools manifest validator passes" \
    "bun ${SCRIPT_DIR}/validate-tools-manifest.js --root ${OPENCODE_DIR}"

# Every installed command file must be registered in opencode.jsonc
COMMANDS_OK=true
MISSING_COMMANDS=""
for cmd_file in "${OPENCODE_DIR}/commands/"*.md; do
    [ -f "$cmd_file" ] || continue
    cmd_name=$(basename "$cmd_file" .md)
    if ! grep -q "\"${cmd_name}\"" "${OPENCODE_DIR}/opencode.jsonc" 2>/dev/null; then
        COMMANDS_OK=false
        MISSING_COMMANDS="${MISSING_COMMANDS} ${cmd_name}"
    fi
done
TOTAL=$((TOTAL + 1))
if [ "$COMMANDS_OK" = true ]; then
    pass "Every installed command file is registered in opencode.jsonc"
    PASSED=$((PASSED + 1))
else
    fail "Unregistered commands:${MISSING_COMMANDS}"
fi

# Static paths promised by agents must exist after install.
# Excluded: PAI/TOOLS/ (helpers with declared unavailable-fallback),
# MEMORY/ (runtime-created), template paths containing placeholders.
PROMISES_OK=true
MISSING_PROMISES=""
while IFS= read -r promised; do
    case "$promised" in
        *"{"*|*YYYY*|*/TOOLS/*|*/MEMORY/*|"~/.config/opencode/") continue ;;
    esac
    expanded="${promised/#\~/$HOME}"
    if [ ! -e "$expanded" ]; then
        PROMISES_OK=false
        MISSING_PROMISES="${MISSING_PROMISES} ${promised}"
    fi
done < <(grep -rho '~/.config/opencode/[A-Za-z0-9_./{}-]*' "${OPENCODE_DIR}/agents/" 2>/dev/null | sort -u)
TOTAL=$((TOTAL + 1))
if [ "$PROMISES_OK" = true ]; then
    pass "All static paths promised by agents exist"
    PASSED=$((PASSED + 1))
else
    fail "Agents promise missing paths:${MISSING_PROMISES}"
fi

# ─── PAI RUNTIME TOOLS ────────────────────────────────────
echo ""
echo "${BLUE}PAI Runtime Tools${RESET}"

run_test "Tools manifest installed" \
    "test -f ${PAI_DIR}/TOOLS/manifest.json"

for tool in Inference.ts ForgeProgress.ts AnvilProgress.ts CrossVendorAudit.ts Arthur.ts MemoryRetriever.ts KnowledgeGraph.ts Checkpoint.ts SessionHarvester.ts KnowledgeHarvester.ts; do
    run_test "${tool} installed" \
        "test -f ${PAI_DIR}/TOOLS/${tool}"
done

TOOLS_TMP="$(mktemp -d)"

if PAI_DIR="$TOOLS_TMP" bun "${PAI_DIR}/TOOLS/Inference.ts" --json --level fast system user 2>/dev/null | grep -q '"status": "unavailable"'; then
    pass "Inference unavailable behavior"
    PASSED=$((PASSED + 1))
else
    fail "Inference unavailable behavior"
fi
TOTAL=$((TOTAL + 1))

if PAI_DIR="$TOOLS_TMP" PAI_DISABLE_CODEX=1 bash -lc "echo prompt | bun '${PAI_DIR}/TOOLS/ForgeProgress.ts' --slug smoke" 2>/dev/null | grep -q '"verdict": "unavailable"'; then
    pass "ForgeProgress unavailable behavior"
    PASSED=$((PASSED + 1))
else
    fail "ForgeProgress unavailable behavior"
fi
TOTAL=$((TOTAL + 1))

if env -u MOONSHOT_API_KEY PAI_DIR="$TOOLS_TMP" bash -lc "echo prompt | bun '${PAI_DIR}/TOOLS/AnvilProgress.ts' --slug smoke" 2>/dev/null | grep -q '"verdict": "unavailable"'; then
    pass "AnvilProgress unavailable behavior"
    PASSED=$((PASSED + 1))
else
    fail "AnvilProgress unavailable behavior"
fi
TOTAL=$((TOTAL + 1))

if PAI_DIR="$TOOLS_TMP" PAI_DISABLE_CODEX=1 bun "${PAI_DIR}/TOOLS/CrossVendorAudit.ts" --slug smoke --advisor-verdict '{}' 2>/dev/null | grep -q '"verdict": "skipped"'; then
    pass "CrossVendorAudit skipped behavior"
    PASSED=$((PASSED + 1))
else
    fail "CrossVendorAudit skipped behavior"
fi
TOTAL=$((TOTAL + 1))

if PAI_DIR="$TOOLS_TMP" bun "${PAI_DIR}/TOOLS/Arthur.ts" status 2>/dev/null | grep -q '"verdict": "available"'; then
    pass "Arthur status behavior"
    PASSED=$((PASSED + 1))
else
    fail "Arthur status behavior"
fi
TOTAL=$((TOTAL + 1))

MEMORY_TMP="$TOOLS_TMP"
mkdir -p "${MEMORY_TMP}/MEMORY/KNOWLEDGE"

if PAI_DIR="$MEMORY_TMP" bun "${PAI_DIR}/TOOLS/MemoryRetriever.ts" anything --json 2>/dev/null | grep -q '"status": "empty_archive"'; then
    pass "MemoryRetriever empty archive behavior"
    PASSED=$((PASSED + 1))
else
    fail "MemoryRetriever empty archive behavior"
fi
TOTAL=$((TOTAL + 1))

if PAI_DIR="$MEMORY_TMP" bun "${PAI_DIR}/TOOLS/KnowledgeGraph.ts" stats --json 2>/dev/null | grep -q '"status": "empty_archive"'; then
    pass "KnowledgeGraph empty archive behavior"
    PASSED=$((PASSED + 1))
else
    fail "KnowledgeGraph empty archive behavior"
fi
TOTAL=$((TOTAL + 1))

if PAI_DIR="$TOOLS_TMP" bun "${PAI_DIR}/TOOLS/Checkpoint.ts" list smoke --json 2>/dev/null | grep -q '"status": "ok"'; then
    pass "Checkpoint list behavior"
    PASSED=$((PASSED + 1))
else
    fail "Checkpoint list behavior"
fi
TOTAL=$((TOTAL + 1))

NO_SESSIONS_DIR="${TOOLS_TMP}/no-sessions"
mkdir -p "$NO_SESSIONS_DIR"
if PAI_DIR="$TOOLS_TMP" bun "${PAI_DIR}/TOOLS/SessionHarvester.ts" --sessions-dir "$NO_SESSIONS_DIR" --json 2>/dev/null | grep -q '"status": "no_sessions"'; then
    pass "SessionHarvester no-session behavior"
    PASSED=$((PASSED + 1))
else
    fail "SessionHarvester no-session behavior"
fi
TOTAL=$((TOTAL + 1))

if PAI_DIR="$TOOLS_TMP" bun "${PAI_DIR}/TOOLS/KnowledgeHarvester.ts" status --json 2>/dev/null | grep -q '"status": "empty_archive"'; then
    pass "KnowledgeHarvester empty archive behavior"
    PASSED=$((PASSED + 1))
else
    fail "KnowledgeHarvester empty archive behavior"
fi
TOTAL=$((TOTAL + 1))

rm -rf "$TOOLS_TMP"

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
