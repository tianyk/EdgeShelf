#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/EdgeShelf.app"
TMP="$ROOT/build/.tmp"
SDK="$(xcrun --show-sdk-path)"
UNIVERSAL="${UNIVERSAL:-0}"

rm -rf "$APP" "$TMP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TMP"

compile() {
  local arch="$1"
  local out="$2"
  echo "Compiling ${arch}…"
  xcrun swiftc \
    -O \
    -swift-version 5 \
    -target "${arch}-apple-macos13.0" \
    -sdk "$SDK" \
    -framework AppKit \
    -framework QuickLookThumbnailing \
    -framework UniformTypeIdentifiers \
    "$ROOT"/Sources/*.swift \
    -o "$out"
}

if [[ "$UNIVERSAL" == "1" ]]; then
  compile arm64 "$TMP/EdgeShelf-arm64"
  compile x86_64 "$TMP/EdgeShelf-x86_64"
  lipo -create "$TMP/EdgeShelf-arm64" "$TMP/EdgeShelf-x86_64" \
    -output "$APP/Contents/MacOS/EdgeShelf"
  lipo -info "$APP/Contents/MacOS/EdgeShelf"
else
  compile "$(uname -m)" "$APP/Contents/MacOS/EdgeShelf"
fi

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --sign - "$APP" >/dev/null
rm -rf "$TMP"

echo "Built: $APP"
echo "Run with: open \"$APP\""
echo "Self-test: \"$APP/Contents/MacOS/EdgeShelf\" --self-test"
