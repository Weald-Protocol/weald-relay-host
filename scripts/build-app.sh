#!/usr/bin/env bash
# Build Weald Relay Host.app into build/.
#
# SwiftPM produces a bare executable; a status bar app needs a bundle with
# LSUIElement set, so the bundle is assembled here rather than by Xcode. Ad-hoc
# signing is enough to run it locally.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/Weald Relay Host.app"
CONFIG="${1:-release}"

swift build -c "$CONFIG" --arch arm64 --arch x86_64
BIN="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)/WealdRelayHost"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WealdRelayHost"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --sign - "$APP"

echo "built: $APP"
