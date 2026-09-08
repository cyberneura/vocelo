#!/bin/bash
# Local equivalent of the release workflow: universal build, Developer ID signing,
# notarization of both the app and the dmg, and dist/Vocelo_<version>_universal.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_ID:?Set DEVELOPER_ID to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool Keychain profile}"
version=$(tr -d '[:space:]' < VERSION)
app="$PWD/dist/Vocelo.app"
dmg="$PWD/dist/Vocelo_${version}_universal.dmg"
ARCHS=universal SIGN_IDENTITY="$DEVELOPER_ID" ./scripts/build-app.sh
ditto -c -k --keepParent "$app" dist/Vocelo-notarization.zip
xcrun notarytool submit dist/Vocelo-notarization.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
# Built from the stapled app, so the copy a user drags out carries the ticket. The
# dmg is then notarized in its own right.
./scripts/make-dmg.sh --sign "$DEVELOPER_ID"
xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$dmg"
spctl --assess --type open --context context:primary-signature -v "$dmg"
printf 'Signed, notarized release: %s\n' "$dmg"
