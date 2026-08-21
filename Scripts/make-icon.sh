#!/bin/bash
# Regenerate the app icon from Scripts/make-icon.swift into the asset catalog.
set -euo pipefail
cd "$(dirname "$0")/.."
SET="App/Assets.xcassets/AppIcon.appiconset"

swift Scripts/make-icon.swift "$SET/icon_1024.png"
for size in 16 32 64 128 256 512; do
    sips -Z "$size" "$SET/icon_1024.png" --out "$SET/icon_$size.png" >/dev/null
done
echo "regenerated $(ls "$SET" | grep -c '\.png$') sizes in $SET"
