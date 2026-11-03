#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/build/AppIcon.iconset"
OUTPUT="$ROOT/Resources/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

mkdir -p "$ROOT/build/icon-renderer"
cp "$ROOT/Tools/AppIconRenderer.swift" "$ROOT/build/icon-renderer/main.swift"
swiftc "$ROOT/Sources/AppIcons.swift" "$ROOT/build/icon-renderer/main.swift" -o "$ROOT/build/icon-renderer/render"
"$ROOT/build/icon-renderer/render" "$ICONSET"
mv "$ICONSET.icns" "$OUTPUT"
rm -rf "$ICONSET"

echo "Wrote $OUTPUT"
