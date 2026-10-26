#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/EdgeShelf.app"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling (${ARCH})…"
xcrun swiftc \
  -O \
  -swift-version 5 \
  -target "${ARCH}-apple-macos13.0" \
  -sdk "$SDK" \
  -framework AppKit \
  -framework QuickLookThumbnailing \
  -framework UniformTypeIdentifiers \
  "$ROOT"/Sources/*.swift \
  -o "$APP/Contents/MacOS/EdgeShelf"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP" >/dev/null

echo "Built: $APP"
echo "Run with: open \"$APP\""
echo "Self-test: \"$APP/Contents/MacOS/EdgeShelf\" --self-test"
