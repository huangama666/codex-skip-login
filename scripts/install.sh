#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$HOME/.local/share/codex-skip-login"
BIN_DIR="$HOME/.local/bin"
OPEN_APP=1

for arg in "$@"; do
  case "$arg" in
    --no-open)
      OPEN_APP=0
      ;;
    -h|--help)
      echo "Usage: ./scripts/install.sh [--no-open]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: ./scripts/install.sh [--no-open]" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$INSTALL_DIR" "$BIN_DIR"
rsync -a --delete \
  --exclude '.git' \
  --exclude '.DS_Store' \
  --exclude 'dist' \
  "$ROOT_DIR/" "$INSTALL_DIR/"

cat > "$BIN_DIR/codex-skip-login" <<'SH'
#!/usr/bin/env sh
exec /usr/bin/env python3 "$HOME/.local/share/codex-skip-login/src/codex_switch/cli.py" "$@"
SH
chmod 755 "$BIN_DIR/codex-skip-login"

"$ROOT_DIR/scripts/package-app.sh"

echo "Installed codex-skip-login to $BIN_DIR/codex-skip-login"
echo "Installed Codex+国产模型免登.app to $HOME/Applications/Codex+国产模型免登.app"
echo "Tip: add ~/.local/bin to PATH if codex-skip-login is not found in your shell."

if [[ "$OPEN_APP" == "1" ]]; then
  open "$HOME/Applications/Codex+国产模型免登.app"
fi
