#!/usr/bin/env bash
set -euo pipefail

rm -f "$HOME/.local/bin/codex-skip-login"
rm -rf "$HOME/.local/share/codex-skip-login"
rm -rf "$HOME/Applications/Codex+国产模型免登.app"

echo "Removed Codex+国产模型免登. User Codex settings under ~/.codex were not deleted."
