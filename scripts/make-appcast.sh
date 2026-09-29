#!/bin/bash
#
# Regenerates appcast.xml from the DMGs in build/ and signs each entry with
# the EdDSA key in this machine's keychain (created once by Sparkle's
# generate_keys; the public half lives in packaging/Info.plist).
#
#   ./scripts/make-appcast.sh
#
# This script builds and signs the feed, and stops there. Publishing belongs
# to the zones-web repository, which serves the site: hand it the artifacts as
# a GitHub Release (the closing message prints the command) and its deploy
# fetches them in, refusing to publish an incomplete set.
#
# They are served at, and these URLs are compiled into every shipped binary:
#   https://zones.pinyridgelabs.com/appcast.xml
#   https://zones.pinyridgelabs.com/Zones-<version>.dmg
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

DOWNLOAD_PREFIX="https://zones.pinyridgelabs.com/"

# `|| true`: with `set -e`, a missing .build/artifacts makes find fail and the
# assignment takes the script out before the line below can say what to do
# about it — which is the one moment that message exists for.
GENERATE_APPCAST="$(find .build/artifacts -type f -name generate_appcast 2>/dev/null | head -1 || true)"
if [[ -z "$GENERATE_APPCAST" ]]; then
    echo "generate_appcast not found — run 'swift build' once so SPM fetches Sparkle's tools" >&2
    exit 1
fi

shopt -s nullglob
DMGS=(build/Zones-*.dmg)
if [[ ${#DMGS[@]} -eq 0 ]]; then
    echo "no build/Zones-*.dmg to describe — run ./scripts/release.sh first" >&2
    exit 1
fi

# Release notes ride beside their DMG: generate_appcast embeds an .html that
# shares an archive's basename.
for dmg in "${DMGS[@]}"; do
    base="$(basename "$dmg" .dmg)"
    if [[ -f "packaging/release-notes/$base.html" ]]; then
        cp "packaging/release-notes/$base.html" "build/$base.html"
    else
        echo "    note: no release notes at packaging/release-notes/$base.html — $base ships without notes"
    fi
done

echo "==> signing appcast for: ${DMGS[*]}"
"$GENERATE_APPCAST" build \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    -o appcast.xml

shopt -s nullglob
STAGED_DMGS=(build/Zones-*.dmg)
if [[ ${#STAGED_DMGS[@]} -eq 0 ]]; then
    echo "no build/Zones-*.dmg survived appcast generation — nothing to stage" >&2
    exit 1
fi

NEWEST_DMG="$(ls -t "${STAGED_DMGS[@]}" | head -1)"
echo "    newest image: ${NEWEST_DMG##*/}"

NEWEST_VERSION="$(basename "$NEWEST_DMG" .dmg)"
NEWEST_VERSION="${NEWEST_VERSION#Zones-}"
FEED_NEWEST="$(grep -oE '<title>[0-9]+\.[0-9]+\.[0-9]+</title>' appcast.xml \
    | head -1 | sed -E 's/<\/?title>//g')"
if [[ "$FEED_NEWEST" != "$NEWEST_VERSION" ]]; then
    echo "the feed's newest item is $FEED_NEWEST but the release is $NEWEST_VERSION" >&2
    echo "(a DMG that is already mounted fails to unarchive and is silently left out —" >&2
    echo " check the output above for 'Resource busy', then: hdiutil detach each one)" >&2
    exit 1
fi
echo "    feed's newest item: $FEED_NEWEST"

echo
echo "built appcast.xml and build/ artifacts — publish them with:"

RELEASE_ASSETS="appcast.xml build/Zones-*.dmg"
DELTA_FILES=(build/*.delta)
if (( ${#DELTA_FILES[@]} > 0 )); then
    RELEASE_ASSETS="$RELEASE_ASSETS build/*.delta"
fi

echo "  gh release create v$NEWEST_VERSION $RELEASE_ASSETS \\"
echo "      --repo sean-rowe/Zones --title \"$NEWEST_VERSION\""
echo
echo "then deploy the site from the zones-web repository."
