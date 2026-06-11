#!/usr/bin/env bash
# Local verification for the Flutter app: static analysis + tests.
# Usage: scripts/check.sh   (from apps/flutter, or anywhere — it self-locates)
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test"
flutter test

echo "==> OK"
