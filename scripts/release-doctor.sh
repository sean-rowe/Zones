#!/bin/bash
#
# Is this machine ready to cut a notarized release?
#
#   ./scripts/release-doctor.sh
#
# Reports every gap at once instead of letting the pipeline die mid-way, and
# says exactly how to close each one. Exit 0 when a notarized release can be
# cut from here; exit 1 when anything is missing.
#
set -uo pipefail   # deliberately not -e: the job is to keep going and report

PROFILE="${NOTARY_PROFILE:-tack}"
missing=0

say_ok()   { printf '  ✓ %s\n' "$1"; }
say_gap()  { printf '  ✗ %s\n' "$1"; missing=$((missing + 1)); }

echo "Zones release doctor"
echo "===================="

# ---- Xcode command line tools ------------------------------------------------
if xcrun --find notarytool >/dev/null 2>&1; then
    say_ok "Xcode command line tools with notarytool"
else
    say_gap "notarytool not found — install Xcode or the Command Line Tools (xcode-select --install)"
fi

# ---- Developer ID Application identity --------------------------------------
# Distribution outside the App Store needs this exact certificate type; an
# Apple Development certificate signs builds that only run on enrolled machines.
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)"
if [[ -n "$DEV_ID" ]]; then
    say_ok "Developer ID Application identity: $DEV_ID"
else
    say_gap "No Developer ID Application certificate installed"
    cat <<'EOF'
      Create one (requires a paid Apple Developer membership):
        Xcode > Settings > Accounts > (your team) > Manage Certificates
        > + > Developer ID Application
      or on the web: developer.apple.com > Certificates > + > Developer ID Application.
EOF
fi

# ---- Team ID, for guidance below --------------------------------------------
TEAM_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" \
    | sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p' | head -1 || true)"
if [[ -z "$TEAM_ID" ]]; then
    TEAM_ID="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -nE 's/.*\(([A-Z0-9]{10})\)".*/\1/p' | head -1 || true)"
fi
TEAM_ID="${TEAM_ID:-<your team id>}"

# ---- Notarytool credentials --------------------------------------------------
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    say_ok "notarytool credentials stored under profile \"$PROFILE\""
else
    say_gap "No notarytool credentials under profile \"$PROFILE\""
    cat <<EOF
      Store them once (interactive; the password is an app-specific password
      from appleid.apple.com > Sign-In and Security):
        xcrun notarytool store-credentials "$PROFILE" \\
            --apple-id "<your Apple ID>" \\
            --team-id "$TEAM_ID" \\
            --password "<app-specific password>"
EOF
fi

echo
if [[ "$missing" -eq 0 ]]; then
    echo "Ready: ./scripts/release.sh --version <X.Y.Z> will produce a notarized DMG."
    exit 0
else
    echo "$missing gap(s) above must be closed before a notarized release."
    exit 1
fi
