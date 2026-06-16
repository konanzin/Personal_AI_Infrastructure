#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  PAI for OpenCode — One-Command Installer
#  Usage: ./install.sh [--update] [--check] [--repair] [--preserve-user]
# ═══════════════════════════════════════════════════════════

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# ─── Paths ────────────────────────────────────────────────
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OPENCODE_DIR="${HOME}/.config/opencode"
PAI_DIR="${OPENCODE_DIR}/PAI"
PLUGINS_DIR="${OPENCODE_DIR}/plugins"
AGENTS_DIR="${OPENCODE_DIR}/agents"
SKILLS_DIR="${OPENCODE_DIR}/skills"
COMMANDS_DIR="${OPENCODE_DIR}/commands"
DOCS_DIR="${OPENCODE_DIR}/docs"
INSTALL_MANIFEST="${REPO_DIR}/opencode/install-manifest.json"

# ─── Flags ────────────────────────────────────────────────
UPDATE_MODE=false
BOOTSTRAP_DEPS=true
CHECK_MODE=false
REPAIR_MODE=false
PRESERVE_USER=true

CONFIG_REGENERATED=false
ARCHIVE_DIR=""
ARCHIVED_AGENTS=()
ARCHIVED_COMMANDS=()
ARCHIVED_SKILLS=()

for arg in "$@"; do
    case "$arg" in
        --update) UPDATE_MODE=true ;;
        --no-bootstrap) BOOTSTRAP_DEPS=false ;;
        --check) CHECK_MODE=true; BOOTSTRAP_DEPS=false ;;
        --repair) REPAIR_MODE=true ;;
        --preserve-user) PRESERVE_USER=true ;;
        -h|--help)
            echo "Usage: ./install.sh [--update] [--check] [--repair] [--preserve-user] [--no-bootstrap]"
            echo ""
            echo "  --check          Report drift between repo manifest and installed OpenCode runtime; make no changes."
            echo "  --repair         Reinstall generated artifacts, archive stale generated dirs, and regenerate config."
            echo "  --preserve-user  Preserve PAI/USER, PAI/MEMORY, and .env (default)."
            echo "  --update         Create a full PAI backup before reinstalling."
            echo "  --no-bootstrap   Do not install missing prerequisites automatically."
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

# ─── Logging ──────────────────────────────────────────────
log() { echo -e "${BLUE}[PAI-INSTALL]${RESET} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error() { echo -e "${RED}[ERROR]${RESET} $1"; }

require_bun_for_manifest() {
    if ! command -v bun &>/dev/null; then
        error "bun is required to read opencode/install-manifest.json"
        exit 1
    fi
}

manifest_values() {
    local key="$1"
    require_bun_for_manifest
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

archive_generated_path() {
    local path="$1"
    local bucket="$2"
    local name
    name="$(basename "$path")"

    if [ ! -e "$path" ]; then
        return 0
    fi

    if [ -z "$ARCHIVE_DIR" ]; then
        ARCHIVE_DIR="${OPENCODE_DIR}/.pai-stale/$(date +%Y%m%d-%H%M%S)"
    fi

    mkdir -p "$ARCHIVE_DIR/$bucket"

    local target="$ARCHIVE_DIR/$bucket/$name"
    if [ -e "$target" ]; then
        target="$ARCHIVE_DIR/$bucket/${name}.$(date +%s)"
    fi

    mv "$path" "$target"
}

render_expected_config() {
    local output="$1"

    if [ ! -f "${REPO_DIR}/opencode/config/opencode.jsonc.template" ]; then
        error "Missing opencode/config/opencode.jsonc.template"
        exit 1
    fi

    sed "s|\"./plugins/pai-hooks.js\"|\"${PLUGINS_DIR}/pai-hooks.js\"|" \
        "${REPO_DIR}/opencode/config/opencode.jsonc.template" > "$output"
}

require_curl() {
    if ! command -v curl &>/dev/null; then
        error "curl is required to bootstrap missing dependencies"
        exit 1
    fi
}

install_opencode() {
    log "OpenCode not found — bootstrapping..."
    require_curl
    if curl -fsSL https://opencode.ai/install | bash; then
        export PATH="$HOME/.opencode/bin:$PATH"
        success "OpenCode installed"
    else
        error "Failed to install OpenCode automatically"
        exit 1
    fi
}

install_bun() {
    log "bun not found — bootstrapping..."
    require_curl
    if curl -fsSL https://bun.sh/install | bash; then
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
        success "bun installed"
    else
        error "Failed to install bun automatically"
        exit 1
    fi
}

# ─── Check Prerequisites ──────────────────────────────────
check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing=()
    
    if ! command -v git &>/dev/null; then
        missing+=("git")
    fi
    
    if ! command -v opencode &>/dev/null; then
        if [ "$BOOTSTRAP_DEPS" = true ]; then
            install_opencode
        else
            missing+=("opencode")
            echo "   Install: https://opencode.ai"
        fi
    fi

    if ! command -v bun &>/dev/null; then
        if [ "$BOOTSTRAP_DEPS" = true ]; then
            install_bun
        else
            missing+=("bun")
            echo "   Install: https://bun.sh"
        fi
    fi

    if ! command -v opencode &>/dev/null; then
        missing+=("opencode")
    fi
    if ! command -v bun &>/dev/null; then
        missing+=("bun")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing: ${missing[*]}"
        exit 1
    fi
    
    success "Prerequisites OK"
}

# ─── Backup ───────────────────────────────────────────────
create_backup() {
    if [ "$UPDATE_MODE" = true ] && [ -d "$PAI_DIR" ]; then
        local backup_dir="${HOME}/.config/opencode-pai-backup-$(date +%Y%m%d-%H%M%S)"
        log "Creating backup..."
        cp -R "$PAI_DIR" "$backup_dir"
        success "Backup: $backup_dir"
    fi
}

# ─── Create Directories ───────────────────────────────────
create_directories() {
    log "Creating directories..."
    
    mkdir -p "$PAI_DIR"/{ALGORITHM,DOCUMENTATION,MEMORY/{STATE,WORK,KNOWLEDGE,LEARNING,RESEARCH},PULSE,TOOLS,TEMPLATES,USER/{TELOS,Config},bin,logs,tests,schemas}
    mkdir -p "$PAI_DIR/plugins/lib"
    mkdir -p "$PLUGINS_DIR"
    mkdir -p "$AGENTS_DIR"
    mkdir -p "$COMMANDS_DIR"
    mkdir -p "$SKILLS_DIR"
    mkdir -p "$DOCS_DIR"
    
    success "Directories OK"
}

archive_stale_artifacts() {
    log "Checking generated artifact drift..."

    local stale

    if [ -d "$AGENTS_DIR" ]; then
        while IFS= read -r stale; do
            [ -n "$stale" ] || continue
            if [ -f "$AGENTS_DIR/$stale" ]; then
                archive_generated_path "$AGENTS_DIR/$stale" "agents"
                ARCHIVED_AGENTS+=("$stale")
            fi
        done < <(manifest_values "retired_agents")

        while IFS= read -r file; do
            local name
            name="$(basename "$file")"
            if ! manifest_has "agents" "$name"; then
                archive_generated_path "$file" "agents"
                ARCHIVED_AGENTS+=("$name")
            fi
        done < <(find "$AGENTS_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
    fi

    if [ -d "$COMMANDS_DIR" ]; then
        while IFS= read -r file; do
            local name
            name="$(basename "$file")"
            if ! manifest_has "commands" "$name"; then
                archive_generated_path "$file" "commands"
                ARCHIVED_COMMANDS+=("$name")
            fi
        done < <(find "$COMMANDS_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
    fi

    if [ -d "$SKILLS_DIR" ]; then
        while IFS= read -r dir; do
            local name
            name="$(basename "$dir")"
            if ! manifest_has "skills" "$name"; then
                archive_generated_path "$dir" "skills"
                ARCHIVED_SKILLS+=("$name")
            fi
        done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    fi

    if [ ${#ARCHIVED_AGENTS[@]} -eq 0 ] && [ ${#ARCHIVED_COMMANDS[@]} -eq 0 ] && [ ${#ARCHIVED_SKILLS[@]} -eq 0 ]; then
        success "No stale generated artifacts found"
    else
        success "Archived stale generated artifacts to $ARCHIVE_DIR"
    fi
}

# ─── Install Plugins ──────────────────────────────────────
install_plugins() {
    log "Installing plugins..."
    
    # Copy main plugin only (lib goes to separate directory)
    cp -f "${REPO_DIR}/opencode/plugins/pai-hooks.js" "$PLUGINS_DIR/"
    rm -f "$PLUGINS_DIR/pai-hooks.lib.js"
    
    # Create lib subdirectory and copy all library files
    mkdir -p "$PLUGINS_DIR/lib"
    cp -f "${REPO_DIR}/opencode/plugins/lib/"*.js "$PLUGINS_DIR/lib/"

    # Mirror plugin libs into installed PAI tree for vendored E2E scenarios
    mkdir -p "$PAI_DIR/plugins/lib"
    cp -f "${REPO_DIR}/opencode/plugins/lib/"*.js "$PAI_DIR/plugins/lib/"
    
    success "Plugins installed (main + lib files)"
}

# ─── Install Agents ───────────────────────────────────────
install_agents() {
    log "Installing agents..."

    cp -f "${REPO_DIR}/opencode/agents/"*.md "$AGENTS_DIR/"

    local count=$(ls "$AGENTS_DIR/"*.md | wc -l)
    success "$count agents installed"
}

# ─── Install Commands ─────────────────────────────────────
install_commands() {
    log "Installing commands..."
    
    cp -f "${REPO_DIR}/opencode/commands/"*.md "$COMMANDS_DIR/"
    
    success "Commands installed"
}

# ─── Install Skills ───────────────────────────────────────
install_skills() {
    log "Installing skills..."
    
    local skills_src=""
    if [ -d "${REPO_DIR}/skills" ] && [ "$(ls -A ${REPO_DIR}/skills)" ]; then
        skills_src="${REPO_DIR}/skills"
    elif [ -d "${REPO_DIR}/opencode/skills" ] && [ "$(ls -A ${REPO_DIR}/opencode/skills)" ]; then
        skills_src="${REPO_DIR}/opencode/skills"
    fi
    
    if [ -z "$skills_src" ]; then
        error "Required skills directory missing in repo (expected skills/ or opencode/skills/)"
        exit 1
    fi
    
    cp -R "${skills_src}/"* "$SKILLS_DIR/"
    
    local count=$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    success "$count skills installed"
}

# ─── Install PAI Core ─────────────────────────────────────
install_pai_core() {
    log "Installing PAI core..."
    
    if [ ! -d "${REPO_DIR}/PAI" ]; then
        error "Required PAI directory missing in repo (expected PAI/)"
        exit 1
    fi
    
    # Copy full PAI tree from repo, preserving existing user data on update
    for dir in ALGORITHM DOCUMENTATION PULSE TOOLS TEMPLATES bin config tests; do
        if [ -d "${REPO_DIR}/PAI/$dir" ]; then
            cp -R "${REPO_DIR}/PAI/$dir" "$PAI_DIR/"
        fi
    done

    # Copy canonical OpenCode runtime E2E scenarios into installed runtime
    if [ -d "${REPO_DIR}/opencode/tests/e2e-runtime" ]; then
        mkdir -p "$PAI_DIR/tests"
        cp -R "${REPO_DIR}/opencode/tests/e2e-runtime" "$PAI_DIR/tests/"
    fi

    mkdir -p "$PAI_DIR/config"
    cp -f "${REPO_DIR}/opencode/config/opencode.jsonc.template" "$PAI_DIR/config/opencode.jsonc.template"
    cp -f "${REPO_DIR}/opencode/install-manifest.json" "$PAI_DIR/install-manifest.json"

    mkdir -p "$PAI_DIR/schemas"
    cp -f "${REPO_DIR}/opencode/schemas/"*.json "$PAI_DIR/schemas/" 2>/dev/null || true

    if [ -d "${REPO_DIR}/opencode/docs" ]; then
        mkdir -p "$DOCS_DIR"
        cp -f "${REPO_DIR}/opencode/docs/"*.md "$DOCS_DIR/" 2>/dev/null || true
    fi
    
    # Copy root-level PAI runtime files
    for file in CLAUDE.md RUNTIME_CONSTITUTION.md; do
        if [ -f "${REPO_DIR}/PAI/$file" ]; then
            cp -f "${REPO_DIR}/PAI/$file" "$PAI_DIR/"
        fi
    done
    
    # Copy safe USER bootstrap only, preserving existing user data
    if [ -d "${REPO_DIR}/PAI/USER" ]; then
        local safe_user_files=(
            "README.md"
            "PRINCIPAL_IDENTITY.md"
            "DA_IDENTITY.md"
            "Config/README.md"
            "Config/PAI_CONFIG.yaml"
            "PROJECTS/PROJECTS.md"
            "TELOS/README.md"
            "TELOS/BELIEFS.md"
            "TELOS/BOOKS.md"
            "TELOS/CHALLENGES.md"
            "TELOS/NARRATIVES.md"
            "TELOS/PRINCIPAL_TELOS.md"
            "TELOS/PROBLEMS.md"
            "TELOS/STRATEGIES.md"
            "TELOS/WISDOM.md"
        )

        for file in "${safe_user_files[@]}"; do
            if [ -f "${REPO_DIR}/PAI/USER/$file" ]; then
                target="$PAI_DIR/USER/$file"
                if [ ! -f "$target" ]; then
                    mkdir -p "$(dirname "$target")"
                    cp -f "${REPO_DIR}/PAI/USER/$file" "$target"
                fi
            fi
        done
    fi

    # Seed the active security policy from the versioned template if the user
    # has none. PATTERNS.yaml itself is user-owned (gitignored); the template
    # lives in DOCUMENTATION and is the canonical seed. Never clobber an
    # existing user policy. If absent, the plugin falls back to its bundled
    # default, so this seed is a convenience, not a safety requirement.
    if [ -f "${REPO_DIR}/PAI/DOCUMENTATION/Security/Patterns.example.yaml" ] && [ ! -f "$PAI_DIR/USER/SECURITY/PATTERNS.yaml" ]; then
        mkdir -p "$PAI_DIR/USER/SECURITY"
        cp -f "${REPO_DIR}/PAI/DOCUMENTATION/Security/Patterns.example.yaml" "$PAI_DIR/USER/SECURITY/PATTERNS.yaml"
    fi

    # Create runtime directories that shouldn't be vendored
    mkdir -p "$PAI_DIR/MEMORY"/{STATE,WORK,KNOWLEDGE,LEARNING,RESEARCH,OBSERVABILITY}
    mkdir -p "$PAI_DIR/logs"
    
    # Copy metadata files (repo canonical versions)
    for file in .version.json .preferences.json .techstack.json .observability.json .notifications.json .pai-protected.json; do
        if [ -f "${REPO_DIR}/opencode/config/$file" ]; then
            cp -f "${REPO_DIR}/opencode/config/$file" "$PAI_DIR/"
        fi
    done

    if [ -f "${REPO_DIR}/opencode/config/.env" ] && [ ! -f "$PAI_DIR/.env" ]; then
        cp -f "${REPO_DIR}/opencode/config/.env" "$PAI_DIR/"
    fi
    
    # Copy scripts (repo canonical versions take precedence)
    cp -f "${REPO_DIR}/opencode/bin/"*.sh "$PAI_DIR/bin/" 2>/dev/null || true
    cp -f "${REPO_DIR}/opencode/bin/"*.js "$PAI_DIR/bin/" 2>/dev/null || true
    chmod +x "$PAI_DIR/bin/"*.sh "$PAI_DIR/bin/"*.js 2>/dev/null || true

    success "PAI core installed"
}

# ─── Install Pulse Broker (optional runtime) ──────────────
install_broker() {
    log "Installing Pulse Broker..."

    mkdir -p "$PAI_DIR/broker"
    cp -f "${REPO_DIR}/opencode/broker/"*.ts "${REPO_DIR}/opencode/broker/"*.py "$PAI_DIR/broker/" 2>/dev/null || true
    cp -f "${REPO_DIR}/opencode/config/pulse-broker.service.template" "$PAI_DIR/broker/" 2>/dev/null || true

    if command -v systemctl &>/dev/null; then
        local user_unit_dir="${HOME}/.config/systemd/user"
        mkdir -p "$user_unit_dir"
        cp -f "${REPO_DIR}/opencode/config/pulse-broker.service.template" \
            "$user_unit_dir/pulse-broker.service"
        systemctl --user daemon-reload 2>/dev/null || \
            warn "systemctl --user daemon-reload failed; unit file was still installed"
        success "Pulse Broker systemd user unit installed (enable with: systemctl --user enable --now pulse-broker)"
    else
        warn "systemctl not found; Pulse Broker service template copied only"
    fi

    success "Pulse Broker installed (optional runtime, PAI/broker/)"
}

# ─── Patch legacy upstream paths ──────────────────────────
# Upstream PAI was built for Claude Code and hardcodes ~/.claude/ in
# vendored skills and docs. The repo keeps those files pristine (clean
# diffs against upstream); the migration happens here, on the installed
# copies only. See REPO_MODEL.md ("patch at install time").
patch_installed_paths() {
    log "Patching legacy ~/.claude/ paths in installed content..."

    local targets=("$SKILLS_DIR" "$PAI_DIR" "$AGENTS_DIR" "$COMMANDS_DIR")
    local patched=0

    # PAI/bin is excluded: those are repo-canonical OpenCode scripts whose
    # grep patterns legitimately mention .claude/ (they scan for leftovers).
    for dir in "${targets[@]}"; do
        [ -d "$dir" ] || continue
        while IFS= read -r file; do
            case "$file" in
                "$PAI_DIR/bin/"*) continue ;;
            esac
            sed -i \
                -e 's|${HOME}/\.claude|${HOME}/.config/opencode|g' \
                -e 's|$HOME/\.claude|$HOME/.config/opencode|g' \
                -e 's|~/\.claude|~/.config/opencode|g' \
                -e 's|\.claude/|.config/opencode/|g' \
                -e 's|"\.claude"|".config/opencode"|g' \
                "$file"
            patched=$((patched + 1))
        done < <(grep -rlI -e '\.claude' "$dir" 2>/dev/null)
    done

    success "Patched legacy paths in $patched files"
}

# ─── Generate opencode.jsonc ──────────────────────────────
generate_config() {
    log "Generating opencode.jsonc..."
    render_expected_config "${OPENCODE_DIR}/opencode.jsonc"
    CONFIG_REGENERATED=true

    success "Config generated"
}

# ─── Validate ─────────────────────────────────────────────
validate() {
    log "Validating..."
    
    if [ -f "$PAI_DIR/bin/validate-pai-installation.sh" ]; then
        if bash "$PAI_DIR/bin/validate-pai-installation.sh" >/dev/null 2>&1; then
            success "Validation passed"
        else
            warn "Validation had issues (check manually)"
        fi
    else
        warn "Validator not found"
    fi
}

# ─── Report ───────────────────────────────────────────────
report() {
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  PAI for OpenCode — Installation Complete"
    echo "═══════════════════════════════════════════════════"
    echo ""
    echo "📁 Structure:"
    echo "  PAI:      $PAI_DIR"
    echo "  Agents:   $(ls $AGENTS_DIR/*.md 2>/dev/null | wc -l) agents"
    echo "  Skills:   $(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l) skills"
    echo "  Plugins:  $(ls $PLUGINS_DIR/pai*.js 2>/dev/null | wc -l) plugins"
    echo ""
    echo "🧹 Hygiene:"
    echo "  Config regenerated: $CONFIG_REGENERATED"
    if [ ${#ARCHIVED_AGENTS[@]} -gt 0 ]; then
        echo "  Archived agents: ${ARCHIVED_AGENTS[*]}"
    fi
    if [ ${#ARCHIVED_COMMANDS[@]} -gt 0 ]; then
        echo "  Archived commands: ${ARCHIVED_COMMANDS[*]}"
    fi
    if [ ${#ARCHIVED_SKILLS[@]} -gt 0 ]; then
        echo "  Archived skills: ${ARCHIVED_SKILLS[*]}"
    fi
    if [ -n "$ARCHIVE_DIR" ]; then
        echo "  Archive: $ARCHIVE_DIR"
    fi
    echo ""
    echo "🚀 Next steps:"
    echo "  1. Run: opencode"
    echo "  2. Use /status to verify"
    echo "  3. Use /pai to start Algorithm"
    echo "  4. Validate drift: bash ${REPO_DIR}/opencode/install.sh --check"
    echo ""
    
    if [ "$UPDATE_MODE" = true ]; then
        echo "🔄 Updated from backup"
    fi
}

# ─── Validate Repo Content ────────────────────────────────
validate_repo_content() {
    log "Validating repo content..."
    
    local missing=()
    
    if [ ! -d "${REPO_DIR}/PAI" ]; then
        missing+=("PAI/")
    fi
    
    if [ ! -d "${REPO_DIR}/skills" ] && [ ! -d "${REPO_DIR}/opencode/skills" ]; then
        missing+=("skills/")
    fi
    
    if [ ! -f "${REPO_DIR}/opencode/plugins/pai-hooks.js" ]; then
        missing+=("opencode/plugins/pai-hooks.js")
    fi

    if [ ! -f "${REPO_DIR}/PAI/RUNTIME_CONSTITUTION.md" ]; then
        missing+=("PAI/RUNTIME_CONSTITUTION.md")
    fi
    
    if [ ! -f "${REPO_DIR}/opencode/config/opencode.jsonc.template" ]; then
        missing+=("opencode/config/opencode.jsonc.template")
    fi

    if [ ! -f "$INSTALL_MANIFEST" ]; then
        missing+=("opencode/install-manifest.json")
    fi

    if [ ! -d "${REPO_DIR}/opencode/schemas" ]; then
        missing+=("opencode/schemas/")
    fi

    if [ ! -f "${REPO_DIR}/opencode/bin/validate-doc-integrity.js" ]; then
        missing+=("opencode/bin/validate-doc-integrity.js")
    fi

    if [ ! -f "${REPO_DIR}/opencode/bin/validate-tools-manifest.js" ]; then
        missing+=("opencode/bin/validate-tools-manifest.js")
    fi

    if [ ! -f "${REPO_DIR}/PAI/TOOLS/manifest.json" ]; then
        missing+=("PAI/TOOLS/manifest.json")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Required repo content missing: ${missing[*]}"
        error "This installer requires a fully vendored repo. Run the vendor script first."
        exit 1
    fi
    
    success "Repo content OK"
}

record_check_failure() {
    local message="$1"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
    echo -e "  ${RED}✗${RESET} $message"
}

record_check_pass() {
    local message="$1"
    echo -e "  ${GREEN}✓${RESET} $message"
}

check_manifest_dir() {
    local label="$1"
    local key="$2"
    local dir="$3"
    local type="$4"
    local suffix="${5:-}"
    local missing=()
    local stale=()
    local expected
    local path
    local name

    while IFS= read -r expected; do
        [ -n "$expected" ] || continue
        path="$dir/$expected"
        if [ ! -e "$path" ]; then
            missing+=("$expected")
        fi
    done < <(manifest_values "$key")

    if [ -d "$dir" ]; then
        local find_cmd=()
        if [ -n "$suffix" ]; then
            find_cmd=(find "$dir" -mindepth 1 -maxdepth 1 -type "$type" -name "$suffix")
        else
            find_cmd=(find "$dir" -mindepth 1 -maxdepth 1 -type "$type")
        fi

        while IFS= read -r path; do
            name="$(basename "$path")"
            if ! manifest_has "$key" "$name"; then
                stale+=("$name")
            fi
        done < <("${find_cmd[@]}" 2>/dev/null | sort)
    else
        missing+=("<directory-missing>")
    fi

    if [ ${#missing[@]} -eq 0 ] && [ ${#stale[@]} -eq 0 ]; then
        record_check_pass "$label matches install manifest"
    else
        [ ${#missing[@]} -eq 0 ] || record_check_failure "$label missing: ${missing[*]}"
        [ ${#stale[@]} -eq 0 ] || record_check_failure "$label stale: ${stale[*]}"
    fi
}

check_config_drift() {
    if [ ! -f "${OPENCODE_DIR}/opencode.jsonc" ]; then
        record_check_failure "opencode.jsonc missing"
        return
    fi

    local expected
    expected="$(mktemp)"
    render_expected_config "$expected"

    if cmp -s "$expected" "${OPENCODE_DIR}/opencode.jsonc"; then
        record_check_pass "opencode.jsonc matches rendered template"
    else
        record_check_failure "opencode.jsonc differs from rendered template"
    fi

    rm -f "$expected"
}

check_runtime_contracts() {
    local schema_count
    schema_count=$(find "$PAI_DIR/schemas" -maxdepth 1 -type f -name '*.schema.json' 2>/dev/null | wc -l | tr -d ' ')
    if [ "$schema_count" -ge 6 ]; then
        record_check_pass "Observability schemas installed"
    else
        record_check_failure "Observability schemas missing or incomplete"
    fi

    if [ -x "$PAI_DIR/bin/validate-doc-integrity.js" ]; then
        record_check_pass "DocIntegrity validator installed"
    else
        record_check_failure "DocIntegrity validator missing or not executable"
    fi

    if [ -x "$PAI_DIR/bin/validate-tools-manifest.js" ]; then
        record_check_pass "Tools manifest validator installed"
    else
        record_check_failure "Tools manifest validator missing or not executable"
    fi

    if [ -f "$PAI_DIR/TOOLS/manifest.json" ]; then
        record_check_pass "Tools manifest installed"
    else
        record_check_failure "Tools manifest missing"
    fi

    if [ -x "$PAI_DIR/bin/validate-tools-manifest.js" ] && bun "$PAI_DIR/bin/validate-tools-manifest.js" --root "$OPENCODE_DIR" >/dev/null 2>&1; then
        record_check_pass "Tools manifest matches installed PAI/TOOLS"
    else
        record_check_failure "Tools manifest validation failed"
    fi

    if [ -f "$DOCS_DIR/OBSERVABILITY_CONTRACTS.md" ]; then
        record_check_pass "OpenCode observability contract docs installed"
    else
        record_check_failure "OpenCode observability contract docs missing"
    fi

    if [ -f "$PAI_DIR/USER/SECURITY/PATTERNS.yaml" ]; then
        record_check_pass "Security policy (PATTERNS.yaml) installed"
    else
        record_check_failure "Security policy (PATTERNS.yaml) missing — plugin runs on bundled default"
    fi
}

run_check_mode() {
    echo "═══════════════════════════════════════════════════"
    echo "  PAI for OpenCode — Install Drift Check"
    echo "═══════════════════════════════════════════════════"
    echo ""

    require_bun_for_manifest
    validate_repo_content

    CHECK_FAILURES=0

    check_manifest_dir "Agents" "agents" "$AGENTS_DIR" "f" "*.md"
    check_manifest_dir "Commands" "commands" "$COMMANDS_DIR" "f" "*.md"
    check_manifest_dir "Skills" "skills" "$SKILLS_DIR" "d"
    check_config_drift
    check_runtime_contracts

    echo ""
    if [ "$CHECK_FAILURES" -eq 0 ]; then
        success "Installed runtime matches manifest"
        return 0
    fi

    warn "$CHECK_FAILURES drift issue(s) found. Run: bash ${REPO_DIR}/opencode/install.sh --repair"
    return 1
}

# ─── Main ─────────────────────────────────────────────────
main() {
    if [ "$CHECK_MODE" = true ]; then
        run_check_mode
        exit $?
    fi

    echo "═══════════════════════════════════════════════════"
    echo "  PAI v5.0.0 for OpenCode"
    if [ "$UPDATE_MODE" = true ]; then
        echo "  [UPDATE MODE]"
    fi
    if [ "$REPAIR_MODE" = true ]; then
        echo "  [REPAIR MODE]"
    fi
    echo "═══════════════════════════════════════════════════"
    echo ""
    
    check_prerequisites
    validate_repo_content
    create_backup
    create_directories
    archive_stale_artifacts
    install_plugins
    install_agents
    install_commands
    install_skills
    install_pai_core
    install_broker
    patch_installed_paths
    generate_config
    validate
    report
    
    success "Done!"
    echo ""
    echo "For subsequent plugin updates without full reinstall:"
    echo "  bash ${REPO_DIR}/opencode/bin/deploy-plugin.sh"
}

main "$@"
