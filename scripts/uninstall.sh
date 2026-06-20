#!/usr/bin/env bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.huangama.codex-skip-login.adapter.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl unsetenv CODEX_SWITCH_API_KEY >/dev/null 2>&1 || true
rm -f "$PLIST" "$HOME/.local/bin/codex-skip-login"
rm -rf "$HOME/.local/share/codex-skip-login" "$HOME/Applications/Codex+国产模型免登.app"
echo "Removed app, CLI, and protocol adapter service. ~/.codex was preserved."
