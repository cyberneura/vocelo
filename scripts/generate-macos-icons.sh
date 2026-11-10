#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Only needed when the vector source changes: rsvg-convert -o resources/app-icons/mac-original.png resources/app-icons/mac-original.svg
swift scripts/prepare-macos-icons.swift resources/app-icons/layout.json
swift scripts/macos-icon.swift build resources/app-icons/AppIcon.iconset packaging/icons Vocelo
