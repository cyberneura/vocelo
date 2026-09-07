#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_ID:?Set DEVELOPER_ID to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
ARCHS=universal ./scripts/build-app.sh
app="$PWD/dist/Vocelo.app"
codesign --force --sign "$DEVELOPER_ID" --timestamp --options runtime \
    --entitlements Vocelo.entitlements "$app"
codesign --verify --strict --verbose=2 "$app"
ditto -c -k --keepParent "$app" dist/Vocelo-notarization.zip
xcrun notarytool submit dist/Vocelo-notarization.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --keepParent "$app" dist/Vocelo.zip
printf 'Signed, notarized release: %s/dist/Vocelo.zip\n' "$PWD"
