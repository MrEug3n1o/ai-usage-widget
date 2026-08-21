#!/bin/bash
# Regenerate the app icon from Scripts/make-icon.swift into both asset
# catalogs: the app's, and the widget extension's — some macOS surfaces look
# for a widget's icon on the extension rather than on the containing app.
set -euo pipefail
cd "$(dirname "$0")/.."

SETS=(
    "App/Assets.xcassets/AppIcon.appiconset"
    "WidgetExtension/Assets.xcassets/AppIcon.appiconset"
)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swift Scripts/make-icon.swift "$TMP/icon_1024.png"

for set in "${SETS[@]}"; do
    cp "$TMP/icon_1024.png" "$set/icon_1024.png"
    for size in 16 32 64 128 256 512; do
        sips -Z "$size" "$set/icon_1024.png" --out "$set/icon_$size.png" >/dev/null
    done
    echo "regenerated $set"
done
