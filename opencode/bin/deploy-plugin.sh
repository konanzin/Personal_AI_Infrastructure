#!/bin/bash
# ═══════════════════════════════════════════════════════════
#  PAI Plugin Deploy — Sync repo to ~/.config/opencode/plugins/
#  Usage: ./deploy-plugin.sh [--restart]
# ═══════════════════════════════════════════════════════════

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGINS_DIR="${HOME}/.config/opencode/plugins"
PAI_DIR="${HOME}/.config/opencode/PAI"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

log() { echo -e "${BLUE}[DEPLOY]${RESET} $1"; }
success() { echo -e "${GREEN}[OK]${RESET} $1"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $1"; }

# Check opencode is installed
if ! command -v opencode &>/dev/null; then
    warn "opencode not found in PATH"
fi

# Create directories
mkdir -p "$PLUGINS_DIR/lib"

# Deploy main plugin
log "Deploying pai-hooks.js..."
cp -f "${REPO_DIR}/opencode/plugins/pai-hooks.js" "$PLUGINS_DIR/"
success "pai-hooks.js deployed"

# Deploy ALL libraries (pai-hooks.js imports pai-hooks.lib.js AND
# mode-classifier.lib.js; a stale lib missing a newly-imported symbol
# breaks the whole plugin load — including the security floor)
log "Deploying plugin libraries (lib/*.js)..."
cp -f "${REPO_DIR}/opencode/plugins/lib/"*.js "$PLUGINS_DIR/lib/"
success "plugin libraries deployed"

# Deploy the sandbox wrapper the plugin invokes at runtime
if [ -f "${REPO_DIR}/opencode/bin/pai-sandbox.sh" ]; then
    log "Deploying pai-sandbox.sh..."
    mkdir -p "$PAI_DIR/bin"
    cp -f "${REPO_DIR}/opencode/bin/pai-sandbox.sh" "$PAI_DIR/bin/"
    chmod +x "$PAI_DIR/bin/pai-sandbox.sh"
    success "pai-sandbox.sh deployed"
fi

# Deploy the escape-hatch token to a PATH dir so opencode's permission
# matcher sees it as a real command_name (env-var prefixes can't be gated).
if [ -f "${REPO_DIR}/opencode/bin/pai-nosandbox" ]; then
    log "Deploying pai-nosandbox to ~/.local/bin..."
    mkdir -p "${HOME}/.local/bin"
    cp -f "${REPO_DIR}/opencode/bin/pai-nosandbox" "${HOME}/.local/bin/"
    chmod +x "${HOME}/.local/bin/pai-nosandbox"
    command -v pai-nosandbox >/dev/null 2>&1 \
        && success "pai-nosandbox deployed (on PATH)" \
        || warn "pai-nosandbox deployed but ~/.local/bin is not on PATH — inline escape won't resolve"
fi

# Verify: every lib the repo ships must exist installed
verify_ok=1
[ -f "$PLUGINS_DIR/pai-hooks.js" ] || verify_ok=0
for lib in "${REPO_DIR}/opencode/plugins/lib/"*.js; do
    [ -f "$PLUGINS_DIR/lib/$(basename "$lib")" ] || verify_ok=0
done
if [ "$verify_ok" = "1" ]; then
    success "Plugin files verified"
else
    echo "ERROR: Plugin files missing after deploy"
    exit 1
fi

# Check for stale root-level lib
if [ -f "$PLUGINS_DIR/pai-hooks.lib.js" ]; then
    warn "Removing stale pai-hooks.lib.js from plugins root (should be in lib/)"
    rm -f "$PLUGINS_DIR/pai-hooks.lib.js"
fi

# Count handlers
HANDLER_COUNT=$(grep -c '".*": async' "$PLUGINS_DIR/pai-hooks.js")
success "Plugin has $HANDLER_COUNT event handlers"

# Show version
VERSION=$(grep "PLUGIN_VERSION" "$PLUGINS_DIR/pai-hooks.js" | grep -o "'[0-9.]*'" | tr -d "'")
success "Plugin version: $VERSION"

# Optional restart
if [ "${1:-}" = "--restart" ]; then
    log "Restarting opencode..."
    # Kill any running opencode processes
    pkill -f "opencode" && sleep 2 || true
    success "opencode restarted"
fi

log "Deploy complete. Plugin is now active."
