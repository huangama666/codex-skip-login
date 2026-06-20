#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$HOME/Applications/Codex+国产模型免登.app"
ZIP_PATH="$DIST_DIR/Codex-Skip-Login-macOS.zip"

"$ROOT_DIR/scripts/package-app.sh" >/dev/null

mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "$ZIP_PATH"
