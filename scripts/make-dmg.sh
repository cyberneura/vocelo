#!/bin/bash
# Puts dist/Vocelo.app into dist/Vocelo_<version>_universal.dmg.
# Run scripts/build-app.sh first. Separate from it so notarization can happen in
# between: the ticket is stapled to the .app, and the dmg has to be built from the
# stapled copy for the app inside it to carry one.
set -euo pipefail
cd "$(dirname "$0")/.."
identity=""
if [[ "${1:-}" == "--sign" ]]; then
    identity="${2:?--sign needs an identity}"
    shift 2
fi
if [[ $# -gt 0 ]]; then
    echo "Usage: scripts/make-dmg.sh [--sign <identity>]" >&2
    exit 1
fi
version=$(tr -d '[:space:]' < VERSION)
app="$PWD/dist/Vocelo.app"
dmg="$PWD/dist/Vocelo_${version}_universal.dmg"
if [[ ! -d "$app" ]]; then
    echo "$app does not exist; run scripts/build-app.sh first" >&2
    exit 1
fi
# The version in the file name has to be the version in the bundle, or the download
# and what it installs disagree.
built_version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
if [[ "$built_version" != "$version" ]]; then
    echo "$app is version $built_version but VERSION says $version; rebuild it" >&2
    exit 1
fi
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
cp -R "$app" "$staging/"
# The Applications symlink is what makes the window a drag-and-drop install.
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -volname Vocelo -srcfolder "$staging" -ov -format UDZO "$dmg"
# Signing the dmg is separate from signing the app inside it; without it the
# download itself is unsigned even though what it installs is not.
if [[ -n "$identity" ]]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
fi
printf 'Built %s\n' "$dmg"
