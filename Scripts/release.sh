#!/bin/bash
# Build an unsigned (ad-hoc signed) release DMG for a GitHub release.
#
#   Scripts/release.sh [version]
#
# "Unsigned" means ad-hoc, not signature-free: arm64 refuses to execute a
# binary with no signature at all, so `-` is the minimum that runs anywhere.
#
# What this CANNOT do is get past Gatekeeper — see README's install section.
# Ad-hoc also cannot carry the App Group entitlement, which is why the snapshot
# is written to the widget's own container as well; see docs/data-channel.md.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(date +%Y.%m.%d)}"
BUILD="build/release"
STAGE="$BUILD/dmg"
DMG="build/AIUsage-$VERSION.dmg"

rm -rf "$BUILD" "$DMG"
mkdir -p "$STAGE"

echo "==> building $VERSION"
xcodebuild \
    -project AIUsageWidget.xcodeproj \
    -scheme AIUsage \
    -configuration Release \
    -derivedDataPath "$BUILD/dd" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    MARKETING_VERSION="$VERSION" \
    build | grep -E "error:|warning: .*deprecated|\*\* BUILD" || true

APP="$BUILD/dd/Build/Products/Release/AI Usage.app"
[ -d "$APP" ] || { echo "build produced no app at $APP" >&2; exit 1; }

# The scheme's post-action installs to /Applications for the widget gallery.
# That is a development convenience and has nothing to do with the release.
echo "==> staging"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> verifying the signature is at least ad-hoc"
codesign --verify --deep --strict "$STAGE/AI Usage.app"

echo "==> packaging"
hdiutil create \
    -volname "AI Usage" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

echo
echo "$DMG"
echo "  $(du -h "$DMG" | cut -f1)"
echo
echo "Publish with:"
echo "  gh release create v$VERSION \"$DMG\" --notes-file docs/release-notes.md"
