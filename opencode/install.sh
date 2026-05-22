#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  PAI for OpenCode — One-Command Installer
#  Usage: ./install.sh [--update]
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

# ─── Flags ────────────────────────────────────────────────
UPDATE_MODE=false
[ "${1:-}" = "--update" ] && UPDATE_MODE=true

# ─── Logging ──────────────────────────────────────────────
log() { echo -e "${BLUE}[PAI-INSTALL]${RESET} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }
error() { echo -e "${RED}[ERROR]${RESET} $1"; }

# ─── Check Prerequisites ──────────────────────────────────
check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing=()
    
    if ! command -v git &>/dev/null; then
        missing+=("git")
    fi
    
    if ! command -v opencode &>/dev/null; then
        missing+=("opencode")
        echo "   Install: https://opencode.ai"
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing: ${missing[*]}"
        exit 1
    fi
    
    if ! command -v bun &>/dev/null; then
        warn "bun not found (optional)"
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
    
    mkdir -p "$PAI_DIR"/{ALGORITHM,DOCUMENTATION,MEMORY/{STATE,WORK,KNOWLEDGE,LEARNING,RESEARCH},PULSE,TOOLS,TEMPLATES,USER/{TELOS,Config},bin,logs,tests}
    mkdir -p "$PAI_DIR/plugins/lib"
    mkdir -p "$PLUGINS_DIR"
    mkdir -p "$AGENTS_DIR"
    mkdir -p "$COMMANDS_DIR"
    mkdir -p "$SKILLS_DIR"
    
    success "Directories OK"
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
    
    local count=$(ls "$SKILLS_DIR/" | wc -l)
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
    
    # Copy root-level PAI files (CLAUDE.md, etc.)
    for file in CLAUDE.md; do
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
    
    # Create runtime directories that shouldn't be vendored
    mkdir -p "$PAI_DIR/MEMORY"/{STATE,WORK,KNOWLEDGE,LEARNING,RESEARCH,OBSERVABILITY}
    mkdir -p "$PAI_DIR/logs"
    
    # Copy metadata files (repo canonical versions)
    for file in .version.json .preferences.json .techstack.json .observability.json .notifications.json .env .pai-protected.json; do
        if [ -f "${REPO_DIR}/opencode/config/$file" ]; then
            cp -f "${REPO_DIR}/opencode/config/$file" "$PAI_DIR/"
        fi
    done
    
    # Copy scripts (repo canonical versions take precedence)
    cp -f "${REPO_DIR}/opencode/bin/"*.sh "$PAI_DIR/bin/" 2>/dev/null || true
    chmod +x "$PAI_DIR/bin/"*.sh 2>/dev/null || true
    
    success "PAI core installed"
}

# ─── Generate opencode.jsonc ──────────────────────────────
generate_config() {
    log "Generating opencode.jsonc..."
    
    if [ ! -f "${REPO_DIR}/opencode/config/opencode.jsonc.template" ]; then
        error "Missing opencode/config/opencode.jsonc.template"
        exit 1
    fi

    cp -f "${REPO_DIR}/opencode/config/opencode.jsonc.template" "${OPENCODE_DIR}/opencode.jsonc"
    
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
    echo "  Skills:   $(ls $SKILLS_DIR/ 2>/dev/null | wc -l) skills"
    echo "  Plugins:  $(ls $PLUGINS_DIR/pai*.js 2>/dev/null | wc -l) plugins"
    echo ""
    echo "🚀 Next steps:"
    echo "  1. Run: opencode"
    echo "  2. Use /status to verify"
    echo "  3. Use /pai to start Algorithm"
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
    
    if [ ! -f "${REPO_DIR}/opencode/config/opencode.jsonc.template" ]; then
        missing+=("opencode/config/opencode.jsonc.template")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Required repo content missing: ${missing[*]}"
        error "This installer requires a fully vendored repo. Run the vendor script first."
        exit 1
    fi
    
    success "Repo content OK"
}

# ─── Main ─────────────────────────────────────────────────
main() {
    echo "═══════════════════════════════════════════════════"
    echo "  PAI v5.0.0 for OpenCode"
    if [ "$UPDATE_MODE" = true ]; then
        echo "  [UPDATE MODE]"
    fi
    echo "═══════════════════════════════════════════════════"
    echo ""
    
    check_prerequisites
    validate_repo_content
    create_backup
    create_directories
    install_plugins
    install_agents
    install_commands
    install_skills
    install_pai_core
    generate_config
    validate
    report
    
    success "Done!"
    echo ""
    echo "For subsequent plugin updates without full reinstall:"
    echo "  bash ${REPO_DIR}/opencode/bin/deploy-plugin.sh"
}

main "$@"
