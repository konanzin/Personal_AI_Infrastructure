#!/usr/bin/env bash
# Validate that the active PAI instructions describe the OpenCode runtime,
# not stale Claude Code-only surfaces.

set -uo pipefail

MODE="installed"
if [ "${1:-}" = "--repo" ]; then
    MODE="repo"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [ "$MODE" = "repo" ]; then
    PAI_DIR="${REPO_ROOT}/PAI"
    OPENCODE_HOME="${REPO_ROOT}/opencode"
    AGENTS_DIR="${REPO_ROOT}/opencode/agents"
    PLUGIN_PATH="${REPO_ROOT}/opencode/plugins/pai-hooks.js"
else
    PAI_DIR="${PAI_DIR:-${HOME}/.config/opencode/PAI}"
    OPENCODE_HOME="${OPENCODE_DIR:-${HOME}/.config/opencode}"
    AGENTS_DIR="${OPENCODE_HOME}/agents"
    PLUGIN_PATH="${OPENCODE_HOME}/plugins/pai-hooks.js"
fi

failures=0

note_fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

if [ ! -f "${PAI_DIR}/CLAUDE.md" ]; then
    note_fail "missing ${PAI_DIR}/CLAUDE.md"
fi

if [ ! -f "${PAI_DIR}/RUNTIME_CONSTITUTION.md" ]; then
    note_fail "missing ${PAI_DIR}/RUNTIME_CONSTITUTION.md"
fi

if [ ! -f "${PAI_DIR}/ALGORITHM/LATEST" ]; then
    note_fail "missing ${PAI_DIR}/ALGORITHM/LATEST"
    latest=""
else
    latest="$(tr -d '[:space:]' < "${PAI_DIR}/ALGORITHM/LATEST")"
fi

active_algorithm=""
if [ -n "$latest" ]; then
    active_algorithm="${PAI_DIR}/ALGORITHM/${latest}.md"
    if [ ! -f "$active_algorithm" ]; then
        note_fail "active Algorithm file missing: ${active_algorithm}"
    fi
fi

scan_files=()
[ -f "${PAI_DIR}/CLAUDE.md" ] && scan_files+=("${PAI_DIR}/CLAUDE.md")
[ -f "${PAI_DIR}/RUNTIME_CONSTITUTION.md" ] && scan_files+=("${PAI_DIR}/RUNTIME_CONSTITUTION.md")
[ -n "$active_algorithm" ] && [ -f "$active_algorithm" ] && scan_files+=("$active_algorithm")

reject_unqualified() {
    local label="$1"
    local pattern="$2"
    local matches
    matches="$(
        grep -nEI "$pattern" "${scan_files[@]}" 2>/dev/null \
            | grep -viE 'legacy|not active|not implemented|unavailable|do not assume|do not call|until|out of scope|verify the file exists|if neither exists|unless the file exists' \
            || true
    )"
    if [ -n "$matches" ]; then
        echo "$matches"
        note_fail "$label"
    fi
}

if [ "${#scan_files[@]}" -gt 0 ]; then
    reject_unqualified "stale Claude Code system-prompt promise" 'PAI_SYSTEM_PROMPT|--append-system-prompt-file'
    reject_unqualified "stale Claude Code prompt hook promise" 'UserPromptSubmit|PromptProcessing\.hook|additionalContext|Sonnet classifier|subscription-billed|No regex fallback'
    reject_unqualified "duplicated PAI/PAI path promise" 'PAI/PAI/'
    reject_unqualified "missing CheckpointPerISC hook promised as active" 'CheckpointPerISC\.hook\.ts'
    reject_unqualified "missing claude-code-guide agent promised as active" 'claude-code-guide'
    reject_unqualified "legacy kitty tab/statusline promised as active" 'setPhaseTab|kitty tab'
    reject_unqualified "Inference helper called without availability guard" '(^|[^A-Za-z0-9_./-])(PAI/TOOLS/Inference\.ts|TOOLS/Inference\.ts)'
fi

if [ -d "$AGENTS_DIR" ]; then
    agent_refs="$(grep -RInE 'claude-code-guide|BrowserAgent|QATester|UIReviewer' "$AGENTS_DIR" 2>/dev/null || true)"
    if [ -n "$agent_refs" ]; then
        echo "$agent_refs"
        note_fail "agent prompt references retired or missing agents"
    fi
fi

if [ ! -f "$PLUGIN_PATH" ]; then
    note_fail "missing OpenCode PAI plugin: ${PLUGIN_PATH}"
elif ! grep -q "RUNTIME_CONSTITUTION.md" "$PLUGIN_PATH"; then
    note_fail "OpenCode PAI plugin does not load RUNTIME_CONSTITUTION.md"
fi

if [ "$failures" -eq 0 ]; then
    echo "PASS: OpenCode port coherence checks passed"
    exit 0
fi

exit 1
