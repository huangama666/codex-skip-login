#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$HOME/Applications"
APP_PATH="$APP_DIR/Codex+国产模型免登.app"
BUILD_DIR="$(mktemp -d)"
BUILD_APP="$BUILD_DIR/Codex+国产模型免登.app"
trap 'rm -rf "$BUILD_DIR"' EXIT

SWIFTC="$(xcrun --find swiftc)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources" "$APP_DIR"
cp "$ROOT_DIR/app/Info.plist" "$BUILD_APP/Contents/Info.plist"
cp "$ROOT_DIR/assets/app-icon.icns" "$BUILD_APP/Contents/Resources/app-icon.icns"
cp "$ROOT_DIR/src/codex_switch/cli.py" "$BUILD_APP/Contents/Resources/codex-skip-login"
chmod 755 "$BUILD_APP/Contents/Resources/codex-skip-login"

CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache" \
SWIFT_MODULECACHE_PATH="$BUILD_DIR/swift-cache" \
"$SWIFTC" -parse-as-library -O -target "$(uname -m)-apple-macos13.0" \
  -sdk "$SDK_PATH" -framework SwiftUI -framework AppKit \
  "$ROOT_DIR/app/CodexSkipLoginApp.swift" \
  -o "$BUILD_APP/Contents/MacOS/Codex+国产模型免登"

codesign --force --deep --sign - "$BUILD_APP" >/dev/null
rm -rf "$APP_PATH"
ditto "$BUILD_APP" "$APP_PATH"
echo "$APP_PATH"
