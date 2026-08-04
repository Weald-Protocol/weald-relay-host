#!/usr/bin/env bash
# Build, sign, notarize, staple and package Weald Relay Host as a .dmg.
#
# The .app that scripts/build-app.sh produces is ad-hoc signed, which is fine
# on the machine that built it and useless to anybody else: Gatekeeper blocks
# it. A download needs Developer ID signing, a hardened runtime and a stapled
# notarization ticket, so this script rebuilds the bundle with those and wraps
# it in a signed, notarized disk image.
#
# Requires:
#   - "Developer ID Application: Veep LLC (NWR2UZ4V67)" in the login keychain
#   - a notarytool keychain profile named "weald-notary"
#
# Usage: ./scripts/build-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
IDENTITY="Developer ID Application: Veep LLC (NWR2UZ4V67)"
NOTARY_PROFILE="weald-notary"
APP="$ROOT/build/Weald Relay Host.app"
STAGING="$ROOT/build/dmg-staging"
ZIP="$ROOT/build/WealdRelayHost-notarize.zip"
DMG="$ROOT/build/WealdRelayHost.dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"

echo "==> Building the bundle (v$VERSION)"
./scripts/build-app.sh release

echo "==> Signing with Developer ID and a hardened runtime"
# No entitlements: the app is unsandboxed on purpose, because its entire job is
# to drive the docker CLI on this Mac.
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Notarizing the app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
spctl -a -vvv --type execute "$APP"

echo "==> Building the disk image"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Weald Relay Host" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

echo "==> Signing and notarizing the disk image"
codesign --force --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -vvv --type open --context context:primary-signature "$DMG"

echo ""
echo "Done: $DMG (v$VERSION)"
