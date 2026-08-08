#!/bin/bash
# One pass over everything that needs the real screen: stills, clips, then the
# site assets that depend on them.
#
#   Tools/capture-all.sh
#
# Takes over the pointer and the keyboard for roughly ten minutes. Do not use the
# Mac while it runs — a stray click dismisses the popup mid-capture.
set -uo pipefail

cd "$(dirname "$0")/.."

DRIVER=build/uidriver

# ---------------------------------------------------------------- clean data

# The history is re-seeded here rather than trusted from an earlier run. Swift
# Paste records everything copied while it is running, so a demo seeded even an
# hour ago is already buried under real clipboard content — which would then be
# published in a screenshot.
echo "==> Re-seeding the demo history"
Tools/demo.sh on >/dev/null 2>&1 || { echo "could not seed the demo history" >&2; exit 1; }

COUNT=$(python3 -c "import json;print(len(json.load(open('$HOME/Library/Application Support/SwiftPaste/history.json'))))" 2>/dev/null || echo 0)
if [ "$COUNT" -lt 5 ] || [ "$COUNT" -gt 40 ]; then
    echo "history has $COUNT entries — expected the 17 demo ones. Stopping." >&2
    exit 1
fi
echo "    $COUNT demo entries loaded"

if ! pgrep -x SwiftPaste >/dev/null; then
    echo "Swift Paste is not running." >&2
    exit 1
fi

# ---------------------------------------------------------------- appearance

# The brand is white, so everything is shot in Light appearance whatever the Mac
# is set to. Restored on the way out, including on failure or Ctrl-C.
ORIGINAL_APPEARANCE=$(defaults read -g AppleInterfaceStyle 2>/dev/null || echo "Light")

set_appearance() {
    osascript -e "tell application \"System Events\" to tell appearance preferences \
        to set dark mode to $1" >/dev/null 2>&1
}

cleanup() {
    if [ "$ORIGINAL_APPEARANCE" = "Dark" ]; then set_appearance true; else set_appearance false; fi
}
trap cleanup EXIT INT TERM

if [ "$ORIGINAL_APPEARANCE" = "Dark" ]; then
    echo "==> Switching to Light appearance (restored afterwards)"
    set_appearance false
    sleep 2.0
fi

echo
echo "Starting in 5 seconds. Hands off the keyboard and trackpad until it finishes."
for n in 5 4 3 2 1; do printf '\r  %d ' "$n"; sleep 1; done
printf '\r      \n\n'

echo "=== 1/3  Screenshots ==="
Tools/screenshots.sh
echo

echo "=== 2/3  Screen recordings ==="
Tools/record.sh
echo

echo "=== 3/3  Site assets ==="
Tools/build-site.sh
echo

echo "Done."
echo "  assets/screenshots/  $(ls -1 assets/screenshots 2>/dev/null | wc -l | tr -d ' ') files"
echo "  assets/video/        $(ls -1 assets/video 2>/dev/null | wc -l | tr -d ' ') files"
echo
echo "Run Tools/demo.sh off to get your real clipboard history back."
