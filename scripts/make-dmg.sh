#!/bin/bash
#
# Packages build/Zones.app into a distributable disk image.
#
#   ./scripts/make-dmg.sh                    # uses build/Zones.app as-is
#   ./scripts/make-dmg.sh --version 1.0.0
#
# Output: build/Zones-<version>.dmg
#
# Uses hdiutil only — no Homebrew dependency (create-dmg is not required).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

APP="build/Zones.app"
if [[ ! -d "$APP" ]]; then
    echo "missing $APP — run ./scripts/build-app.sh --release first" >&2
    exit 1
fi

# Fall back to the version baked into the bundle.
if [[ -z "$VERSION" ]]; then
    VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
fi

STAGING="build/dmg-staging"
DMG="build/Zones-$VERSION.dmg"

echo "==> staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
# The Applications symlink is what makes drag-to-install obvious.
ln -s /Applications "$STAGING/Applications"

echo "==> building $DMG"
hdiutil create \
    -volname "Zones $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG" >/dev/null

rm -rf "$STAGING"

# Signing the DMG itself means Gatekeeper can verify it before mounting.
# Prefer Developer ID; fall back to whatever signed the app.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
if [[ -n "$IDENTITY" ]]; then
    echo "==> signing DMG as: $IDENTITY"
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    codesign --verify --verbose=2 "$DMG"
else
    echo "    note: no Developer ID Application certificate found — DMG left unsigned."
    echo "          Gatekeeper will reject it on other Macs until you sign and notarize."
fi

echo
echo "built $DMG ($(du -h "$DMG" | cut -f1))"
echo "next: ./scripts/notarize.sh $DMG"
