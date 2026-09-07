#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
args=(--disable-sandbox --scratch-path "${BUILD_PATH:-.build}"
    -debug-info-format "${DEBUG_INFO_FORMAT:-dwarf}")
developer_dir=$(xcode-select -p)
# Some standalone Command Line Tools releases omit these Testing search paths.
frameworks="$developer_dir/Library/Developer/Frameworks"
interop="$developer_dir/Library/Developer/usr/lib"
if [[ -d "$frameworks/Testing.framework" ]]; then
    args+=(-Xswiftc -F -Xswiftc "$frameworks"
        -Xlinker -F -Xlinker "$frameworks"
        -Xlinker -rpath -Xlinker "$frameworks"
        -Xlinker -rpath -Xlinker "$interop")
fi
swift test "${args[@]}" "$@"
