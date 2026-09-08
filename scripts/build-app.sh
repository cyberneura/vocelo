#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# VERSION is the single source of truth: the workflow releases whatever version is
# in it, so the bundle has to carry the same number.
version=$(tr -d '[:space:]' < VERSION)
if [[ -z "$version" ]]; then
    echo "VERSION is empty" >&2
    exit 1
fi
# BUILD_PATH can redirect SwiftPM output in CI or restricted environments.
build_args=(-c release --disable-sandbox --scratch-path "${BUILD_PATH:-.build}"
    -debug-info-format "${DEBUG_INFO_FORMAT:-dwarf}")
binaries=()
if [[ "${ARCHS:-native}" == universal ]]; then
    # Separate builds + lipo also work with Command Line Tools (no Xcode IDE).
    for arch in arm64 x86_64; do
        swift build "${build_args[@]}" --triple "$arch-apple-macosx14.0"
        bin_dir=$(swift build "${build_args[@]}" --triple "$arch-apple-macosx14.0" --show-bin-path)
        binaries+=("$bin_dir/Vocelo")
    done
else
    swift build "${build_args[@]}"
    bin_dir=$(swift build "${build_args[@]}" --show-bin-path)
    binaries+=("$bin_dir/Vocelo")
fi
app="$PWD/dist/Vocelo.app"
# Assembled into an empty bundle: a stapled ticket or a file left by an earlier
# build would otherwise ride along into the dmg.
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ ${#binaries[@]} == 2 ]]; then
    lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Vocelo"
else
    cp "${binaries[0]}" "$app/Contents/MacOS/Vocelo"
fi
# Matched with the surrounding element rather than on the bare word, so the comment
# in Info.plist that names the placeholder survives.
sed "s|<string>__VERSION__</string>|<string>$version</string>|g" Info.plist \
    > "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" > /dev/null
if grep -q "<string>__VERSION__</string>" "$app/Contents/Info.plist"; then
    echo "the version placeholder is still in the built Info.plist" >&2
    exit 1
fi
# Ad-hoc signing changes the code hash on every build, so macOS asks for the privacy
# permissions again each time. Set SIGN_IDENTITY to a stable certificate (for example
# the Developer ID Application identity) to keep permissions across rebuilds.
identity="${SIGN_IDENTITY:--}"
sign_args=(--force --sign "$identity" --options runtime --entitlements Vocelo.entitlements)
if [[ "$identity" != "-" ]]; then sign_args+=(--timestamp); fi
codesign "${sign_args[@]}" "$app"
codesign --verify --strict --verbose=2 "$app"
printf 'Built %s (%s)\n' "$app" "$version"
