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
TTS_VENV_DIR="${OPENCODE_DIR}/tts-venv"
TTS_VENV_PYTHON="${TTS_VENV_DIR}/bin/python"

# ─── Flags ────────────────────────────────────────────────
UPDATE_MODE=false
BOOTSTRAP_DEPS=true
BOOTSTRAP_TTS=true
RENDERER_SERVICE=auto   # auto | yes | no — desktop voice autostart unit
ROLE=auto               # auto | anchor | renderer-client
RENDERER_CLIENT_BROKER="" # PULSE_BROKER_URL for renderer-client role
CHECK_MODE=false
REPAIR_MODE=false
PRESERVE_USER=true

CONFIG_REGENERATED=false
EDGE_TTS_STATUS="not checked"
RENDERER_SERVICE_STATUS="not checked"
ROLE_STATUS="not checked"
SANDBOX_STATUS="not checked"
ARCHIVE_DIR=""
ARCHIVED_AGENTS=()
ARCHIVED_COMMANDS=()
ARCHIVED_SKILLS=()

for arg in "$@"; do
    case "$arg" in
        --update) UPDATE_MODE=true ;;
        --no-bootstrap) BOOTSTRAP_DEPS=false ;;
        --no-tts-bootstrap) BOOTSTRAP_TTS=false ;;
        --renderer-service) RENDERER_SERVICE=yes ;;
        --no-renderer-service) RENDERER_SERVICE=no ;;
        --anchor) ROLE=anchor ;;
        --renderer-client) ROLE=renderer-client ;;
        --renderer-client=*) ROLE=renderer-client; RENDERER_CLIENT_BROKER="${arg#*=}" ;;
        --check) CHECK_MODE=true; BOOTSTRAP_DEPS=false ;;
        --repair) REPAIR_MODE=true ;;
        --preserve-user) PRESERVE_USER=true ;;
        -h|--help)
            echo "Usage: ./install.sh [--update] [--check] [--repair] [--preserve-user] [--no-bootstrap] [--no-tts-bootstrap]"
            echo ""
            echo "  --check          Report drift between repo manifest and installed OpenCode runtime; make no changes."
            echo "  --repair         Reinstall generated artifacts, archive stale generated dirs, and regenerate config."
            echo "  --preserve-user  Preserve PAI/USER, PAI/MEMORY, and .env (default)."
            echo "  --update         Create a full PAI backup before reinstalling."
            echo "  --no-bootstrap   Do not install missing prerequisites automatically."
            echo "  --no-tts-bootstrap"
            echo "                  Skip the optional desktop Edge TTS dependency bootstrap."
            echo "  --renderer-service / --no-renderer-service"
            echo "                  Force install (or skip) the desktop voice autostart systemd unit."
            echo "                  Default (auto): installed only when Edge TTS is set up AND an audio"
            echo "                  output is detected (sound card / running PipeWire-PulseAudio), so a"
            echo "                  headless VPS never gets it even if the installer is run by hand."
            echo "                  Use --renderer-service to force it (e.g. desktop install over SSH)."
            echo "  --anchor / --renderer-client[=<broker-url>]"
            echo "                  Host role. anchor (default): runs the local broker + agent."
            echo "                  renderer-client: a desktop that only SPEAKS notifications from a"
            echo "                  REMOTE anchor broker (no local broker). The role is persisted to"
            echo "                  PAI/.role; switching roles disables the previous role's units."
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

    # Per-machine primary model (model-agnostic: the template hardcodes NO model).
    # If $PAI_DIR/USER/Config/primary-model exists and is non-empty, inject a
    # top-level "model" line at the marker. Without it, no model key is emitted and
    # OpenCode uses the host's globally configured model. Subagents omit `model`
    # and inherit this primary. Applied here so generate_config and --check render
    # identically (no false drift).
    local model_file="$PAI_DIR/USER/Config/primary-model"
    if [ -f "$model_file" ]; then
        local m
        m="$(tr -d '[:space:]' < "$model_file" 2>/dev/null)"
        if [ -n "$m" ]; then
            sed -i "/PAI_MODEL_INJECTION_POINT/a\\  \"model\": \"${m}\"," "$output"
        fi
    fi
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

# ─── T1 sandbox (bubblewrap) ──────────────────────────────
# bwrap is the kernel-level backstop under the allow-by-default bash posture.
# pai-sandbox.sh fails OPEN when bwrap is absent (command runs unconfined), so a
# missing bwrap is a SILENT loss of the T1 layer. The installer therefore always
# tries to provision it and always verifies + reports the outcome — the sandbox is
# never silently skipped. It is not a hard prerequisite (macOS has no bwrap; the
# deny floor still runs regardless), so failure warns loudly rather than aborting.
install_bwrap() {
    if command -v bwrap &>/dev/null; then
        return 0
    fi
    if [ "$(uname -s)" != "Linux" ]; then
        warn "bubblewrap (bwrap) is Linux-only; T1 filesystem sandbox is unavailable on $(uname -s)"
        return 1
    fi
    if [ "$BOOTSTRAP_DEPS" != true ]; then
        warn "bwrap missing and --no-bootstrap active — T1 sandbox will fail open (commands run unconfined)"
        return 1
    fi

    local sudo=""
    if [ "$(id -u)" -ne 0 ]; then
        if command -v sudo &>/dev/null; then
            sudo="sudo"
        else
            warn "bwrap missing and no root/sudo to install it — T1 sandbox will fail open"
            return 1
        fi
    fi

    log "bubblewrap (bwrap) not found — bootstrapping T1 sandbox dependency..."
    local ok=false
    if command -v apt-get &>/dev/null; then
        $sudo apt-get update -qq && $sudo apt-get install -y bubblewrap && ok=true
    elif command -v pacman &>/dev/null; then
        $sudo pacman -S --noconfirm --needed bubblewrap && ok=true
    elif command -v dnf &>/dev/null; then
        $sudo dnf install -y bubblewrap && ok=true
    elif command -v zypper &>/dev/null; then
        $sudo zypper --non-interactive install bubblewrap && ok=true
    elif command -v apk &>/dev/null; then
        $sudo apk add bubblewrap && ok=true
    else
        warn "No supported package manager (apt/pacman/dnf/zypper/apk) found to install bubblewrap"
        return 1
    fi

    if [ "$ok" = true ] && command -v bwrap &>/dev/null; then
        success "bubblewrap installed"
        return 0
    fi
    warn "Failed to install bubblewrap automatically — T1 sandbox will fail open until it is present"
    return 1
}

# Post-install liveness probe: replicates the plugin's sandboxAvailable() logic
# (script present + bwrap on a known path) AND actually confines a command to prove
# bwrap engages on THIS host — turning the silent fail-open into a reported status.
verify_sandbox() {
    local script="$PAI_DIR/bin/pai-sandbox.sh"

    if [ ! -f "$script" ]; then
        SANDBOX_STATUS="INACTIVE — pai-sandbox.sh not installed"
        warn "T1 sandbox: wrapper script missing at $script"
        return 1
    fi
    if ! command -v bwrap &>/dev/null; then
        SANDBOX_STATUS="FAIL-OPEN — bwrap absent (commands run unconfined)"
        warn "T1 sandbox: bwrap not present; pai-sandbox.sh will run commands unwrapped"
        return 1
    fi

    # Confinement probe: $HOME is writable to this user normally, but read-only
    # inside the sandbox (only $PWD/tmp/caches are rw). Run from /tmp so $HOME is
    # NOT $PWD, then try to write into $HOME through the wrapper. CONFINED means the
    # write was refused (bwrap engaged); LEAK means it succeeded (running unwrapped
    # — i.e. fail-open despite bwrap being present, e.g. user namespaces disabled).
    local probe marker="$HOME/.pai-sandbox-probe.$$"
    probe="$(cd /tmp && bash "$script" "touch '$marker' 2>/dev/null && echo LEAK || echo CONFINED" 2>/dev/null | tail -1)"
    rm -f "$marker" 2>/dev/null || true

    if [ "$probe" = "CONFINED" ]; then
        SANDBOX_STATUS="ACTIVE — bwrap confinement verified"
        success "T1 sandbox: confinement verified (root fs read-only outside \$PWD)"
        return 0
    fi
    SANDBOX_STATUS="DEGRADED — bwrap present but confinement probe returned '${probe:-<none>}'"
    warn "T1 sandbox: bwrap is installed but the confinement probe did not confirm (got '${probe:-<none>}')"
    return 1
}

find_python_runtime() {
    if command -v python3 &>/dev/null; then
        echo "python3"
        return 0
    fi
    if command -v python &>/dev/null; then
        echo "python"
        return 0
    fi
    return 1
}

python_has_edge_tts() {
    local python="$1"
    "$python" -c 'import edge_tts' >/dev/null 2>&1
}

edge_tts_version() {
    local python="$1"
    "$python" -c 'import edge_tts; print(getattr(edge_tts, "__version__", "unknown"))' 2>/dev/null || true
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

    # T1 sandbox backstop — attempted always, never a hard requirement (fail-open).
    install_bwrap || true

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

    # Record where the repo checkout lives so the installed agent can route
    # harness fixes back to source (HarnessCalibration skill reads this) —
    # changes belong in the repo + fences, never in the installed copy.
    printf '%s\n' "$REPO_DIR" > "$PAI_DIR/.repo"

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
    cp -f "${REPO_DIR}/opencode/bin/"*.ts "$PAI_DIR/bin/" 2>/dev/null || true
    chmod +x "$PAI_DIR/bin/"*.sh "$PAI_DIR/bin/"*.js "$PAI_DIR/bin/"*.ts 2>/dev/null || true

    # Escape-hatch token must live on PATH so opencode's permission matcher
    # sees it as a real command_name (an env-var prefix can't be gated —
    # tree-sitter drops variable_assignment nodes before matching).
    if [ -f "${REPO_DIR}/opencode/bin/pai-nosandbox" ]; then
        mkdir -p "${HOME}/.local/bin"
        cp -f "${REPO_DIR}/opencode/bin/pai-nosandbox" "${HOME}/.local/bin/"
        chmod +x "${HOME}/.local/bin/pai-nosandbox"
        command -v pai-nosandbox >/dev/null 2>&1 \
            || warn "pai-nosandbox installed to ~/.local/bin but that dir is not on PATH; the inline sandbox escape won't resolve until it is"
    fi

    success "PAI core installed"
}

# ─── Host role (anchor vs renderer-only client) ───────────
# anchor (default): this host runs the agent + the local Pulse broker.
# renderer-client: this host only SPEAKS notifications from a REMOTE anchor
# broker; it must NOT run a local broker. The role is persisted to PAI/.role so
# re-runs converge without re-passing flags; switching roles disables the
# previous role's units so the two never run side by side.
resolve_and_reconcile_role() {
    local role_file="$PAI_DIR/.role"
    local previous=""
    [ -f "$role_file" ] && previous="$(tr -d '[:space:]' < "$role_file" 2>/dev/null)"

    if [ "$ROLE" = "auto" ]; then
        ROLE="${previous:-anchor}"
    fi

    if command -v systemctl &>/dev/null && [ -n "$previous" ] && [ "$previous" != "$ROLE" ]; then
        if [ "$previous" = "anchor" ]; then
            systemctl --user disable --now pulse-broker.service 2>/dev/null || true
            systemctl --user disable --now pai-renderer.service 2>/dev/null || true
        elif [ "$previous" = "renderer-client" ]; then
            systemctl --user disable --now pai-renderer-client.service 2>/dev/null || true
        fi
        systemctl --user daemon-reload 2>/dev/null || true
        log "Role changed: $previous → $ROLE (disabled previous role's units)"
    fi

    mkdir -p "$PAI_DIR"
    printf '%s\n' "$ROLE" > "$role_file"
    ROLE_STATUS="$ROLE"
}

# ─── Install Pulse Broker (optional runtime) ──────────────
install_broker() {
    resolve_and_reconcile_role
    log "Installing Pulse Broker..."

    mkdir -p "$PAI_DIR/broker"
    rm -f "$PAI_DIR/broker/"*.py 2>/dev/null || true
    # The renderer imports broker-lib/edge-tts-lib/renderer-dedupe, so the .ts
    # files are copied for ALL roles, even when no local broker is enabled.
    cp -f "${REPO_DIR}/opencode/broker/"*.ts "$PAI_DIR/broker/" 2>/dev/null || true
    cp -f "${REPO_DIR}/opencode/config/pulse-broker.service.template" "$PAI_DIR/broker/" 2>/dev/null || true

    if [ "$ROLE" = "renderer-client" ]; then
        success "Renderer-client role: local Pulse Broker service not installed (uses remote anchor broker)"
        return 0
    fi

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

# ─── Install Edge TTS Provider ────────────────────────────
install_edge_tts() {
    log "Preparing Edge TTS voice provider..."

    if [ -x "$TTS_VENV_PYTHON" ] && python_has_edge_tts "$TTS_VENV_PYTHON"; then
        local version
        version="$(edge_tts_version "$TTS_VENV_PYTHON")"
        EDGE_TTS_STATUS="managed venv (${version:-installed})"
        success "Edge TTS ready in $TTS_VENV_DIR"
        return 0
    fi

    if [ "$BOOTSTRAP_DEPS" != true ] || [ "$BOOTSTRAP_TTS" != true ]; then
        if command -v edge-tts &>/dev/null; then
            EDGE_TTS_STATUS="PATH executable ($(edge-tts --version 2>/dev/null || echo installed))"
            success "Edge TTS executable found in PATH"
            return 0
        fi

        local existing_python
        for existing_python in python3 python; do
            if command -v "$existing_python" &>/dev/null && python_has_edge_tts "$existing_python"; then
                EDGE_TTS_STATUS="$existing_python module ($(edge_tts_version "$existing_python"))"
                success "Edge TTS Python module found via $existing_python"
                return 0
            fi
        done

        if [ "$BOOTSTRAP_TTS" != true ]; then
            EDGE_TTS_STATUS="skipped (--no-tts-bootstrap)"
            warn "Edge TTS venv not prepared because --no-tts-bootstrap is active"
        else
            EDGE_TTS_STATUS="skipped (--no-bootstrap)"
            warn "Edge TTS venv not prepared because --no-bootstrap is active"
            warn "Run without --no-bootstrap for plug-and-play desktop voice"
        fi
        return 0
    fi

    local python
    if ! python="$(find_python_runtime)"; then
        error "python3 or python is required to bootstrap Edge TTS"
        error "Install Python or rerun with --no-tts-bootstrap to skip desktop voice dependency bootstrap"
        exit 1
    fi

    mkdir -p "$TTS_VENV_DIR"
    if ! "$python" -m venv "$TTS_VENV_DIR"; then
        error "Failed to create Edge TTS venv at $TTS_VENV_DIR"
        error "Install the Python venv package for your distro, then rerun the installer"
        exit 1
    fi

    if ! "$TTS_VENV_PYTHON" -m pip --version >/dev/null 2>&1; then
        error "pip is missing from the Edge TTS venv at $TTS_VENV_DIR"
        error "Install ensurepip/pip for Python, then rerun the installer"
        exit 1
    fi

    if ! "$TTS_VENV_PYTHON" -m pip install --quiet edge-tts; then
        error "Failed to install edge-tts into $TTS_VENV_DIR"
        error "Check network/PyPI access or rerun with --no-tts-bootstrap to skip desktop voice dependency bootstrap"
        exit 1
    fi

    local version
    version="$(edge_tts_version "$TTS_VENV_PYTHON")"
    EDGE_TTS_STATUS="managed venv (${version:-installed})"
    success "Edge TTS ready in $TTS_VENV_DIR"
}

# ─── Install desktop voice autostart (renderer) ───────────
# The renderer is a per-device consumer that speaks notifications locally; it
# only makes sense where the Edge TTS provider is set up. We therefore gate its
# systemd unit on the SAME signal that distinguishes desktop from server: a
# headless server is provisioned with --no-tts-bootstrap, so it never gets this
# unit. The unit Requires/After the broker, so enabling it brings the broker up
# too — one service to manage, two processes underneath (architecture intact).
edge_tts_ready() {
    case "$EDGE_TTS_STATUS" in
        "not checked"|skipped*) return 1 ;;
        *) return 0 ;;
    esac
}

# True only if this machine can actually play audio — the real desktop-vs-VPS
# differentiator (capability), independent of the --no-tts-bootstrap intent
# signal. A headless VPS has no sound card and no running sound server, so a
# would-be renderer there would just fail; we skip it instead.
audio_output_available() {
    # 1) A usable audio player must exist.
    local have_player=false
    if [ "$(uname)" = "Darwin" ] && [ -x /usr/bin/afplay ]; then
        have_player=true
    fi
    local p
    for p in ffplay mpg123; do
        command -v "$p" &>/dev/null && have_player=true
    done
    [ "$have_player" = true ] || return 1

    # macOS desktops always have CoreAudio.
    [ "$(uname)" = "Darwin" ] && return 0

    # 2) Linux: require a real output device OR a running sound server.
    if [ -r /proc/asound/cards ] && grep -qE '^[[:space:]]*[0-9]+[[:space:]]' /proc/asound/cards 2>/dev/null; then
        return 0
    fi
    if [ -n "${XDG_RUNTIME_DIR:-}" ] && { [ -S "${XDG_RUNTIME_DIR}/pipewire-0" ] || [ -S "${XDG_RUNTIME_DIR}/pulse/native" ]; }; then
        return 0
    fi
    if command -v pactl &>/dev/null && pactl info &>/dev/null; then
        return 0
    fi
    return 1
}

install_renderer_service() {
    local anchor_tmpl="${REPO_DIR}/opencode/config/pai-renderer.service.template"
    local client_tmpl="${REPO_DIR}/opencode/config/pai-renderer-client.service.template"
    # Keep reference copies alongside the broker template regardless of gating.
    cp -f "$anchor_tmpl" "$client_tmpl" "$PAI_DIR/broker/" 2>/dev/null || true

    # Shared gates: the desktop voice autostart needs local audio + Edge TTS in
    # both roles. A renderer-client still SPEAKS locally, just from a remote
    # broker, so the same gates apply.
    if [ "$RENDERER_SERVICE" = "no" ]; then
        RENDERER_SERVICE_STATUS="skipped (--no-renderer-service)"
        return 0
    fi
    if ! command -v systemctl &>/dev/null; then
        RENDERER_SERVICE_STATUS="skipped (no systemctl)"
        return 0
    fi
    if [ "$RENDERER_SERVICE" = "auto" ] && { [ "$BOOTSTRAP_TTS" != true ] || ! edge_tts_ready; }; then
        RENDERER_SERVICE_STATUS="skipped (desktop voice not set up)"
        return 0
    fi
    if [ "$RENDERER_SERVICE" = "auto" ] && ! audio_output_available; then
        RENDERER_SERVICE_STATUS="skipped (no audio output detected)"
        return 0
    fi

    local user_unit_dir="${HOME}/.config/systemd/user"
    mkdir -p "$user_unit_dir"

    if [ "$ROLE" = "renderer-client" ]; then
        local broker_url="${RENDERER_CLIENT_BROKER:-${PULSE_BROKER_URL:-}}"
        if [ -z "$broker_url" ]; then
            RENDERER_SERVICE_STATUS="skipped (renderer-client without broker URL)"
            warn "renderer-client role needs a broker URL: rerun with --renderer-client=http://<anchor>:31337"
            return 0
        fi
        umask 077
        printf 'PULSE_BROKER_URL=%s\n' "$broker_url" > "$PAI_DIR/broker/renderer-client.env"
        log "Installing desktop voice autostart (pai-renderer-client → $broker_url)..."
        cp -f "$client_tmpl" "$user_unit_dir/pai-renderer-client.service"
        systemctl --user daemon-reload 2>/dev/null || \
            warn "systemctl --user daemon-reload failed; unit file was still installed"
        if systemctl --user enable pai-renderer-client.service 2>/dev/null; then
            RENDERER_SERVICE_STATUS="enabled renderer-client → $broker_url"
            systemctl --user start pai-renderer-client.service 2>/dev/null || \
                warn "pai-renderer-client not started now (will start on next login / graphical session)"
            success "Desktop voice (remote anchor) enabled; control with: systemctl --user start/stop pai-renderer-client"
        else
            RENDERER_SERVICE_STATUS="unit installed (enable failed)"
            warn "pai-renderer-client unit installed but enable failed; enable with: systemctl --user enable --now pai-renderer-client"
        fi
        return 0
    fi

    log "Installing desktop voice autostart (pai-renderer)..."
    cp -f "$anchor_tmpl" "$user_unit_dir/pai-renderer.service"
    systemctl --user daemon-reload 2>/dev/null || \
        warn "systemctl --user daemon-reload failed; unit file was still installed"

    if systemctl --user enable pai-renderer.service 2>/dev/null; then
        RENDERER_SERVICE_STATUS="enabled (autostart on login)"
        # Best-effort immediate start; harmless if no audio session yet.
        systemctl --user start pai-renderer.service 2>/dev/null || \
            warn "pai-renderer not started now (will start on next login / graphical session)"
        success "Desktop voice autostart enabled (pulls in pulse-broker; control with: systemctl --user start/stop pai-renderer)"
    else
        RENDERER_SERVICE_STATUS="unit installed (enable failed)"
        warn "pai-renderer unit installed but enable failed; enable manually with: systemctl --user enable --now pai-renderer"
    fi
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

# ─── Health-check timer (O5 consumer) ─────────────────────
# HARNESS_QUALITY.md O5: "degradation is noticed" requires a CONSUMER that runs
# on a schedule — an on-demand monitor nobody runs is the write-only-JSONL
# failure mode one step removed. Installs a systemd user timer that runs
# bin/pai-health-check.sh daily (classifier health + install drift, notify-send
# on warn/alert). Skipped where there is no systemd user session (mobile rigs,
# containers) — warn, not abort, matching the bwrap posture.
install_health_timer() {
    log "Installing PAI health-check timer (O5 consumer)..."

    if [ "$(uname -s)" != "Linux" ] || ! systemctl --user show-environment >/dev/null 2>&1; then
        warn "No systemd user session — health timer skipped. Run bin/pai-health-check.sh manually or via cron."
        return 0
    fi

    chmod +x "${REPO_DIR}/opencode/bin/pai-health-check.sh"

    local unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$unit_dir"

    cat > "$unit_dir/pai-health.service" <<EOF
[Unit]
Description=PAI harness health check (classifier health + install drift)

[Service]
Type=oneshot
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus
ExecStart=${REPO_DIR}/opencode/bin/pai-health-check.sh
EOF

    cat > "$unit_dir/pai-health.timer" <<EOF
[Unit]
Description=Daily PAI harness health check

[Timer]
OnCalendar=daily
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
    if systemctl --user enable --now pai-health.timer >/dev/null 2>&1; then
        success "pai-health.timer enabled (daily; notify-send on warn/alert; log: MEMORY/OBSERVABILITY/health-check.jsonl)"
    else
        warn "Could not enable pai-health.timer — enable manually: systemctl --user enable --now pai-health.timer"
    fi
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
    echo "  Host role: $ROLE_STATUS"
    echo "  T1 sandbox: $SANDBOX_STATUS"
    echo "  Edge TTS: $EDGE_TTS_STATUS"
    echo "  Desktop voice autostart: $RENDERER_SERVICE_STATUS"
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

    # T1 sandbox must still be LIVE — a host that lost bwrap, or whose user
    # namespaces got disabled, fails open silently. Presence alone is not enough:
    # run the real confinement probe (verify_sandbox) so a degraded-but-present
    # bwrap is caught here too, matching the post-install guarantee.
    if [ "${PAI_SANDBOX:-}" = "off" ]; then
        record_check_pass "T1 sandbox disabled by PAI_SANDBOX=off (operator override)"
    elif [ ! -f "$PAI_DIR/bin/pai-sandbox.sh" ]; then
        record_check_failure "T1 sandbox wrapper (pai-sandbox.sh) missing"
    elif ! command -v bwrap &>/dev/null; then
        if [ "$(uname -s)" = "Linux" ]; then
            record_check_failure "T1 sandbox fail-open: bwrap absent (commands run unconfined)"
        else
            record_check_pass "T1 sandbox N/A on $(uname -s) (bwrap is Linux-only)"
        fi
    elif verify_sandbox >/dev/null 2>&1; then
        record_check_pass "T1 sandbox confinement verified ($SANDBOX_STATUS)"
    else
        record_check_failure "T1 sandbox degraded: ${SANDBOX_STATUS:-confinement probe failed}"
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

    # O5 consumer: the health timer must be SCHEDULED, not merely runnable — an
    # on-demand monitor nobody runs is the write-only-JSONL failure mode one
    # step removed.
    # Filesystem-based on purpose: user-unit enablement IS the wants/ symlink
    # (systemctl enable creates it), and file checks respect $HOME overrides so
    # the fixture tests exercise the same code path as a real host.
    if [ "$(uname -s)" != "Linux" ] || ! systemctl --user show-environment >/dev/null 2>&1; then
        record_check_pass "Health timer N/A (no systemd user session)"
    elif [ -f "$HOME/.config/systemd/user/pai-health.timer" ] \
        && [ -e "$HOME/.config/systemd/user/timers.target.wants/pai-health.timer" ]; then
        record_check_pass "Health timer scheduled (pai-health.timer enabled)"
    else
        record_check_failure "Health timer not scheduled — O5 consumer missing (re-run install, or: systemctl --user enable --now pai-health.timer)"
    fi

    if [ -f "$PAI_DIR/USER/SECURITY/PATTERNS.yaml" ]; then
        record_check_pass "Security policy (PATTERNS.yaml) installed"
        # Staleness fence: the installed policy is user-owned and seeded only when
        # absent, so template improvements never propagate on their own (this bit
        # us: an install ran for months without the curated reverse-shell adds).
        # The version line is the drift signal — Patterns.example.yaml bumps it
        # whenever patterns change; a customized install keeps its edits and merges.
        local template_policy="${REPO_DIR}/PAI/DOCUMENTATION/Security/Patterns.example.yaml"
        if [ -f "$template_policy" ]; then
            local installed_ver template_ver
            installed_ver="$(grep -m1 '^version:' "$PAI_DIR/USER/SECURITY/PATTERNS.yaml" 2>/dev/null | sed -E 's/^version:[[:space:]]*"?([^" ]*)"?.*/\1/')"
            template_ver="$(grep -m1 '^version:' "$template_policy" 2>/dev/null | sed -E 's/^version:[[:space:]]*"?([^" ]*)"?.*/\1/')"
            if [ -n "$template_ver" ] && [ "$installed_ver" = "$template_ver" ]; then
                record_check_pass "Security policy version current ($installed_ver)"
            else
                record_check_failure "Security policy STALE: installed version '${installed_ver:-none}' != template '${template_ver}' — merge new patterns from Patterns.example.yaml (or re-seed if uncustomized)"
            fi
        fi
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

    if [ -f "$PAI_DIR/.role" ]; then
        echo ""
        echo "  Host role: $(tr -d '[:space:]' < "$PAI_DIR/.role" 2>/dev/null)"
    fi

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
    verify_sandbox || true
    install_broker
    install_edge_tts
    install_renderer_service
    install_health_timer
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
