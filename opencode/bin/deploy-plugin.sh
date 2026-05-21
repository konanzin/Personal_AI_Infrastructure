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

# Deploy library
log "Deploying pai-hooks.lib.js..."
cp -f "${REPO_DIR}/opencode/plugins/lib/pai-hooks.lib.js" "$PLUGINS_DIR/lib/"
success "pai-hooks.lib.js deployed"

# Verify
if [ -f "$PLUGINS_DIR/pai-hooks.js" ] && [ -f "$PLUGINS_DIR/lib/pai-hooks.lib.js" ]; then
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
