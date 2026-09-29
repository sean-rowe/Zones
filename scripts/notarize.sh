#!/bin/bash
#
# Submits a DMG to Apple for notarization, waits for the verdict, and staples
# the ticket so the app opens on machines that have never seen it before.
#
#   ./scripts/notarize.sh build/Zones-1.0.0.dmg
#
# One-time setup (interactive — run it yourself, it prompts for credentials):
# see ./scripts/release-doctor.sh, which prints the exact store-credentials
# command with your own team id filled in.
#
set -euo pipefail

PROFILE="${NOTARY_PROFILE:-tack}"
TARGET="${1:-}"

if [[ -z "$TARGET" || ! -f "$TARGET" ]]; then
    echo "usage: $0 <path-to-dmg-or-zip>" >&2
    exit 1
fi

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    TEAM_ID="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" \
        | sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p' | head -1 || true)"
    if [[ -z "$TEAM_ID" ]]; then
        TEAM_ID="$(security find-identity -v -p codesigning 2>/dev/null \
            | sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p' | head -1 || true)"
    fi
    TEAM_ID="${TEAM_ID:-<your team id>}"
    cat >&2 <<EOF
No notarytool credentials found under profile "$PROFILE".

Run this once (it is interactive, so run it yourself):

  xcrun notarytool store-credentials "$PROFILE" \\
      --apple-id "<your Apple ID>" \\
      --team-id "$TEAM_ID" \\
      --password "<app-specific password>"

Generate the app-specific password at appleid.apple.com > Sign-In and Security.
EOF
    exit 1
fi

echo "==> submitting $TARGET (this waits for Apple; typically a few minutes)"
xcrun notarytool submit "$TARGET" \
    --keychain-profile "$PROFILE" \
    --wait

echo "==> stapling ticket"
xcrun stapler staple "$TARGET"

echo "==> verifying"
xcrun stapler validate "$TARGET"
spctl --assess --type open --context context:primary-signature -vv "$TARGET" || true

echo
echo "notarized and stapled: $TARGET"
echo "This is the file to put on the website."
