#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

dest=${1:-$PWD/bin/Converter.app}
target=${2:-$(uname -m)}
work=$(mktemp -d "$(dirname "$dest")/.converter-build.XXXXXX")
trap 'rm -rf "$work"' EXIT
app="$work/Converter.app"
iconset="$work/Converter.iconset"
icon="$work/Converter.png"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"
src=internal/payout/desktop/ui
cp "$src/Info.plist" "$app/Contents/Info.plist"
swift scripts/generate-converter-icon.swift "$icon"
for size in 16 32 128 256 512; do
  doubled=$((size * 2))
  sips -z "$size" "$size" "$icon" \
    --out "$iconset/icon_${size}x${size}.png" >/dev/null
  sips -z "$doubled" "$doubled" "$icon" \
    --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Converter.icns"

build() {
  swiftc -target "$1-apple-macos12.0" -O -parse-as-library "$src"/*.swift -o "$2"
}
binary="$app/Contents/MacOS/Converter"
case $target in
  universal)
    build arm64 "$work/arm64"
    build x86_64 "$work/x86_64"
    lipo -create "$work/arm64" "$work/x86_64" -output "$binary"
    ;;
  arm64|x86_64) build "$target" "$binary" ;;
  *) exit 2 ;;
esac
codesign --force --sign - "$app"
if [ -d "$dest" ]; then
  mv "$dest" "$work/previous"
fi
if ! mv "$app" "$dest"; then
  if [ -d "$work/previous" ]; then
    mv "$work/previous" "$dest"
  fi
  exit 1
fi
