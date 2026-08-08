#!/bin/bash
# Puts the app into a state worth photographing, then puts it back.
#
#   Tools/demo.sh on      quit the app, seed the demo history, relaunch
#   Tools/demo.sh off     quit the app, restore the real history, relaunch
#
# The app keeps the history in memory and writes it out on a timer, so it has to
# be stopped before anything touches history.json — otherwise it saves over the
# seed a second later.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="Swift Paste"
INSTALLED="/Applications/${APP}.app"
LOCAL="build/${APP}.app"

quit_app() {
    osascript -e "tell application \"${APP}\" to quit" 2>/dev/null || true
    pkill -x SwiftPaste 2>/dev/null || true
    # Give the app a moment to finish its final saveNow() before we overwrite the file.
    for _ in $(seq 1 20); do
        pgrep -x SwiftPaste >/dev/null || break
        sleep 0.2
    done
    pkill -9 -x SwiftPaste 2>/dev/null || true
    sleep 0.4
}

launch_app() {
    if [ -d "$INSTALLED" ]; then
        open "$INSTALLED"
    elif [ -d "$LOCAL" ]; then
        open "$LOCAL"
    else
        echo "no app bundle found — run ./build.sh first" >&2
        exit 1
    fi
    sleep 1.5
}

case "${1:-on}" in
    on)
        echo "==> Stopping ${APP}"
        quit_app
        echo "==> Seeding demo history"
        swift Tools/seed-demo.swift
        # Pin the preferences the settings screenshots show, so a stray keystroke
        # from an earlier capture cannot leave an odd value like "keep at most 525"
        # in a published image. Written while the app is stopped, or it would save
        # its in-memory copy back over them.
        echo "==> Resetting demo preferences"
        defaults write io.bytezero.SwiftPaste maxItems -int 300
        defaults write io.bytezero.SwiftPaste unlimitedItems -bool false
        defaults write io.bytezero.SwiftPaste expirySeconds -int 0
        defaults write io.bytezero.SwiftPaste hotKeyModifier -string option
        defaults write io.bytezero.SwiftPaste pasteBehaviour -string pasteIntoApp
        defaults write io.bytezero.SwiftPaste pastePlainText -bool false
        defaults write io.bytezero.SwiftPaste captureImages -bool true
        defaults write io.bytezero.SwiftPaste showSourceApp -bool true
        defaults write io.bytezero.SwiftPaste quickPastePrevious -bool true
        echo "==> Relaunching"
        launch_app
        echo "==> Demo history is live. Tools/demo.sh off puts your real one back."
        ;;
    off)
        echo "==> Stopping ${APP}"
        quit_app
        echo "==> Restoring real history"
        swift Tools/seed-demo.swift restore
        echo "==> Relaunching"
        launch_app
        echo "==> Your real history is back."
        ;;
    *)
        echo "usage: Tools/demo.sh [on|off]" >&2
        exit 2
        ;;
esac
