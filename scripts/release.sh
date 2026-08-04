#!/usr/bin/env bash
# Cut a release of Weald Relay Host: version, build, notarize, publish, verify.
#
# One command, because the website links
# releases/latest/download/WealdRelayHost.dmg and nothing else. That URL is only
# correct if the newest release always carries an asset of exactly that name, so
# the asset name, the notarization and the release are one step rather than three
# a person can do two of.
#
# Requires:
#   - "Developer ID Application: Veep LLC (NWR2UZ4V67)" in the login keychain
#   - a notarytool keychain profile named "weald-notary"
#   - gh, authenticated for Weald-Protocol
#
# Usage:
#   ./scripts/release.sh            # bump the patch version
#   ./scripts/release.sh 0.4.0      # release exactly this version
#   ./scripts/release.sh --same     # re-release the current version (retag)
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
PLIST="$ROOT/Resources/Info.plist"
DMG="$ROOT/build/WealdRelayHost.dmg"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }
CURRENT="$(plist CFBundleShortVersionString)"
BUILD_NUMBER="$(plist CFBundleVersion)"

case "${1:-}" in
  "")
    IFS=. read -r major minor patch <<<"$CURRENT"
    VERSION="$major.$minor.$((patch + 1))"
    ;;
  --same) VERSION="$CURRENT" ;;
  *)
    [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
      echo "not a version: $1" >&2
      exit 1
    }
    VERSION="$1"
    ;;
esac

echo "==> Releasing v$VERSION (was v$CURRENT)"

# A dirty tree is refused rather than committed for you: this script pushes a tag
# that a stranger is invited to rebuild from, and a tag over unreviewed work is a
# published claim about source nobody read.
if [ -n "$(git status --porcelain)" ]; then
  echo "working tree is dirty, commit or discard first" >&2
  git status --short >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
  echo "tag v$VERSION already exists" >&2
  exit 1
fi
if gh release view "v$VERSION" >/dev/null 2>&1; then
  echo "release v$VERSION already exists" >&2
  exit 1
fi

if [ "$VERSION" != "$CURRENT" ]; then
  echo "==> Stamping the bundle"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD_NUMBER + 1))" "$PLIST"
  # The README carries the version in its badge line, and a download page whose
  # own source disagrees with the file it hands you is the cheapest kind of lie.
  /usr/bin/sed -i '' "s/· v$CURRENT<\/sub>/· v$VERSION<\/sub>/" "$ROOT/README.md"
  git add "$PLIST" "$ROOT/README.md"
  git commit -q -m "Release v$VERSION"
  git push -q origin HEAD
fi

echo "==> Building, signing and notarizing"
./scripts/build-dmg.sh

echo "==> Publishing the release"
NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
{
  echo "A status bar app that runs your own Weald relay on this Mac. Start the"
  echo "relay, copy the URL, paste it into a Weald project."
  echo
  echo "\`WealdRelayHost.dmg\` is universal, macOS 14 or later, signed by Veep LLC"
  echo "(NWR2UZ4V67) and notarized by Apple, so it opens without a Gatekeeper"
  echo "warning. A Docker engine is the only prerequisite. Install steps, the"
  echo "panel reference and troubleshooting are in the README."
  echo
  echo "Built from this tag by \`./scripts/release.sh\`."
} >"$NOTES"
gh release create "v$VERSION" "$DMG" \
  --title "Weald Relay Host v$VERSION" \
  --notes-file "$NOTES"

echo "==> Verifying the download the website links"
URL="https://github.com/Weald-Protocol/weald-relay-host/releases/latest/download/WealdRelayHost.dmg"
CODE="$(curl -sIL -o /dev/null -w '%{http_code}' "$URL")"
[ "$CODE" = "200" ] || {
  echo "the website's download URL returned $CODE" >&2
  exit 1
}

echo ""
echo "Released v$VERSION. $URL serves it."
