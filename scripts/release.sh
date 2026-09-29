#!/bin/bash
#
# One command from checkout to notarized, stapled, distributable DMG.
#
#   ./scripts/release.sh --version 1.0.0
#
# Stages: doctor gate → release build → disk image → notarize + staple.
# The doctor runs first so every gap surfaces before any minutes-long build
# or upload, not in the middle of one.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# No default: a release built under a placeholder version is notarised, signed
# and indistinguishable from a real one until someone reads the filename.
VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            if [[ $# -lt 2 ]]; then
                echo "--version needs a value (X.Y.Z)" >&2
                exit 1
            fi
            VERSION="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

# A malformed version poisons the DMG name, the bundle version and the
# notarization record all at once — stop before any stage runs.
if [[ -z "$VERSION" ]]; then
    echo "release.sh requires --version X.Y.Z" >&2
    exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "version must look like X.Y.Z, got '$VERSION'" >&2
    exit 1
fi

./scripts/release-doctor.sh || {
    echo >&2
    echo "release aborted — close the gaps above, then rerun." >&2
    exit 1
}

./scripts/build-app.sh --release --version "$VERSION"
./scripts/make-dmg.sh --version "$VERSION"
./scripts/notarize.sh "build/Zones-$VERSION.dmg"
# After stapling, so the feed describes the exact bytes users will download.
./scripts/make-appcast.sh

echo
echo "release complete: build/Zones-$VERSION.dmg (notarized and stapled)"
echo "publish: commit appcast.xml, then run the gh release create command that"
echo "         make-appcast.sh printed above. It is built from what this release"
echo "         actually produced, so it names the delta files only when there"
echo "         are any — restating it here is how the two drift apart."
echo "  then deploy from the zones-web repository."
