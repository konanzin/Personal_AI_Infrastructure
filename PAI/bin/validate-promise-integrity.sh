#!/usr/bin/env bash
# Validate that operational PAI promises match the OpenCode runtime.
#
# Default mode scans the installed runtime under ~/.config/opencode.
# Use --repo to scan this repository's active runtime surfaces.
# Use --root <dir> for isolated fixtures shaped like an installed runtime.

set -uo pipefail

MODE="installed"
CUSTOM_ROOT=""
STRICT_SKILLS=false
SHOW_WARNINGS=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo)
            MODE="repo"
            shift
            ;;
        --root)
            MODE="custom"
            CUSTOM_ROOT="${2:-}"
            if [ -z "$CUSTOM_ROOT" ]; then
                echo "FAIL: --root requires a directory"
                exit 2
            fi
            shift 2
            ;;
        --strict-skills)
            STRICT_SKILLS=true
            shift
            ;;
        --show-warnings)
            SHOW_WARNINGS=true
            shift
            ;;
        *)
            echo "FAIL: unknown argument: $1"
            exit 2
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [ "$MODE" = "repo" ]; then
    PAI_DIR="${REPO_ROOT}/PAI"
    OPENCODE_HOME="${REPO_ROOT}/opencode"
    AGENTS_DIR="${REPO_ROOT}/opencode/agents"
    COMMANDS_DIR="${REPO_ROOT}/opencode/commands"
    SKILLS_DIR="${REPO_ROOT}/skills"
    CONFIG_PATH="${REPO_ROOT}/opencode/config/opencode.jsonc.template"
    PLUGIN_PATH="${REPO_ROOT}/opencode/plugins/pai-hooks.js"
elif [ "$MODE" = "custom" ]; then
    OPENCODE_HOME="$CUSTOM_ROOT"
    PAI_DIR="${CUSTOM_ROOT}/PAI"
    AGENTS_DIR="${CUSTOM_ROOT}/agents"
    COMMANDS_DIR="${CUSTOM_ROOT}/commands"
    SKILLS_DIR="${CUSTOM_ROOT}/skills"
    CONFIG_PATH="${CUSTOM_ROOT}/opencode.jsonc"
    PLUGIN_PATH="${CUSTOM_ROOT}/plugins/pai-hooks.js"
else
    OPENCODE_HOME="${OPENCODE_DIR:-${HOME}/.config/opencode}"
    PAI_DIR="${PAI_DIR:-${OPENCODE_HOME}/PAI}"
    AGENTS_DIR="${OPENCODE_HOME}/agents"
    COMMANDS_DIR="${OPENCODE_HOME}/commands"
    SKILLS_DIR="${OPENCODE_HOME}/skills"
    CONFIG_PATH="${OPENCODE_HOME}/opencode.jsonc"
    PLUGIN_PATH="${OPENCODE_HOME}/plugins/pai-hooks.js"
fi

failures=0
warnings=0

QUALIFIER_PATTERN='legacy|historical|not active|not implemented|unavailable|do not assume|do not call|do not invoke|until|out of scope|verify .*exists|verify the file exists|if .*exists|if neither exists|unless .*exists|unless the file exists|skipped|fallback|optional|deprecated|absent|not found|is missing|if .*missing|missing .*helper|missing .*tool|missing .*file|example|placeholder'

record_fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

record_warn() {
    warnings=$((warnings + 1))
    if [ "$SHOW_WARNINGS" = true ]; then
        echo "WARN: $1"
    fi
}

record_skill_issue() {
    if [ "$STRICT_SKILLS" = true ]; then
        record_fail "$1"
    else
        record_warn "$1"
    fi
}

is_qualified() {
    printf '%s\n' "$1" | grep -qiE "$QUALIFIER_PATTERN"
}

print_limited_matches() {
    local matches="$1"
    local count
    count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l)"
    printf '%s\n' "$matches" | sed -n '1,20p'
    if [ "$count" -gt 20 ]; then
        echo "... $((count - 20)) more matches omitted"
    fi
}

existing_files_from_dir() {
    local dir="$1"
    local pattern="$2"
    if [ -d "$dir" ]; then
        find "$dir" -type f -name "$pattern" | sort
    fi
}

active_files=()
if [ -f "${PAI_DIR}/CLAUDE.md" ]; then
    active_files+=("${PAI_DIR}/CLAUDE.md")
else
    record_fail "missing ${PAI_DIR}/CLAUDE.md"
fi

if [ -f "${PAI_DIR}/RUNTIME_CONSTITUTION.md" ]; then
    active_files+=("${PAI_DIR}/RUNTIME_CONSTITUTION.md")
else
    record_fail "missing ${PAI_DIR}/RUNTIME_CONSTITUTION.md"
fi

latest=""
if [ -f "${PAI_DIR}/ALGORITHM/LATEST" ]; then
    latest="$(tr -d '[:space:]' < "${PAI_DIR}/ALGORITHM/LATEST")"
else
    record_fail "missing ${PAI_DIR}/ALGORITHM/LATEST"
fi

if [ -n "$latest" ]; then
    active_algorithm="${PAI_DIR}/ALGORITHM/${latest}.md"
    if [ -f "$active_algorithm" ]; then
        active_files+=("$active_algorithm")
    else
        record_fail "active Algorithm file missing: ${active_algorithm}"
    fi
fi

mapfile -t agent_files < <(existing_files_from_dir "$AGENTS_DIR" "*.md")
mapfile -t command_files < <(existing_files_from_dir "$COMMANDS_DIR" "*.md")
if [ -d "$SKILLS_DIR" ]; then
    mapfile -t skill_files < <(
        find "$SKILLS_DIR" \
            -path '*/Patterns/*' -prune -o \
            -type f \( -name 'SKILL.md' -o -path '*/Workflows/*.md' \) -print | sort
    )
else
    skill_files=()
fi

scan_unqualified() {
    local severity="$1"
    local label="$2"
    local pattern="$3"
    shift 3
    [ "$#" -gt 0 ] || return 0

    local matches
    matches="$(
        grep -nEI "$pattern" "$@" 2>/dev/null \
            | grep -viE "$QUALIFIER_PATTERN" \
            || true
    )"

    if [ -n "$matches" ]; then
        if [ "$severity" = "fail" ]; then
            print_limited_matches "$matches"
            record_fail "$label"
        else
            record_warn "$label"
            if [ "$SHOW_WARNINGS" = true ]; then
                print_limited_matches "$matches"
            fi
        fi
    fi
}

scan_tool_refs() {
    local severity="$1"
    local label="$2"
    shift 2
    [ "$#" -gt 0 ] || return 0

    local matches
    matches="$(grep -nEI '(~/.config/opencode/PAI/)?(PAI/)?TOOLS/[A-Za-z0-9_.-]+\.ts|(^|[^A-Za-z0-9_./-])TOOLS/[A-Za-z0-9_.-]+\.ts' "$@" 2>/dev/null || true)"
    [ -n "$matches" ] || return 0

    while IFS= read -r match; do
        [ -n "$match" ] || continue
        local file_path line_text refs ref tool_name tool_path message
        file_path="${match%%:*}"
        line_text="${match#*:}"
        line_text="${line_text#*:}"

        if is_qualified "$line_text"; then
            continue
        fi

        refs="$(printf '%s\n' "$line_text" \
            | grep -Eo '(~/.config/opencode/PAI/)?(PAI/)?TOOLS/[A-Za-z0-9_.-]+\.ts|(^|[^A-Za-z0-9_./-])TOOLS/[A-Za-z0-9_.-]+\.ts' \
            | sed -E 's|^[^A-Za-z0-9_./~$-]+||' \
            || true)"

        while IFS= read -r ref; do
            [ -n "$ref" ] || continue
            tool_name="$(basename "$ref")"
            tool_path="${PAI_DIR}/TOOLS/${tool_name}"
            if [ ! -f "$tool_path" ]; then
                if grep -niF "$tool_name" "$file_path" 2>/dev/null | grep -qiE "$QUALIFIER_PATTERN|test -f|not found"; then
                    continue
                fi
                message="${label}: ${tool_name} referenced without availability fallback at ${match%%:*}"
                if [ "$severity" = "fail" ]; then
                    record_fail "$message"
                else
                    record_skill_issue "$message"
                fi
            fi
        done <<< "$refs"
    done <<< "$matches"
}

scan_agent_refs() {
    local severity="$1"
    local label="$2"
    shift 2
    [ "$#" -gt 0 ] || return 0

    local matches
    matches="$(grep -nEI '(Agent|Task)\(subagent_type[=:][[:space:]]*['\''"][A-Za-z0-9_-]+['\''"]' "$@" 2>/dev/null || true)"
    [ -n "$matches" ] || return 0

    while IFS= read -r match; do
        [ -n "$match" ] || continue
        local line_text agent_name message
        line_text="${match#*:}"
        line_text="${line_text#*:}"
        agent_name="$(printf '%s\n' "$line_text" | sed -E 's/.*subagent_type[=:][[:space:]]*['\''"]([^'\''"]+)['\''"].*/\1/')"

        case "$agent_name" in
            build|build-mobile|general-purpose|AgentType)
                continue
                ;;
        esac

        if [ ! -f "${AGENTS_DIR}/${agent_name}.md" ]; then
            message="${label}: ${agent_name} referenced but ${AGENTS_DIR}/${agent_name}.md is absent at ${match%%:*}"
            if [ "$severity" = "fail" ]; then
                record_fail "$message"
            else
                record_skill_issue "$message"
            fi
        fi
    done <<< "$matches"
}

# Active instruction surfaces: strict failures.
if [ "${#active_files[@]}" -gt 0 ]; then
    scan_unqualified fail "stale system-prompt promise in active PAI instructions" 'PAI_SYSTEM_PROMPT|--append-system-prompt-file' "${active_files[@]}"
    scan_unqualified fail "stale prompt-hook promise in active PAI instructions" 'UserPromptSubmit|PromptProcessing\.hook|additionalContext|Sonnet classifier|subscription-billed|No regex fallback' "${active_files[@]}"
    scan_unqualified fail "duplicated PAI/PAI path in active PAI instructions" 'PAI/PAI/' "${active_files[@]}"
    scan_unqualified fail "missing CheckpointPerISC hook promised active" 'CheckpointPerISC\.hook\.ts' "${active_files[@]}"
    scan_unqualified fail "retired/missing agent promised active" 'claude-code-guide|BrowserAgent|QATester|UIReviewer' "${active_files[@]}"
    scan_unqualified fail "legacy kitty/statusline promised active" 'setPhaseTab|kitty tab' "${active_files[@]}"
    scan_unqualified fail "legacy .claude path in active PAI instructions" '(^|[^A-Za-z0-9_.-])(~|[$][{]?HOME[}]?)/\.claude|\.claude/' "${active_files[@]}"
    scan_tool_refs fail "active PAI instructions" "${active_files[@]}"
    scan_agent_refs fail "active PAI instructions" "${active_files[@]}"
fi

# Agent prompts are active operational surfaces.
if [ "${#agent_files[@]}" -gt 0 ]; then
    scan_unqualified fail "legacy .claude path in installed/source agents" '(^|[^A-Za-z0-9_.-])(~|[$][{]?HOME[}]?)/\.claude|\.claude/' "${agent_files[@]}"
    scan_unqualified fail "retired/missing agent referenced by active agents" 'claude-code-guide|BrowserAgent|QATester|UIReviewer' "${agent_files[@]}"
    scan_tool_refs fail "active agent prompt" "${agent_files[@]}"
    scan_agent_refs fail "active agent prompt" "${agent_files[@]}"
fi

# Skill files are operational, but many are inherited and patched/rewritten in later plans.
# They warn by default and can be promoted with --strict-skills.
if [ "${#skill_files[@]}" -gt 0 ]; then
    scan_unqualified warn "legacy .claude path in skills" '(^|[^A-Za-z0-9_.-])(~|[$][{]?HOME[}]?)/\.claude|\.claude/' "${skill_files[@]}"
    scan_unqualified warn "retired/missing agent referenced by skills" 'claude-code-guide|BrowserAgent|QATester|UIReviewer' "${skill_files[@]}"
    scan_unqualified warn "stale prompt-hook promise in skills" 'UserPromptSubmit|PromptProcessing\.hook|additionalContext|PAI_SYSTEM_PROMPT|--append-system-prompt-file' "${skill_files[@]}"
    scan_tool_refs warn "skill prompt/workflow" "${skill_files[@]}"
    scan_agent_refs warn "skill prompt/workflow" "${skill_files[@]}"
fi

# Config and installed/repo registration checks.
if [ ! -f "$CONFIG_PATH" ]; then
    record_fail "missing OpenCode config: ${CONFIG_PATH}"
else
    plugin_refs="$(grep -F -o 'pai-hooks.js' "$CONFIG_PATH" 2>/dev/null | wc -l)"
    if [ "$plugin_refs" -ne 1 ]; then
        record_fail "OpenCode config should reference pai-hooks.js exactly once; found ${plugin_refs}"
    fi

    if ! grep -q 'CLAUDE.md' "$CONFIG_PATH"; then
        record_fail "OpenCode config does not include PAI/CLAUDE.md instructions"
    fi

    pai_notify_refs="$(grep -F -o 'pai_notify' "$CONFIG_PATH" 2>/dev/null | wc -l)"
    if [ "$pai_notify_refs" -lt 2 ]; then
        record_fail "OpenCode config primary agents do not both require pai_notify"
    fi

    for command_file in "${command_files[@]}"; do
        command_name="$(basename "$command_file" .md)"
        if ! grep -q "\"${command_name}\"[[:space:]]*:" "$CONFIG_PATH"; then
            record_fail "command file ${command_name}.md is not registered in OpenCode config"
        fi
    done

    command_agent_refs="$(grep -Eo '"agent"[[:space:]]*:[[:space:]]*"[^"]+"' "$CONFIG_PATH" 2>/dev/null | sed -E 's/.*"agent"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
    while IFS= read -r agent_name; do
        [ -n "$agent_name" ] || continue
        case "$agent_name" in
            build|build-mobile)
                continue
                ;;
        esac
        if [ ! -f "${AGENTS_DIR}/${agent_name}.md" ]; then
            record_fail "OpenCode config command references missing agent: ${agent_name}"
        fi
    done <<< "$command_agent_refs"
fi

if [ ! -f "$PLUGIN_PATH" ]; then
    record_fail "missing OpenCode PAI plugin: ${PLUGIN_PATH}"
else
    if ! grep -q "RUNTIME_CONSTITUTION.md" "$PLUGIN_PATH"; then
        record_fail "OpenCode PAI plugin does not load RUNTIME_CONSTITUTION.md"
    fi
    if ! grep -q "tool.execute.before" "$PLUGIN_PATH" || ! grep -q "permission.asked" "$PLUGIN_PATH"; then
        record_fail "OpenCode PAI plugin is missing security hook surfaces"
    fi
fi

# Tool manifest checks keep the active `PAI/TOOLS` surface honest: implemented
# helpers must exist; deferred/optional helpers must document fallback behavior.
TOOLS_VALIDATOR="${SCRIPT_DIR}/validate-tools-manifest.js"
if [ ! -f "$TOOLS_VALIDATOR" ]; then
    record_fail "missing tools manifest validator: ${TOOLS_VALIDATOR}"
elif ! command -v bun >/dev/null 2>&1; then
    record_fail "bun is required to run tools manifest validator"
else
    if [ "$MODE" = "repo" ]; then
        if ! bun "$TOOLS_VALIDATOR" --repo >/dev/null 2>&1; then
            record_fail "tools manifest validator failed"
        fi
    else
        if ! bun "$TOOLS_VALIDATOR" --root "$OPENCODE_HOME" >/dev/null 2>&1; then
            record_fail "tools manifest validator failed"
        fi
    fi
fi

if [ "$failures" -eq 0 ]; then
    if [ "$warnings" -gt 0 ]; then
        echo "PASS: promise integrity checks passed (${warnings} warnings)"
    else
        echo "PASS: promise integrity checks passed"
    fi
    exit 0
fi

echo "SUMMARY: ${failures} failures, ${warnings} warnings"
exit 1
