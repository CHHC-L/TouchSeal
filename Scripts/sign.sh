#!/bin/sh
# Signs the release binary so macOS will allow Touch ID-protected Keychain items.
#
# Usage:
#   Scripts/sign.sh "Developer ID Application: Your Name (TEAMID)"
#   Scripts/sign.sh "Apple Development: you@example.com (XXXXXXXXXX)"
#
# List the identities available on this Mac with:
#   security find-identity -v -p codesigning
#
# An ad-hoc signature will NOT work: macOS refuses to honour a
# keychain-access-groups entitlement on an ad-hoc signature and terminates the
# process. See "Code signing" in README.md.
set -eu

if [ $# -ne 1 ]; then
    echo "usage: $0 <code-signing-identity>" >&2
    echo >&2
    echo "available identities:" >&2
    security find-identity -v -p codesigning >&2
    exit 2
fi

identity="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
binary="$root/.build/release/touchseal"
template="$root/Resources/touchseal.entitlements"

if [ ! -x "$binary" ]; then
    echo "error: $binary not found. Run 'swift build -c release' first." >&2
    exit 1
fi

# The entitlement's access group must be prefixed with the signing identity's
# team ID, so it is derived from the identity rather than hard-coded.
team_id="$(printf '%s' "$identity" | sed -n 's/.*(\([A-Z0-9]*\))$/\1/p')"
if [ -z "$team_id" ]; then
    echo "error: could not read a team ID from \"$identity\"." >&2
    echo "       expected an identity ending in \"(TEAMID)\"." >&2
    exit 2
fi

entitlements="$(mktemp -t touchseal-entitlements)"
trap 'rm -f "$entitlements"' EXIT INT TERM
sed "s/TEAMID/$team_id/" "$template" >"$entitlements"

codesign --force --options runtime --timestamp \
    --sign "$identity" \
    --identifier "io.github.chhc-l.touchseal" \
    --entitlements "$entitlements" \
    "$binary"

echo "Signed $binary with team $team_id."
codesign --display --entitlements - "$binary"
