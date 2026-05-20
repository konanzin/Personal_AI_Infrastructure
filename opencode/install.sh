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
    mkdir -p "$PLUGINS_DIR"
    mkdir -p "$AGENTS_DIR"
    mkdir -p "$COMMANDS_DIR"
    mkdir -p "$SKILLS_DIR"
    
    success "Directories OK"
}

# ─── Install Plugins ──────────────────────────────────────
install_plugins() {
    log "Installing plugins..."
    
    cp -f "${REPO_DIR}/opencode/plugins/"*.js "$PLUGINS_DIR/"
    
    success "Plugins installed"
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
    
    if [ -d "${REPO_DIR}/skills" ]; then
        cp -R "${REPO_DIR}/skills/"* "$SKILLS_DIR/"
    elif [ -d "${REPO_DIR}/opencode/skills" ]; then
        cp -R "${REPO_DIR}/opencode/skills/"* "$SKILLS_DIR/"
    fi
    
    local count=$(ls "$SKILLS_DIR/" | wc -l)
    success "$count skills installed"
}

# ─── Install PAI Core ─────────────────────────────────────
install_pai_core() {
    log "Installing PAI core..."
    
    # Copy from repo's PAI directory or use submodule
    if [ -d "${REPO_DIR}/PAI" ]; then
        # Copy preserving existing user data
        for dir in ALGORITHM DOCUMENTATION PULSE TOOLS TEMPLATES; do
            if [ -d "${REPO_DIR}/PAI/$dir" ]; then
                cp -R "${REPO_DIR}/PAI/$dir" "$PAI_DIR/"
            fi
        done
        
        # Only copy USER if it doesn't exist
        if [ ! -d "$PAI_DIR/USER" ] && [ -d "${REPO_DIR}/PAI/USER" ]; then
            cp -R "${REPO_DIR}/PAI/USER" "$PAI_DIR/"
        fi
    fi
    
    # Copy metadata files
    for file in .version.json .preferences.json .techstack.json .observability.json .notifications.json .env .pai-protected.json; do
        if [ -f "${REPO_DIR}/opencode/config/$file" ]; then
            cp -f "${REPO_DIR}/opencode/config/$file" "$PAI_DIR/"
        fi
    done
    
    # Copy scripts
    cp -f "${REPO_DIR}/opencode/bin/"*.sh "$PAI_DIR/bin/" 2>/dev/null || true
    chmod +x "$PAI_DIR/bin/"*.sh 2>/dev/null || true
    
    success "PAI core installed"
}

# ─── Generate opencode.jsonc ──────────────────────────────
generate_config() {
    log "Generating opencode.jsonc..."
    
    if [ -f "${REPO_DIR}/opencode/config/opencode.jsonc.template" ]; then
        # Use template
        cp -f "${REPO_DIR}/opencode/config/opencode.jsonc.template" "${OPENCODE_DIR}/opencode.jsonc"
    else
        # Generate minimal config
        cat > "${OPENCODE_DIR}/opencode.jsonc" << 'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["./plugins/pai-hooks.js"],
  "model": "kimi-for-coding/k2p6",
  "default_agent": "build",
  "skills": {
    "paths": ["~/.config/opencode/skills"]
  },
  "reference": {
    "PAI": {"path": "~/.config/opencode/PAI"}
  },
  "instructions": ["~/.config/opencode/PAI/CLAUDE.md"]
}
EOF
    fi
    
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
}

main "$@"
