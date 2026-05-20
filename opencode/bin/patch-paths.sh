#!/bin/bash
# Patch PULSE paths from ~/.claude/ to ~/.config/opencode/

cd "$(dirname "$0")"

echo "🔧 Patching PULSE paths..."

find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.sh" -o -name "*.toml" -o -name "*.plist" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.next/*" \
  -not -path "*/out/*" \
  -exec sed -i 's|${HOME}/.claude/|${HOME}/.config/opencode/|g' {} +

find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.sh" -o -name "*.toml" -o -name "*.plist" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.next/*" \
  -not -path "*/out/*" \
  -exec sed -i 's|~/.claude/|~/.config/opencode/|g' {} +

echo "✅ Paths patched"
