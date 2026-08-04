#!/bin/bash
# Builds Swift Paste and assembles a runnable .app bundle.
#
#   ./build.sh               release build -> ./build/Swift Paste.app
#   ./build.sh --install     also copies it into /Applications and relaunches it
#   ./build.sh --reset-perms clears the stale Accessibility grant, then builds and installs
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Swift Paste"
BUNDLE="build/${APP_NAME}.app"
BIN_NAME="SwiftPaste"
BUNDLE_ID="io.bytezero.SwiftPaste"

MODE="${1:-}"

# Rebuilding changes the ad-hoc code signature, so an existing Accessibility toggle
# keeps showing as ON while macOS no longer trusts the new binary. Clearing the entry
# makes the system prompt again on next launch.
if [ "$MODE" = "--reset-perms" ]; then
    echo "==> Resetting Accessibility approval for ${BUNDLE_ID}"
    tccutil reset Accessibility "$BUNDLE_ID" || true
    MODE="--install"
fi

echo "==> Compiling (release)"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${BIN_NAME}"
[ -f "$BIN_PATH" ] || { echo "build failed: ${BIN_PATH} missing"; exit 1; }

echo "==> Assembling ${BUNDLE}"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"
cp "$BIN_PATH" "${BUNDLE}/Contents/MacOS/${BIN_NAME}"
cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"

# Regenerate the artwork from Resources/logo.svg when it's missing.
if [ ! -f Resources/AppIcon.icns ] || [ ! -f Resources/MenuBarIcon.png ]; then
    echo "==> Rendering icon and menu bar glyph from logo.svg"
    swift Tools/make-icon.swift > /dev/null
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "${BUNDLE}/Contents/Resources/AppIcon.icns"
cp Resources/MenuBarIcon.png "${BUNDLE}/Contents/Resources/MenuBarIcon.png"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

# Ad-hoc signature with a stable identifier so macOS keeps the Accessibility grant
# across rebuilds.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --identifier io.bytezero.SwiftPaste "$BUNDLE"

echo "==> Built ${BUNDLE}"

if [ "$MODE" = "--install" ]; then
    echo "==> Installing to /Applications"
    pkill -f "/Applications/${APP_NAME}.app" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$BUNDLE" "/Applications/${APP_NAME}.app"
    open "/Applications/${APP_NAME}.app"
    echo "==> Running from /Applications"
fi
