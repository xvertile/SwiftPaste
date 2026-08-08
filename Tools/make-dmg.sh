#!/bin/bash
# Packages the built app as a DMG that opens with the app beside an Applications
# shortcut, so installing is one drag.
#
#   Tools/make-dmg.sh              -> build/SwiftPaste.dmg
#   Tools/make-dmg.sh out.dmg
#
# Deliberately avoids AppleScript window styling: that needs a logged-in Finder
# and fails on a CI runner, which is where the published builds come from.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Swift Paste"
VOLUME_NAME="Swift Paste"
APP="build/${APP_NAME}.app"
OUTPUT="${1:-build/SwiftPaste.dmg}"
STAGING="build/dmg-staging"

[ -d "$APP" ] || { echo "no app at $APP — run ./build.sh first" >&2; exit 1; }

echo "==> Staging"
rm -rf "$STAGING" "$OUTPUT"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Gives the mounted volume the app's own icon instead of the generic disk.
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$STAGING/.VolumeIcon.icns"
fi

echo "==> Building ${OUTPUT}"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO -imagekey zlib-level=9 \
    "$OUTPUT" >/dev/null

rm -rf "$STAGING"

SIZE=$(du -h "$OUTPUT" | cut -f1 | tr -d ' ')
echo "==> Built ${OUTPUT} (${SIZE})"
