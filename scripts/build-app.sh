#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
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
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
if [[ ${#binaries[@]} == 2 ]]; then
    lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Vocelo"
else
    cp "${binaries[0]}" "$app/Contents/MacOS/Vocelo"
fi
cp Info.plist "$app/Contents/Info.plist"
# Ad-hoc signing supports local testing. Release signing is done separately.
codesign --force --sign - --options runtime --entitlements Vocelo.entitlements "$app"
codesign --verify --strict --verbose=2 "$app"
printf 'Built %s\n' "$app"
