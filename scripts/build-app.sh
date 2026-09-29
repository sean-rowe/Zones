#!/bin/bash
#
# Builds Zones.app from the SPM executable.
#
#   ./scripts/build-app.sh                 # debug build, ad-hoc signed
#   ./scripts/build-app.sh --release       # release build, ad-hoc signed
#   ./scripts/build-app.sh --release --sign "Developer ID Application: NAME (TEAMID)"
#
# Output: build/Zones.app
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG="debug"
SIGN_IDENTITY=""           # empty = auto-detect; "-" means ad-hoc
SHORT_VERSION="0.1.0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release) CONFIG="release"; shift ;;
        --sign)    SIGN_IDENTITY="$2"; shift 2 ;;
        --version) SHORT_VERSION="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

# Monotonic build number from commit count; falls back to 1 outside a git checkout.
BUILD_VERSION="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

# Auto-detect the best available identity. This matters beyond release builds:
# macOS keys the Accessibility grant to the signature, so an ad-hoc signature
# is revoked on every rebuild and re-prompts. A real certificate keeps the
# grant stable across rebuilds.
if [[ -z "$SIGN_IDENTITY" ]]; then
    for kind in "Developer ID Application" "Apple Development"; do
        # `|| true` matters: grep exits 1 when a certificate type is absent,
        # which under `set -e -o pipefail` would abort the whole script.
        found="$(security find-identity -v -p codesigning 2>/dev/null \
            | grep "$kind" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
        if [[ -n "$found" ]]; then
            SIGN_IDENTITY="$found"
            break
        fi
    done
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
    echo "==> auto-selected signing identity: $SIGN_IDENTITY"
fi

APP_DIR="$REPO_ROOT/build/Zones.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

# Universal, always. Without the --arch flags SwiftPM builds only for the host.
ARCHS=(--arch arm64 --arch x86_64)
echo "==> swift build -c $CONFIG ${ARCHS[*]}"
swift build -c "$CONFIG" --product Zones "${ARCHS[@]}"

BINARY="$(swift build -c "$CONFIG" --product Zones "${ARCHS[@]}" --show-bin-path)/Zones"
if [[ ! -x "$BINARY" ]]; then
    echo "build failed: no executable at $BINARY" >&2
    exit 1
fi

# Checked, not assumed: a missing slice is invisible until an Apple silicon
# user reports the app will not open natively.
for slice in arm64 x86_64; do
    if ! lipo -info "$BINARY" | grep -q "$slice"; then
        echo "build failed: $BINARY has no $slice slice ($(lipo -info "$BINARY"))" >&2
        exit 1
    fi
done
echo "==> universal: $(lipo -info "$BINARY" | sed 's/.*are: //')"

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES"
cp "$BINARY" "$MACOS_DIR/Zones"

# Sparkle rides inside the bundle. The SPM build links it against an absolute
# .build path that exists on no other machine, so the bundle carries its own
# copy and the executable learns to look beside itself.
FRAMEWORKS="$CONTENTS/Frameworks"
mkdir -p "$FRAMEWORKS"
cp -R "$(dirname "$BINARY")/Sparkle.framework" "$FRAMEWORKS/"
# Swallowing every failure here also swallowed the one that matters: without
# this rpath the installed app cannot find Sparkle and dies at launch on any
# machine but this one. Added only when absent, and a failure to add it stops
# the build.
if ! otool -l "$MACOS_DIR/Zones" | grep -Fq "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/Zones"
fi

sed -e "s/__SHORT_VERSION__/$SHORT_VERSION/" \
    -e "s/__BUILD_VERSION__/$BUILD_VERSION/" \
    packaging/Info.plist > "$CONTENTS/Info.plist"

# Debug builds carry their own identity. macOS keys permission grants by
# bundle id, and two copies sharing one id fight over a single TCC entry —
# every dev-build launch orphaned the installed app's Accessibility grant,
# which re-prompted the user for a permission they had already given.
if [[ "$CONFIG" == "debug" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.pinyridgelabs.Zones.dev" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Zones Dev" "$CONTENTS/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Zones Dev" "$CONTENTS/Info.plist"
fi

if [[ -f packaging/AppIcon.icns ]]; then
    cp packaging/AppIcon.icns "$RESOURCES/AppIcon.icns"
else
    # Without an icon the app still runs; the Finder just shows a generic one.
    echo "    note: packaging/AppIcon.icns missing — bundling without an icon"
fi

# Hardened runtime is required for notarization.
echo "==> codesign (identity: $SIGN_IDENTITY)"
CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    # Ad-hoc signatures cannot carry a secure timestamp.
    CODESIGN_ARGS=(--force --sign "-")
fi

# Notarization requires every piece of nested code to carry our signature,
# deepest first: Sparkle's XPC services and helpers, then the framework,
# then the app that contains them.
SPARKLE_B="$FRAMEWORKS/Sparkle.framework/Versions/B"
for nested in "$SPARKLE_B/XPCServices/"*.xpc \
              "$SPARKLE_B/Autoupdate" \
              "$SPARKLE_B/Updater.app" \
              "$FRAMEWORKS/Sparkle.framework"; do
    [[ -e "$nested" ]] && codesign "${CODESIGN_ARGS[@]}" "$nested"
done

codesign "${CODESIGN_ARGS[@]}" "$APP_DIR"
codesign --verify --verbose=2 "$APP_DIR"

echo
echo "built $APP_DIR  ($SHORT_VERSION build $BUILD_VERSION, $CONFIG)"
echo "run it with: open '$APP_DIR'"
